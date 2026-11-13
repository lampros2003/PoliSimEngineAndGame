//! Unit algebra. A unit is a list of (base name, integer exponent), sorted by name.
//!
//! `"GBP/month"` is `[("GBP", 1), ("month", -1)]` and `"1"` is the empty list. Where a
//! unit is optional, `None` means "any unit" and is used only for the literal zero.

use std::collections::BTreeMap;

#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct Unit(Vec<(String, i32)>);

impl Unit {
    /// The dimensionless unit.
    pub fn one() -> Unit {
        Unit(Vec::new())
    }

    /// A single base unit to the first power.
    pub fn base(name: &str) -> Unit {
        Unit(vec![(name.to_string(), 1)])
    }

    /// Parses `a*b/c^2`. Operators apply left to right; `1` is dimensionless.
    pub fn parse(text: &str) -> Result<Unit, String> {
        let mut exponents: BTreeMap<String, i32> = BTreeMap::new();
        let mut sign = 1;
        let mut token = String::new();
        let mut flush = |token: &str, sign: i32| -> Result<(), String> {
            let tok = token.trim();
            if tok.is_empty() {
                return Err(format!("malformed unit {text:?}"));
            }
            if tok == "1" {
                return Ok(());
            }
            let (name, power) = match tok.split_once('^') {
                Some((n, p)) => (n.trim(), Some(p)),
                None => (tok, None),
            };
            let valid = !name.is_empty()
                && name.chars().all(|c| c == '_' || c.is_alphanumeric())
                && !name.chars().next().is_some_and(|c| c.is_numeric());
            if !valid {
                return Err(format!("bad unit name {name:?} in {text:?}"));
            }
            let power = match power {
                None | Some("") => 1,
                Some(p) => p.trim().parse::<i32>().map_err(|_| format!("bad exponent in {text:?}"))?,
            };
            *exponents.entry(name.to_string()).or_insert(0) += sign * power;
            Ok(())
        };
        for ch in text.chars() {
            if ch == '*' || ch == '/' {
                flush(&token, sign)?;
                token.clear();
                sign = if ch == '*' { 1 } else { -1 };
            } else {
                token.push(ch);
            }
        }
        flush(&token, sign)?;
        Ok(Unit(exponents.into_iter().filter(|(_, p)| *p != 0).collect()))
    }

    fn combine(a: &Option<Unit>, b: &Option<Unit>, sign: i32) -> Unit {
        let mut exponents: BTreeMap<&str, i32> = BTreeMap::new();
        if let Some(a) = a {
            for (name, power) in &a.0 {
                *exponents.entry(name).or_insert(0) += power;
            }
        }
        if let Some(b) = b {
            for (name, power) in &b.0 {
                *exponents.entry(name).or_insert(0) += sign * power;
            }
        }
        Unit(exponents.into_iter().filter(|(_, p)| *p != 0).map(|(n, p)| (n.to_string(), p)).collect())
    }
}

/// The unit of a product. "Any" counts as dimensionless.
pub fn mul(a: &Option<Unit>, b: &Option<Unit>) -> Unit {
    Unit::combine(a, b, 1)
}

/// The unit of a quotient. "Any" counts as dimensionless.
pub fn div(a: &Option<Unit>, b: &Option<Unit>) -> Unit {
    Unit::combine(a, b, -1)
}

/// The common unit of two operands that must agree. "Any" adopts the other side.
pub fn unify(a: &Option<Unit>, b: &Option<Unit>, what: &str) -> Result<Option<Unit>, String> {
    match (a, b) {
        (None, other) | (other, None) => Ok(other.clone()),
        (Some(x), Some(y)) if x == y => Ok(Some(x.clone())),
        _ => Err(format!("{what}: unit {} does not match {}", fmt(a), fmt(b))),
    }
}

pub fn fmt(unit: &Option<Unit>) -> String {
    let Some(unit) = unit else { return "any".to_string() };
    if unit.0.is_empty() {
        return "1".to_string();
    }
    let part = |name: &str, power: i32| if power == 1 { name.to_string() } else { format!("{name}^{power}") };
    let top: Vec<String> = unit.0.iter().filter(|(_, p)| *p > 0).map(|(n, p)| part(n, *p)).collect();
    let mut out = if top.is_empty() { "1".to_string() } else { top.join("*") };
    for (name, power) in unit.0.iter().filter(|(_, p)| *p < 0) {
        out.push('/');
        out.push_str(&part(name, -power));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_and_format() {
        let per_household = Unit::parse("GBP/month/household").unwrap();
        assert_eq!(fmt(&Some(per_household.clone())), "GBP/household/month");
        assert_eq!(Unit::parse("1").unwrap(), Unit::one());
        assert_eq!(Unit::parse("a/a").unwrap(), Unit::one());
        assert_eq!(Unit::parse("a*b/c^2").unwrap(), Unit::parse("b * a / c / c").unwrap());
        assert!(Unit::parse("").is_err());
        assert!(Unit::parse("GBP/").is_err());
        assert!(Unit::parse("2x").is_err());
        let total = mul(&Some(per_household), &Some(Unit::base("household")));
        assert_eq!(total, Unit::parse("GBP/month").unwrap());
        assert!(unify(&Some(total.clone()), &Some(Unit::one()), "t").is_err());
        assert_eq!(unify(&None, &Some(total.clone()), "t").unwrap(), Some(total));
    }
}
