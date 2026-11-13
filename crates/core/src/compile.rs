//! Type and unit checking, and translation of a syntax tree into bytecode.
//!
//! This is a port of the oracle's `_Builder` (oracle/polisim_oracle/expr.py). It must
//! accept and reject exactly the same formulas; conformance/cases.tsv holds it to that.

use std::collections::BTreeSet;

use crate::error::{Error, Result};
use crate::model::{Kind, Model};
use crate::program::{Agg, AggKind, Cmp, Compiled, Op, Program, R, Rounding, Src, TableUse, Ty};
use crate::syntax::{BinOp, Node, parse};
use crate::units::{self, Unit};

struct Built {
    ty: Ty,
    unit: Option<Unit>, // None only for the literal zero, which fits any unit
    reg: R,
}

type Check<T> = std::result::Result<T, String>;

struct Builder<'a> {
    model: &'a Model,
    deps: &'a mut BTreeSet<usize>,
    lagged: &'a mut BTreeSet<usize>,
    ops: Vec<Op>,
    n_i: u32,
    n_f: u32,
    n_b: u32,
    aggs: Vec<Agg>,
    tables: Vec<TableUse>,
}

fn number(b: &Built, what: &str) -> Check<()> {
    if b.ty == Ty::Bool {
        return Err(format!("{what} needs a number, not a true/false value"));
    }
    Ok(())
}

fn boolean(b: &Built, what: &str) -> Check<()> {
    if b.ty != Ty::Bool {
        return Err(format!("{what} needs a true/false value, not a number"));
    }
    Ok(())
}

fn arg_count(fname: &str, args: &[Node], count: usize) -> Check<()> {
    if args.len() != count {
        return Err(format!("{fname}() takes {count} argument(s), got {}", args.len()));
    }
    Ok(())
}

