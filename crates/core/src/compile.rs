//! Type and unit checking, and translation of a syntax tree into bytecode.
//!
//! This is a port of the oracle's `_Builder` (oracle/polisim_oracle/expr.py). It must
//! accept and reject exactly the same formulas; conformance/cases.tsv holds it to that.

use std::collections::BTreeSet;

use crate::error::{Error, Result};
use crate::model::{Kind, Model};
use crate::program::{
    Agg, AggKind, Cmp, Compiled, Fixed, IndexUse, Op, Program, R, Rounding, Src, Sub, SubKind, TableUse, Ty,
};
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
    /// Format 1: the dimensions in scope, which are the program's domain in this order.
    scope: Vec<usize>,
    gathers: Vec<Vec<u32>>,
    coords: Vec<Vec<i64>>,
    indexes: Vec<IndexUse>,
    subs: Vec<Sub>,
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
        Builder {
            model,
            deps,
            lagged,
            ops: Vec::new(),
            n_i: 0,
            n_f: 0,
            n_b: 0,
            aggs: Vec::new(),
            tables: Vec::new(),
            scope: Vec::new(),
            gathers: Vec::new(),
            coords: Vec::new(),
            indexes: Vec::new(),
            subs: Vec::new(),
        }
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
            gathers: self.gathers,
            coords: self.coords,
            indexes: self.indexes,
            subs: self.subs,
        })
    }

    // ---------------------------------------------------------------- format 1

    fn dim_name(&self, d: usize) -> &str {
        &self.model.dims[d].name
    }

    /// The dimension a node names, for `sum`, `coord` and `cohort_shift`.
    fn dim_arg(&self, node: &Node, fname: &str) -> Check<usize> {
        match node {
            Node::Name(name) => match self.model.dim_index.get(name.as_str()) {
                Some(d) => Ok(*d),
                None => Err(format!("{fname}(): {name} is not a declared dimension")),
            },
            _ => Err(format!("{fname}(): that is not a declared dimension")),
        }
    }

    /// Strides of row-major storage over `dims`: the last varies fastest.
    fn strides(&self, dims: &[usize]) -> Vec<usize> {
        let mut out = vec![1usize; dims.len()];
        for k in (0..dims.len().saturating_sub(1)).rev() {
            out[k] = out[k + 1] * self.model.dims[dims[k + 1]].size();
        }
        out
    }

    /// For every cell of the domain, the flat index into a value stored over `target`
    /// (whose dimensions not in `skip` must all be in scope), counting only those dimensions.
    fn map_over_domain(&self, target: &[usize], skip: &[usize]) -> Vec<u32> {
        let domain = &self.scope;
        let dstrides = self.strides(domain);
        let tstrides = self.strides(target);
        let cells = self.model.cell_count(domain);
        let parts: Vec<(usize, usize, usize)> = target
            .iter()
            .enumerate()
            .filter(|(_, d)| !skip.contains(d))
            .map(|(k, d)| {
                let at = domain.iter().position(|x| x == d).expect("checked to be in scope");
                (dstrides[at], self.model.dims[*d].size(), tstrides[k])
            })
            .collect();
        (0..cells).map(|c| parts.iter().map(|(ds, size, ts)| ((c / ds) % size) * ts).sum::<usize>() as u32).collect()
    }

    fn push_table<T>(list: &mut Vec<T>, item: T) -> Check<u16> {
        let index = u16::try_from(list.len()).map_err(|_| "formula is too large".to_string())?;
        list.push(item);
        Ok(index)
    }

    fn index(&mut self, name: &str, coords: &[(String, Node)], ctx: Option<usize>) -> Check<Built> {
        let Some(&id) = self.model.sym_index.get(name) else {
            return Err(format!("unknown name {name:?}"));
        };
        let sym = &self.model.symbols[id];
        if sym.dims.is_empty() {
            return Err(format!("{name:?} has no dimensions to index"));
        }
        let (dims, ty, unit) = (sym.dims.clone(), sym.ty, sym.unit.clone());
        self.deps.insert(id);
        let strides = self.strides(&dims);
        let mut fixed: Vec<Fixed> = Vec::new();
        let mut fixed_dims: Vec<usize> = Vec::new();
        for (dim, node) in coords {
            let Some(k) = dims.iter().position(|d| self.model.dims[*d].name == *dim) else {
                return Err(format!("{name}[{dim}: ...]: {name} has no dimension {dim:?}"));
            };
            let d = dims[k];
            if fixed_dims.contains(&d) {
                return Err(format!("{name}[...]: {dim} is fixed twice"));
            }
            let info = &self.model.dims[d];
            let (size, first) = (info.size() as u32, info.first);
            let member = match (first, node) {
                (None, Node::Name(n)) => info.members.iter().position(|m| m == n),
                _ => None,
            };
            let reg = match member {
                Some(pos) => {
                    let r = self.reg(Ty::Int);
                    self.ops.push(Op::ConstI(r, pos as i64));
                    r
                }
                None => {
                    let b = self.build(node, ctx)?;
                    if b.ty != Ty::Int {
                        return Err(format!("{name}[{dim}: ...]: a coordinate must be a whole number"));
                    }
                    if b.unit.is_some() {
                        units::unify(&b.unit, &Some(Unit::one()), &format!("{name}[{dim}: ...] coordinate"))?;
                    }
                    b.reg
                }
            };
            fixed_dims.push(d);
            fixed.push(Fixed {
                dim: dim.clone(),
                reg,
                first: if member.is_some() { 0 } else { first.unwrap_or(0) },
                size,
                stride: strides[k] as u32,
            });
        }
        if let Some(d) = dims.iter().find(|d| !fixed_dims.contains(d) && !self.scope.contains(d)) {
            return Err(format!("{name}[...]: {} is neither fixed nor in scope here", self.dim_name(*d)));
        }
        let base = if dims.iter().all(|d| fixed_dims.contains(d)) {
            Vec::new()
        } else {
            self.map_over_domain(&dims, &fixed_dims)
        };
        let src = Src { sym: id as u32, lagged: false };
        let use_index = Self::push_table(&mut self.indexes, IndexUse { name: name.to_string(), src, base, fixed })?;
        let d = self.reg(ty);
        self.ops.push(match ty {
            Ty::Int => Op::IndexI(d, use_index),
            Ty::Real => Op::IndexF(d, use_index),
            Ty::Bool => Op::IndexB(d, use_index),
        });
        Ok(Built { ty, unit: Some(unit), reg: d })
    }

    /// `sum` and `cohort_shift`: `x` compiled over `domain` as a sub-program.
    fn sub_program(
        &mut self,
        x: &Node,
        domain: Vec<usize>,
        ctx: Option<usize>,
        what: &str,
    ) -> Check<(Ty, Option<Unit>, Program)> {
        let mut sub = Builder::new(self.model, self.deps, self.lagged);
        sub.scope = domain;
        let inner = sub.build(x, ctx)?;
        number(&inner, what)?;
        let (ty, unit) = (inner.ty, inner.unit.clone());
        Ok((ty, unit, sub.finish(&inner)?))
    }

    fn load_sub(&mut self, ty: Ty, unit: Option<Unit>, sub: Sub) -> Check<Built> {
        let index = Self::push_table(&mut self.subs, sub)?;
        let d = self.reg(ty);
        self.ops.push(if ty == Ty::Int { Op::LoadSubI(d, index) } else { Op::LoadSubF(d, index) });
        Ok(Built { ty, unit, reg: d })
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
            Node::Index(name, coords) => self.index(name, coords, ctx),
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
        if !sym.dims.is_empty() {
            let (dims, ty, unit) = (sym.dims.clone(), sym.ty, sym.unit.clone());
            if let Some(missing) = dims.iter().find(|d| !self.scope.contains(d)) {
                let missing = self.dim_name(*missing).to_string();
                return Err(format!(
                    "{name:?} holds one value per cell of its dimensions; {missing} is not in scope here: sum it with \
                     sum({name}, {missing}) or fix it with {name}[{missing}: ...]"
                ));
            }
            let map = self.map_over_domain(&dims, &[]);
            let g = Self::push_table(&mut self.gathers, map)?;
            let d = self.reg(ty);
            self.ops.push(match ty {
                Ty::Int => Op::LoadGI(d, src, g),
                Ty::Real => Op::LoadGF(d, src, g),
                Ty::Bool => Op::LoadGB(d, src, g),
            });
            return Ok(Built { ty, unit: Some(unit), reg: d });
        }
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
                if !self.scope.is_empty() {
                    return Err("rand() is not available in a formula with dimensions".to_string());
                }
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
            "sum" => {
                if args.len() < 2 {
                    return Err("sum() takes a value and at least one dimension".to_string());
                }
                if let Some(entity) = ctx {
                    let entity = &self.model.entities[entity].name;
                    return Err(format!("sum() is not available in a per-{entity} formula"));
                }
                let mut summed: Vec<usize> = Vec::new();
                for node in &args[1..] {
                    let d = self.dim_arg(node, "sum")?;
                    if self.scope.contains(&d) || summed.contains(&d) {
                        return Err(format!("sum(): {} is already in scope", self.dim_name(d)));
                    }
                    summed.push(d);
                }
                let group = self.model.cell_count(&summed);
                let mut domain = self.scope.clone();
                domain.extend(&summed);
                let cells = self.model.cell_count(&domain);
                let (ty, unit, prog) = self.sub_program(&args[0], domain, ctx, "sum()")?;
                self.load_sub(ty, unit, Sub { kind: SubKind::Sum { group }, cells, prog })
            }
            "coord" => {
                arg_count(fname, args, 1)?;
                let dim = self.dim_arg(&args[0], "coord")?;
                let Some(at) = self.scope.iter().position(|d| *d == dim) else {
                    return Err(format!("coord({0}): {0} is not in scope here", self.dim_name(dim)));
                };
                let info = &self.model.dims[dim];
                let (size, first) = (info.size(), info.first.unwrap_or(0));
                let stride = self.strides(&self.scope)[at];
                let cells = self.model.cell_count(&self.scope);
                let table: Vec<i64> = (0..cells).map(|c| first + ((c / stride) % size) as i64).collect();
                let index = Self::push_table(&mut self.coords, table)?;
                let d = self.reg(Ty::Int);
                self.ops.push(Op::Coord(d, index));
                Ok(Built { ty: Ty::Int, unit: Some(Unit::one()), reg: d })
            }
            "cohort_shift" => {
                arg_count(fname, args, 2)?;
                let dim = self.dim_arg(&args[1], "cohort_shift")?;
                let Some(at) = self.scope.iter().position(|d| *d == dim) else {
                    return Err(format!("cohort_shift(): {} is not in scope here", self.dim_name(dim)));
                };
                let stride = self.strides(&self.scope)[at];
                let size = self.model.dims[dim].size();
                let cells = self.model.cell_count(&self.scope);
                let (ty, unit, prog) = self.sub_program(&args[0], self.scope.clone(), ctx, "cohort_shift()")?;
                self.load_sub(ty, unit, Sub { kind: SubKind::Shift { stride, size }, cells, prog })
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
    dims: &[usize],
    want_ty: Ty,
    want_unit: &Unit,
    label: &str,
) -> Result<Compiled> {
    let mut deps = BTreeSet::new();
    let mut lagged = BTreeSet::new();
    let outcome = (|| -> Check<(Program, Option<Unit>)> {
        let node = parse(src)?;
        let mut builder = Builder::new(model, &mut deps, &mut lagged);
        builder.scope = dims.to_vec();
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
