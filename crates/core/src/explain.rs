//! Why did a value change? Attribution of the last step's change to the inputs that moved.
//!
//! For a value computed by a formula, the change from the previous step is split by
//! asking, for each input in turn, what the formula would have given this step if only
//! that input had kept last step's value. The difference is that input's effect. For a
//! formula that adds and subtracts its inputs the effects sum exactly to the change;
//! otherwise the part that no single input explains (their interaction) is reported as a
//! remainder, never hidden. For an account the change is split into the flows that
//! entered and left it, which is always exact.
//!
//! Explanations observe a run and never change it. They need [`Simulation::set_tracing`]
//! and are available two steps after tracing starts.

use crate::error::{Error, Result, model_err};
use crate::model::Kind;
use crate::program::{Col, Op, Program, Val};
use crate::sim::{Simulation, Snapshot};
use crate::vm::{self, EvalCtx, Swap};

/// A number as the explanation reports it: whole numbers exactly, reals as reals.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Num {
    Int(i128),
    Real(f64),
}

impl Num {
    pub fn as_f64(self) -> f64 {
        match self {
            Num::Int(v) => v as f64,
            Num::Real(v) => v,
        }
    }

    fn minus(self, other: Num) -> Num {
        match (self, other) {
            (Num::Int(a), Num::Int(b)) => Num::Int(a - b),
            (a, b) => Num::Real(a.as_f64() - b.as_f64()),
        }
    }

    pub fn is_zero(self) -> bool {
        match self {
            Num::Int(v) => v == 0,
            Num::Real(v) => v == 0.0,
        }
    }
}

/// One input's share of a change.
#[derive(Clone, Debug, PartialEq)]
pub struct Part {
    /// What a person reads: the input's name, "<name> (last month)" for a value read
    /// through `prev()`, or "random draws".
    pub label: String,
    /// The symbol to explain next, if any.
    pub symbol: Option<String>,
    /// True for a value read through `prev()`.
    pub lagged: bool,
    /// How much of the change this input accounts for. `None` when the formula could not
    /// be evaluated with this input held back (the remainder then covers it).
    pub effect: Option<Num>,
    /// The input's value this step and last step: totals for per-record values.
    pub now: Option<Num>,
    pub before: Option<Num>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Explanation {
    pub name: String,
    pub kind: Kind,
    /// Index of the step explained (the last one completed).
    pub step: u64,
    /// For a per-record value, the entity whose records are totalled (weighted).
    pub entity: Option<String>,
    pub now: Num,
    pub before: Num,
    pub change: Num,
    /// Largest effects first.
    pub parts: Vec<Part>,
    /// Change not attributed to any single part.
    pub remainder: Num,
    /// A sentence when there is nothing to break down (a lever, a constant).
    pub note: Option<String>,
}

/// Weighted total of a per-record column, or the value itself for a national one.
fn total(value: &Val) -> Num {
    match value {
        Val::I(v) => Num::Int(*v as i128),
        Val::F(v) => Num::Real(*v),
        Val::B(v) => Num::Int(*v as i128),
    }
}

fn column_total(column: &Col, weights: &[i64]) -> Num {
    match column {
        Col::I(c) => Num::Int(c.iter().zip(weights).map(|(v, w)| *v as i128 * *w as i128).sum()),
        Col::F(c) => {
            let mut acc = 0.0;
            for (v, w) in c.iter().zip(weights) {
                acc += *w as f64 * *v;
            }
            Num::Real(acc)
        }
        Col::B(c) => Num::Int(c.iter().zip(weights).filter(|(v, _)| **v).map(|(_, w)| *w as i128).sum()),
    }
}

fn uses_random(prog: &Program) -> bool {
    prog.ops.iter().any(|op| matches!(op, Op::Rand(..)))
        || prog.aggs.iter().any(|a| uses_random(&a.prog))
        || prog.tables.iter().flat_map(|t| t.lows.iter().chain(&t.rates)).any(uses_random)
}

/// The values a formula of phase `phase` read during the step that ended in `end`, given
/// `before`, the state at the end of the step before that. Accounts are read at their
/// start-of-step value, and so are states that had not yet been updated.
struct Context {
    scal: Vec<Val>,
    cols: Vec<Col>,
    step: u32,
}

impl Simulation {
    fn context(&self, end: &Snapshot, before: &Snapshot, phase: usize) -> Context {
        let mut scal = end.scal.clone();
        let mut cols = end.cols.clone();
        for (id, d) in self.model().symbols.iter().enumerate() {
            let old = match d.kind {
                Kind::Account => true,
                Kind::State => d.phase.is_some_and(|p| p >= phase),
                _ => false,
            };
            if old {
                if d.columnar() {
                    cols[id].clone_from(&before.cols[id]);
                } else {
                    scal[id] = before.scal[id];
                }
            }
        }
        Context { scal, cols, step: (end.steps_done - 1) as u32 }
    }

