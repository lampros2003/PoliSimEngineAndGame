//! The small JSON `polisim serve` writes (docs/spec/09-serve.md). Written by hand: the
//! engine takes no dependency for it.
//!
//! Reals are written in the shortest form that reads back to the same value (Python's
//! `repr`), always with a decimal point or an exponent so a reader can tell them from whole
//! numbers; infinities and not-a-number as `Infinity`, `-Infinity` and `NaN`, which
//! Python's `json` module reads (they are not standard JSON).

use polisim_core::{Col, RawValue, Val, pyfmt};

#[derive(Clone, Debug, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Int(i128),
    Real(f64),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

impl Json {
    pub fn obj(fields: Vec<(&str, Json)>) -> Json {
        Json::Obj(fields.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
    }

    pub fn str(text: &str) -> Json {
        Json::Str(text.to_string())
    }

    pub fn text(&self) -> String {
        let mut out = String::new();
        self.write(&mut out);
        out
    }

    pub fn write(&self, out: &mut String) {
        match self {
            Json::Null => out.push_str("null"),
            Json::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            Json::Int(v) => out.push_str(&v.to_string()),
            Json::Real(v) if v.is_nan() => out.push_str("NaN"),
            Json::Real(v) if v.is_infinite() => out.push_str(if *v > 0.0 { "Infinity" } else { "-Infinity" }),
            Json::Real(v) => out.push_str(&pyfmt::float_repr(*v)),
            Json::Str(s) => string(out, s),
            Json::Arr(items) => {
                out.push('[');
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    item.write(out);
                }
                out.push(']');
            }
            Json::Obj(fields) => {
                out.push('{');
                for (i, (key, value)) in fields.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    string(out, key);
                    out.push(':');
                    value.write(out);
                }
                out.push('}');
            }
        }
    }
}

fn string(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}

impl From<Val> for Json {
    fn from(value: Val) -> Json {
        match value {
            Val::I(v) => Json::Int(v as i128),
            Val::F(v) => Json::Real(v),
            Val::B(v) => Json::Bool(v),
        }
    }
}

impl From<&Col> for Json {
    fn from(column: &Col) -> Json {
        match column {
            Col::I(v) => Json::Arr(v.iter().map(|x| Json::Int(*x as i128)).collect()),
            Col::F(v) => Json::Arr(v.iter().map(|x| Json::Real(*x)).collect()),
            Col::B(v) => Json::Arr(v.iter().map(|x| Json::Bool(*x)).collect()),
        }
    }
}

impl From<&RawValue> for Json {
    fn from(value: &RawValue) -> Json {
        match value {
            RawValue::String(s) => Json::str(s),
            RawValue::Integer(v) => Json::Int(*v as i128),
            RawValue::Float(v) => Json::Real(*v),
            RawValue::Boolean(v) => Json::Bool(*v),
            RawValue::Datetime(d) => Json::Str(d.to_string()),
            RawValue::Array(items) => Json::Arr(items.iter().map(Json::from).collect()),
            RawValue::Table(table) => Json::Obj(table.iter().map(|(k, v)| (k.clone(), Json::from(v))).collect()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Json;

    #[test]
    fn numbers_strings_arrays_and_objects() {
        let value = Json::obj(vec![
            ("n", Json::Null),
            ("b", Json::Bool(true)),
            ("i", Json::Int(-9_223_372_036_854_775_808)),
            ("u", Json::Int(u64::MAX as i128)),
            (
                "r",
                Json::Arr(vec![
                    Json::Real(1.0),
                    Json::Real(0.1),
                    Json::Real(1e16),
                    Json::Real(-0.0),
                    Json::Real(5e-324),
                ]),
            ),
            ("x", Json::Arr(vec![Json::Real(f64::INFINITY), Json::Real(f64::NEG_INFINITY), Json::Real(f64::NAN)])),
            ("s", Json::str("a \"q\" \\ \n\t\r \u{1} é")),
            ("e", Json::Arr(vec![])),
        ]);
        assert_eq!(
            value.text(),
            r#"{"n":null,"b":true,"i":-9223372036854775808,"u":18446744073709551615,"r":[1.0,0.1,1e+16,-0.0,5e-324],"x":[Infinity,-Infinity,NaN],"s":"a \"q\" \\ \n\t\r \u0001 é","e":[]}"#
        );
    }

    #[test]
    fn reals_read_back_exactly() {
        for v in [0.1 + 0.2, 1.0 / 3.0, 2301745961.03, 1e-7, 123456789012345680.0, f64::MAX, f64::MIN_POSITIVE] {
            let text = Json::Real(v).text();
            assert_eq!(text.parse::<f64>().unwrap().to_bits(), v.to_bits(), "{text}");
            assert!(text.contains('.') || text.contains('e'), "{text}");
        }
    }
}