impl<'a> Builder<'a> {
    fn new(model: &'a Model, deps: &'a mut BTreeSet<usize>, lagged: &'a mut BTreeSet<usize>) -> Builder<'a> {
        Builder { model, deps, lagged, ops: Vec::new(), n_i: 0, n_f: 0, n_b: 0, aggs: Vec::new(), tables: Vec::new() }
    }

    fn finish(self, result: &Built) -> Check<Program> {
        let narrow = |n: u32| u16::try_from(n).map_err(|_| "formula is too large".to_string());
        Ok(Program {
            ops: self.ops,
            n_i: narrow(self.n_i)?,
            n_f: narrow(self.n_f)?,
            n_b: narrow(self.n_b)?,
            result: result.reg,
            ty: result.ty,
            aggs: self.aggs,
            tables: self.tables,
        })
    }

    fn reg(&mut self, ty: Ty) -> R {
        let counter = match ty {
            Ty::Int => &mut self.n_i,
            Ty::Real => &mut self.n_f,
            Ty::Bool => &mut self.n_b,
        };
        *counter += 1;
        // Saturates here and is reported by `finish`; a formula never gets this large.
        (*counter - 1).min(u16::MAX as u32) as R
    }

    /// Register holding `b` as a real, converting a whole number if needed.
    fn as_real(&mut self, b: &Built) -> R {
        if b.ty == Ty::Real {
            return b.reg;
        }
        let d = self.reg(Ty::Real);
        self.ops.push(Op::IToF(d, b.reg));
        d
    }

    // ---------------------------------------------------------------- leaves

    fn build(&mut self, node: &Node, ctx: Option<usize>) -> Check<Built> {
        match node {
            Node::Int(v) => {
                let d = self.reg(Ty::Int);
                self.ops.push(Op::ConstI(d, *v));
                Ok(Built { ty: Ty::Int, unit: if *v == 0 { None } else { Some(Unit::one()) }, reg: d })
            }
            Node::Real(v) => {
                let d = self.reg(Ty::Real);
                self.ops.push(Op::ConstF(d, *v));
                Ok(Built { ty: Ty::Real, unit: if *v == 0.0 { None } else { Some(Unit::one()) }, reg: d })
            }
            Node::Bool(v) => {
                let d = self.reg(Ty::Bool);
                self.ops.push(Op::ConstB(d, *v));
                Ok(Built { ty: Ty::Bool, unit: Some(Unit::one()), reg: d })
            }
            Node::Name(name) => self.name(name, ctx, false),
            Node::Neg(a) => {
                let a = self.build(a, ctx)?;
                number(&a, "unary minus")?;
                let d = self.reg(a.ty);
                self.ops.push(if a.ty == Ty::Int { Op::NegI(d, a.reg) } else { Op::NegF(d, a.reg) });
                Ok(Built { ty: a.ty, unit: a.unit, reg: d })
            }
            Node::Not(a) => {
                let a = self.build(a, ctx)?;
                boolean(&a, "not")?;
                let d = self.reg(Ty::Bool);
                self.ops.push(Op::NotB(d, a.reg));
                Ok(Built { ty: Ty::Bool, unit: Some(Unit::one()), reg: d })
            }
            Node::Bin(op, a, b) => {
                let a = self.build(a, ctx)?;
                let b = self.build(b, ctx)?;
                self.binary(*op, a, b)
            }
            Node::Call(fname, args) => self.call(fname, args, ctx),
        }
    }

    fn name(&mut self, name: &str, ctx: Option<usize>, lagged: bool) -> Check<Built> {
        let Some(&id) = self.model.sym_index.get(name) else {
            return Err(format!("unknown name {name:?}"));
        };
        if lagged {
            self.lagged.insert(id);
        } else {
            self.deps.insert(id);
        }
        let sym = &self.model.symbols[id];
        let src = Src { sym: id as u32, lagged };
        let d = self.reg(sym.ty);
        match sym.entity {
            None => self.ops.push(match sym.ty {
                Ty::Int => Op::LoadSI(d, src),
                Ty::Real => Op::LoadSF(d, src),
                Ty::Bool => Op::LoadSB(d, src),
            }),
            Some(entity) => {
                if ctx != Some(entity) {
                    let entity = &self.model.entities[entity].name;
                    return Err(format!("{name:?} holds one value per {entity}; aggregate it with wsum() or wcount()"));
                }
                self.ops.push(match sym.ty {
                    Ty::Int => Op::LoadCI(d, src),
                    Ty::Real => Op::LoadCF(d, src),
                    Ty::Bool => Op::LoadCB(d, src),
                });
            }
        }
        Ok(Built { ty: sym.ty, unit: Some(sym.unit.clone()), reg: d })
    }

    // ---------------------------------------------------------------- operators

    fn binary(&mut self, op: BinOp, a: Built, b: Built) -> Check<Built> {
        let sym = op.symbol();
        if matches!(op, BinOp::And | BinOp::Or) {
            boolean(&a, sym)?;
            boolean(&b, sym)?;
            let d = self.reg(Ty::Bool);
            self.ops.push(if op == BinOp::And { Op::AndB(d, a.reg, b.reg) } else { Op::OrB(d, a.reg, b.reg) });
            return Ok(Built { ty: Ty::Bool, unit: Some(Unit::one()), reg: d });
        }

        let compare = match op {
            BinOp::Lt => Some(Cmp::Lt),
            BinOp::Le => Some(Cmp::Le),
            BinOp::Gt => Some(Cmp::Gt),
            BinOp::Ge => Some(Cmp::Ge),
            BinOp::Eq => Some(Cmp::Eq),
            BinOp::Ne => Some(Cmp::Ne),
            _ => None,
        };
        if let Some(cmp) = compare {
            let d;
            if a.ty == Ty::Bool || b.ty == Ty::Bool {
                if !(a.ty == b.ty && matches!(op, BinOp::Eq | BinOp::Ne)) {
                    return Err(format!("cannot compare {} with {} using {sym}", a.ty.name(), b.ty.name()));
                }
                d = self.reg(Ty::Bool);
                self.ops.push(Op::CmpB(op == BinOp::Eq, d, a.reg, b.reg));
            } else {
                units::unify(&a.unit, &b.unit, &format!("comparison {sym}"))?;
                if a.ty == Ty::Int && b.ty == Ty::Int {
                    d = self.reg(Ty::Bool);
                    self.ops.push(Op::CmpI(cmp, d, a.reg, b.reg));
                } else {
                    let (x, y) = (self.as_real(&a), self.as_real(&b));
                    d = self.reg(Ty::Bool);
                    self.ops.push(Op::CmpF(cmp, d, x, y));
                }
            }
            return Ok(Built { ty: Ty::Bool, unit: Some(Unit::one()), reg: d });
        }

        number(&a, &format!("operator {sym}"))?;
        number(&b, &format!("operator {sym}"))?;
        let unit = match op {
            BinOp::Add | BinOp::Sub => units::unify(&a.unit, &b.unit, &format!("operator {sym}"))?,
            BinOp::Mul => Some(units::mul(&a.unit, &b.unit)),
            _ => Some(units::div(&a.unit, &b.unit)),
        };
        if op == BinOp::Div {
            let (x, y) = (self.as_real(&a), self.as_real(&b));
            let d = self.reg(Ty::Real);
            self.ops.push(Op::DivF(d, x, y));
            return Ok(Built { ty: Ty::Real, unit, reg: d });
        }
        if a.ty == Ty::Int && b.ty == Ty::Int {
            let d = self.reg(Ty::Int);
            self.ops.push(match op {
                BinOp::Add => Op::AddI(d, a.reg, b.reg),
                BinOp::Sub => Op::SubI(d, a.reg, b.reg),
                _ => Op::MulI(d, a.reg, b.reg),
            });
            return Ok(Built { ty: Ty::Int, unit, reg: d });
        }
        let (x, y) = (self.as_real(&a), self.as_real(&b));
        let d = self.reg(Ty::Real);
        self.ops.push(match op {
            BinOp::Add => Op::AddF(d, x, y),
            BinOp::Sub => Op::SubF(d, x, y),
            _ => Op::MulF(d, x, y),
        });
        Ok(Built { ty: Ty::Real, unit, reg: d })
    }

    // ---------------------------------------------------------------- functions

    fn call(&mut self, fname: &str, args: &[Node], ctx: Option<usize>) -> Check<Built> {
        match fname {
            "min" | "max" => {
                arg_count(fname, args, 2)?;
                let (ty, unit, r) = self.numeric_group(fname, args, ctx)?;
                let d = self.reg(ty);
                self.ops.push(match (fname, ty) {
                    ("min", Ty::Int) => Op::MinI(d, r[0], r[1]),
                    ("min", _) => Op::MinF(d, r[0], r[1]),
                    (_, Ty::Int) => Op::MaxI(d, r[0], r[1]),
                    _ => Op::MaxF(d, r[0], r[1]),
                });
                Ok(Built { ty, unit, reg: d })
            }
            "clamp" => {
                arg_count(fname, args, 3)?;
                let (ty, unit, r) = self.numeric_group(fname, args, ctx)?;
                let d = self.reg(ty);
                self.ops.push(if ty == Ty::Int {
                    Op::ClampI(d, r[0], r[1], r[2])
                } else {
                    Op::ClampF(d, r[0], r[1], r[2])
                });
                Ok(Built { ty, unit, reg: d })
            }
            "abs" => {
                arg_count(fname, args, 1)?;
                let a = self.build(&args[0], ctx)?;
                number(&a, "abs()")?;
                let d = self.reg(a.ty);
                self.ops.push(if a.ty == Ty::Int { Op::AbsI(d, a.reg) } else { Op::AbsF(d, a.reg) });
                Ok(Built { ty: a.ty, unit: a.unit, reg: d })
            }
            "round" | "floor" | "ceil" => {
                arg_count(fname, args, 1)?;
                let a = self.build(&args[0], ctx)?;
                number(&a, &format!("{fname}()"))?;
                if a.ty == Ty::Int {
                    return Ok(a);
                }
                let mode = match fname {
                    "round" => Rounding::Round,
                    "floor" => Rounding::Floor,
                    _ => Rounding::Ceil,
                };
                let d = self.reg(Ty::Int);
                self.ops.push(Op::ToInt(mode, d, a.reg));
                Ok(Built { ty: Ty::Int, unit: a.unit, reg: d })
            }
            "select" => {
                arg_count(fname, args, 3)?;
                let c = self.build(&args[0], ctx)?;
                boolean(&c, "select() condition")?;
                let a = self.build(&args[1], ctx)?;
                let b = self.build(&args[2], ctx)?;
                if a.ty == Ty::Bool || b.ty == Ty::Bool {
                    if a.ty != b.ty {
                        return Err("select(): the two branches must be the same kind of value".to_string());
                    }
                    let d = self.reg(Ty::Bool);
                    self.ops.push(Op::SelB(d, c.reg, a.reg, b.reg));
                    return Ok(Built { ty: Ty::Bool, unit: Some(Unit::one()), reg: d });
                }
                let unit = units::unify(&a.unit, &b.unit, "select()")?;
                if a.ty == Ty::Int && b.ty == Ty::Int {
                    let d = self.reg(Ty::Int);
                    self.ops.push(Op::SelI(d, c.reg, a.reg, b.reg));
                    return Ok(Built { ty: Ty::Int, unit, reg: d });
                }
                let (x, y) = (self.as_real(&a), self.as_real(&b));
                let d = self.reg(Ty::Real);
                self.ops.push(Op::SelF(d, c.reg, x, y));
                Ok(Built { ty: Ty::Real, unit, reg: d })
            }
            "safe_div" => {
                arg_count(fname, args, 3)?;
                let mut built = Vec::new();
                for arg in args {
                    let b = self.build(arg, ctx)?;
                    number(&b, "safe_div()")?;
                    built.push(b);
                }
                let quotient = Some(units::div(&built[0].unit, &built[1].unit));
                let unit = units::unify(&quotient, &built[2].unit, "safe_div()")?;
                let (x, y, fallback) = (self.as_real(&built[0]), self.as_real(&built[1]), self.as_real(&built[2]));
                let d = self.reg(Ty::Real);
                self.ops.push(Op::SafeDiv(d, x, y, fallback));
                Ok(Built { ty: Ty::Real, unit, reg: d })
            }
            "muldiv" => {
                arg_count(fname, args, 3)?;
                let a = self.build(&args[0], ctx)?;
                let b = self.build(&args[1], ctx)?;
                let c = self.build(&args[2], ctx)?;
                if !(a.ty == Ty::Int && b.ty == Ty::Int && c.ty == Ty::Int) {
                    return Err("muldiv() needs three whole numbers".to_string());
                }
                let unit = units::div(&Some(units::mul(&a.unit, &b.unit)), &c.unit);
                let d = self.reg(Ty::Int);
                self.ops.push(Op::MulDiv(d, a.reg, b.reg, c.reg));
                Ok(Built { ty: Ty::Int, unit: Some(unit), reg: d })
            }
            "per_step" | "times_step" => {
                arg_count(fname, args, 1)?;
                let a = self.build(&args[0], ctx)?;
                number(&a, &format!("{fname}()"))?;
                let step = Some(self.model.step_unit.clone());
                let unit = if fname == "per_step" { units::div(&a.unit, &step) } else { units::mul(&a.unit, &step) };
                Ok(Built { ty: a.ty, unit: Some(unit), reg: a.reg })
            }
            "marginal" => self.marginal(args, ctx),
            "prev" => {
                arg_count(fname, args, 1)?;
                let Node::Name(name) = &args[0] else {
                    return Err("prev() takes the name of a variable".to_string());
                };
                if let Some(&id) = self.model.sym_index.get(name.as_str()) {
                    let kind = self.model.symbols[id].kind;
                    if !matches!(kind, Kind::Var | Kind::Flow | Kind::State | Kind::Account | Kind::Lever) {
                        return Err(format!("prev({name}): a {} has no previous-step value", kind.name()));
                    }
                }
                self.name(name, ctx, true)
            }
            "rand" => {
                arg_count(fname, args, 1)?;
                let stream = match &args[0] {
                    Node::Name(name) => self.model.stream_id(name),
                    _ => None,
                };
                let Some(stream) = stream else {
                    return Err("rand() takes the name of a declared random stream".to_string());
                };
                let d = self.reg(Ty::Real);
                self.ops.push(Op::Rand(d, stream, ctx.is_some()));
                Ok(Built { ty: Ty::Real, unit: Some(Unit::one()), reg: d })
            }
            "wsum" => {
                let (entity, inner, sub) = self.aggregate(fname, args, ctx)?;
                number(&inner, "wsum()")?;
                let sub = sub.finish(&inner)?;
                let unit = units::mul(&inner.unit, &Some(Unit::base(&self.model.entities[entity].name)));
                let kind = if inner.ty == Ty::Int { AggKind::SumInt } else { AggKind::SumReal };
                let index = self.push_agg(kind, entity, sub)?;
                let d = self.reg(inner.ty);
                self.ops.push(if inner.ty == Ty::Int { Op::LoadAggI(d, index) } else { Op::LoadAggF(d, index) });
                Ok(Built { ty: inner.ty, unit: Some(unit), reg: d })
            }
            "wcount" => {
                let (entity, inner, sub) = self.aggregate(fname, args, ctx)?;
                boolean(&inner, "wcount()")?;
                let sub = sub.finish(&inner)?;
                let unit = Unit::base(&self.model.entities[entity].name);
                let index = self.push_agg(AggKind::Count, entity, sub)?;
                let d = self.reg(Ty::Int);
                self.ops.push(Op::LoadAggI(d, index));
                Ok(Built { ty: Ty::Int, unit: Some(unit), reg: d })
            }
            _ => Err(format!("unknown function {fname:?}")),
        }
    }

    /// Arguments that must be numbers with one common unit; whole only if all are whole.
    fn numeric_group(&mut self, fname: &str, args: &[Node], ctx: Option<usize>) -> Check<(Ty, Option<Unit>, Vec<R>)> {
        let mut built = Vec::new();
        for arg in args {
            let b = self.build(arg, ctx)?;
            number(&b, &format!("{fname}()"))?;
            built.push(b);
        }
        let mut unit = None;
        for b in &built {
            unit = units::unify(&unit, &b.unit, &format!("{fname}()"))?;
        }
        if built.iter().all(|b| b.ty == Ty::Int) {
            return Ok((Ty::Int, unit, built.iter().map(|b| b.reg).collect()));
        }
        let regs = built.iter().map(|b| self.as_real(b)).collect();
        Ok((Ty::Real, unit, regs))
    }

    fn marginal(&mut self, args: &[Node], ctx: Option<usize>) -> Check<Built> {
        arg_count("marginal", args, 2)?;
        let x = self.build(&args[0], ctx)?;
        if x.ty != Ty::Int {
            return Err("marginal(): the amount must be a whole number (money)".to_string());
        }
        let table = match &args[1] {
            Node::Name(name) => self.model.table_index.get(name.as_str()).copied(),
            _ => None,
        };
        let Some(table) = table else {
            return Err("marginal(): the second argument must be the name of a table".to_string());
        };
        let model = self.model;
        let spec = &model.tables[table];
        let table_unit = Some(spec.unit.clone());
        units::unify(&x.unit, &table_unit, &format!("marginal() with table {:?}", spec.name))?;
        let (mut lows, mut rates) = (Vec::new(), Vec::new());
        for (low_src, rate_src) in &spec.bands {
            // Thresholds and rates are national formulas, whatever the caller's context.
            let mut low_builder = Builder::new(model, self.deps, self.lagged);
            let low = low_builder.build(&parse(low_src)?, None)?;
            let low_prog = low_builder.finish(&low)?;
            let mut rate_builder = Builder::new(model, self.deps, self.lagged);
            let rate = rate_builder.build(&parse(rate_src)?, None)?;
            number(&rate, "band rate")?;
            if low.ty != Ty::Int {
                return Err(format!("table {:?}: 'from' must be a whole number (money)", spec.name));
            }
            units::unify(&low.unit, &table_unit, &format!("table {:?} threshold", spec.name))?;
            units::unify(&rate.unit, &Some(Unit::one()), &format!("table {:?} rate", spec.name))?;
            let rate_reg = rate_builder.as_real(&rate);
            let rate = Built { ty: Ty::Real, unit: None, reg: rate_reg };
            lows.push(low_prog);
            rates.push(rate_builder.finish(&rate)?);
        }
        let index = u16::try_from(self.tables.len()).map_err(|_| "formula is too large".to_string())?;
        self.tables.push(TableUse { table, lows, rates });
        let d = self.reg(Ty::Int);
        self.ops.push(Op::Marginal(d, x.reg, index));
        Ok(Built { ty: Ty::Int, unit: x.unit, reg: d })
    }

    fn aggregate(&mut self, fname: &str, args: &[Node], ctx: Option<usize>) -> Check<(usize, Built, Builder<'_>)> {
        arg_count(fname, args, 2)?;
        if let Some(entity) = ctx {
            let entity = &self.model.entities[entity].name;
            return Err(format!("{fname}() cannot be used inside a per-{entity} formula"));
        }
        let entity = match &args[0] {
            Node::Name(name) => self.model.entity_index.get(name.as_str()).copied(),
            _ => None,
        };
        let Some(entity) = entity else {
            return Err(format!("{fname}(): the first argument must be the name of an entity"));
        };
        let mut sub = Builder::new(self.model, self.deps, self.lagged);
        let inner = sub.build(&args[1], Some(entity))?;
        Ok((entity, inner, sub))
    }
}

impl Builder<'_> {
    fn push_agg(&mut self, kind: AggKind, entity: usize, prog: Program) -> Check<u16> {
        let index = u16::try_from(self.aggs.len()).map_err(|_| "formula is too large".to_string())?;
        self.aggs.push(Agg { kind, entity, prog });
        Ok(index)
    }
}