    fn total_in(&self, id: usize, scal: &[Val], cols: &[Col]) -> Num {
        let d = &self.model().symbols[id];
        if !d.dims.is_empty() {
            // Format 1: a dimensioned input is measured by its sum over every cell.
            return column_total(&cols[id], &vec![1; cols[id].len()]);
        }
        match d.entity {
            None => total(&scal[id]),
            Some(entity) => column_total(&cols[id], &self.weights_in(cols)[entity]),
        }
    }

    /// Runs symbol `id`'s formula in a context, optionally holding one input back.
    fn run(&self, id: usize, cx: &Context, prev: &Snapshot, swap: Option<Swap>, step: u32) -> Option<Num> {
        let prog = self.progs_of(id)?;
        let model = self.model();
        let weights = self.weights_in(&cx.cols);
        let eval = EvalCtx {
            scal: &cx.scal,
            cols: &cx.cols,
            prev_scal: &prev.scal,
            prev_cols: &prev.cols,
            entities: &model.entities,
            weights: &weights,
            seed: self.seed(),
            step,
            swap,
        };
        if !model.symbols[id].dims.is_empty() {
            return None;
        }
        match model.symbols[id].entity {
            None => vm::eval_scalar(prog, &eval).ok().map(|v| total(&v)),
            Some(entity) => vm::eval_column(prog, entity, &eval).ok().map(|c| column_total(&c, &weights[entity])),
        }
    }