/// Compiles `src` for a target of the given type and unit.
///
/// `ctx` is `None` for a national formula or the index of the entity for a per-record
/// one. A whole-number result may feed a real target; a real result never feeds a
/// whole-number target without an explicit `round`, `floor` or `ceil`.
pub fn compile_formula(
    model: &Model,
    src: &str,
    ctx: Option<usize>,
    want_ty: Ty,
    want_unit: &Unit,
    label: &str,
) -> Result<Compiled> {
    let mut deps = BTreeSet::new();
    let mut lagged = BTreeSet::new();
    let outcome = (|| -> Check<(Program, Option<Unit>)> {
        let node = parse(src)?;
        let mut builder = Builder::new(model, &mut deps, &mut lagged);
        let mut built = builder.build(&node, ctx)?;
        if want_ty == Ty::Real && built.ty == Ty::Int {
            let reg = builder.as_real(&built);
            built = Built { ty: Ty::Real, unit: built.unit, reg };
        } else if built.ty != want_ty {
            let hint =
                if want_ty == Ty::Int && built.ty == Ty::Real { " (use round(), floor() or ceil())" } else { "" };
            return Err(format!("expected a {} value but the formula gives {}{hint}", want_ty.name(), built.ty.name()));
        }
        if want_ty != Ty::Bool {
            units::unify(&built.unit, &Some(want_unit.clone()), "result")?;
        }
        let prog = builder.finish(&built)?;
        Ok((prog, built.unit))
    })();
    match outcome {
        Ok((prog, unit)) => {
            Ok(Compiled { prog, deps: deps.into_iter().collect(), lagged: lagged.into_iter().collect(), unit })
        }
        Err(message) => Err(Error::Formula(format!("{label}: {message}\n    formula: {src}"))),
    }
}