    /// Explains the change in `name` over the last completed step.
    pub fn explain(&self, name: &str) -> Result<Explanation> {
        let model = self.model();
        let Some(&id) = model.sym_index.get(name) else { return model_err(format!("unknown name {name:?}")) };
        let d = &model.symbols[id];
        let snaps = &self.snapshots;
        if !d.dims.is_empty() {
            return Err(Error::Model(format!(
                "{name} has dimensions; explanations of dimensioned values are not in format 1"
            )));
        }
        if !self.is_tracing() {
            return Err(Error::Model("explanations need tracing to be turned on".to_string()));
        }
        let wanted = if d.kind == Kind::Account { 2 } else { 3 };
        if snaps.len() < wanted || snaps[0].steps_done == 0 {
            return Err(Error::Model("not enough history yet: advance at least two steps".to_string()));
        }
        let (end, mid) = (&snaps[0], &snaps[1]);
        let entity = d.entity.map(|e| model.entities[e].name.clone());
        let now = self.total_in(id, &end.scal, &end.cols);
        let before = self.total_in(id, &mid.scal, &mid.cols);
        let change = now.minus(before);
        let mut explanation = Explanation {
            name: d.name.clone(),
            kind: d.kind,
            step: end.steps_done - 1,
            entity,
            now,
            before,
            change,
            parts: Vec::new(),
            remainder: change,
            note: None,
        };

        match d.kind {
            Kind::State if d.rake.is_some() => {
                explanation.note = Some("set by raking the weights to their targets".to_string())
            }
            Kind::Lever => explanation.note = Some("set by the player".to_string()),
            Kind::Param | Kind::Column => explanation.note = Some("fixed for the whole run".to_string()),
            Kind::Account => {
                for flow in &model.flows {
                    let sign = if flow.src_account == id {
                        -1
                    } else if flow.dst_account == id {
                        1
                    } else {
                        continue;
                    };
                    let amount = self.total_in(flow.sym, &end.scal, &end.cols);
                    let Num::Int(amount) = amount else { continue };
                    let flow_name = &model.symbols[flow.sym].name;
                    explanation.parts.push(Part {
                        label: flow_name.clone(),
                        symbol: Some(flow_name.clone()),
                        lagged: false,
                        effect: Some(Num::Int(sign * amount)),
                        now: Some(Num::Int(amount)),
                        before: Some(self.total_in(flow.sym, &mid.scal, &mid.cols)),
                    });
                }
            }
            Kind::Var | Kind::Flow | Kind::State => {
                let early = &snaps[2];
                let phase = d.phase.unwrap_or(0);
                let now_cx = self.context(end, mid, phase);
                let before_cx = self.context(mid, early, phase);
                let Some(reproduced) = self.run(id, &now_cx, mid, None, now_cx.step) else {
                    return Err(Error::Model(format!("{name}: the formula could not be re-evaluated")));
                };
                if reproduced != now {
                    return Err(Error::Model(format!("{name}: re-evaluation does not reproduce the stored value")));
                }
                let mut inputs: Vec<(usize, bool)> = Vec::new();
                for &input in &self.deps[id] {
                    inputs.push((input, false));
                }
                for &input in &self.lagged_deps[id] {
                    inputs.push((input, true));
                }
                for (input, lagged) in inputs {
                    let s = &model.symbols[input];
                    if matches!(s.kind, Kind::Param | Kind::Column) {
                        continue;
                    }
                    let (alt_scal, alt_cols) =
                        if lagged { (&early.scal, &early.cols) } else { (&before_cx.scal, &before_cx.cols) };
                    let swap = Swap { sym: input as u32, lagged, scal: alt_scal, cols: alt_cols };
                    let held = self.run(id, &now_cx, mid, Some(swap), now_cx.step);
                    let (input_now, input_before) = if lagged {
                        (self.total_in(input, &mid.scal, &mid.cols), self.total_in(input, &early.scal, &early.cols))
                    } else {
                        (
                            self.total_in(input, &now_cx.scal, &now_cx.cols),
                            self.total_in(input, &before_cx.scal, &before_cx.cols),
                        )
                    };
                    explanation.parts.push(Part {
                        label: if lagged { format!("{} (last step)", s.name) } else { s.name.clone() },
                        symbol: Some(s.name.clone()),
                        lagged,
                        effect: held.map(|h| now.minus(h)),
                        now: Some(input_now),
                        before: Some(input_before),
                    });
                }
                if self.progs_of(id).is_some_and(uses_random) {
                    let held = self.run(id, &now_cx, mid, None, before_cx.step);
                    explanation.parts.push(Part {
                        label: "random draws".to_string(),
                        symbol: None,
                        lagged: false,
                        effect: held.map(|h| now.minus(h)),
                        now: None,
                        before: None,
                    });
                }
            }
        }

        let mut remainder = change;
        for part in &explanation.parts {
            if let Some(effect) = part.effect {
                remainder = remainder.minus(effect);
            }
        }
        explanation.remainder = remainder;
        // Largest effect first; parts that could not be isolated last; ties by label.
        explanation.parts.sort_by(|a, b| {
            let size = |p: &Part| p.effect.map(|e| e.as_f64().abs()).unwrap_or(-1.0);
            size(b).total_cmp(&size(a)).then_with(|| a.label.cmp(&b.label))
        });
        Ok(explanation)
    }
}

#[cfg(test)]
mod tests {
    use super::Num;

    #[test]
    fn arithmetic() {
        assert_eq!(Num::Int(5).minus(Num::Int(7)), Num::Int(-2));
        assert_eq!(Num::Int(5).minus(Num::Real(0.5)), Num::Real(4.5));
        assert!(Num::Real(0.0).is_zero());
    }
}
