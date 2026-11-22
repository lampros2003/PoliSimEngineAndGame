//! Python-style text forms, part of the file formats.
//!
//! The runner's CSV, `polisim serve`'s JSON, the hex of hashes and parts of the model hash
//! were first written to match the retired Python reference byte for byte, and the recorded
//! files and the Python tools still read them so. Reals are written the way Python's `repr`
//! writes them: the shortest digits that read back to the same value, in positional
//! notation unless the exponent is below -4 or at least 16.

/// Python's `repr(float)`.
pub fn float_repr(x: f64) -> String {
    if x.is_nan() {
        return "nan".to_string();
    }
    if x.is_infinite() {
        return if x > 0.0 { "inf".to_string() } else { "-inf".to_string() };
    }
    // Rust's `{:e}` gives the shortest digits that read back to `x`. When two strings of
    // that length are equally close, Python picks the one whose last digit is even, so
    // the digits are regenerated at that length with exact, ties-to-even rounding.
    let shortest = format!("{x:e}");
    let length = shortest.split('e').next().unwrap_or("").chars().filter(char::is_ascii_digit).count();
    let scientific = format!("{x:.prec$e}", prec = length.saturating_sub(1));
    let (mantissa, exponent) = scientific.split_once('e').expect("exponent form");
    let exponent: i32 = exponent.parse().expect("exponent digits");
    let negative = mantissa.starts_with('-');
    let digits: String = mantissa.chars().filter(char::is_ascii_digit).collect();
    let sign = if negative { "-" } else { "" };

    if !(-4..16).contains(&exponent) {
        let mut out = format!("{sign}{}", &digits[..1]);
        if digits.len() > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        let exp_sign = if exponent < 0 { '-' } else { '+' };
        return format!("{out}e{exp_sign}{:02}", exponent.abs());
    }
    if exponent < 0 {
        return format!("{sign}0.{}{digits}", "0".repeat((-exponent - 1) as usize));
    }
    let whole = exponent as usize + 1;
    if digits.len() <= whole {
        return format!("{sign}{digits}{}.0", "0".repeat(whole - digits.len()));
    }
    format!("{sign}{}.{}", &digits[..whole], &digits[whole..])
}

/// Python's `str(bool)`.
pub fn bool_str(value: bool) -> &'static str {
    if value { "True" } else { "False" }
}

/// Lower-case hexadecimal.
pub fn hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::float_repr;

    #[test]
    fn matches_python_repr() {
        // Each pair was produced by Python's repr().
        let cases: [(f64, &str); 24] = [
            (0.0, "0.0"),
            (-0.0, "-0.0"),
            (1.0, "1.0"),
            (-1.5, "-1.5"),
            (0.1, "0.1"),
            (0.06058089758251296, "0.06058089758251296"),
            (100.0, "100.0"),
            (1234567.0, "1234567.0"),
            (1e15, "1000000000000000.0"),
            (1e16, "1e+16"),
            (1.5e16, "1.5e+16"),
            (123456789012345680.0, "1.2345678901234568e+17"),
            (0.0001, "0.0001"),
            (0.00012345, "0.00012345"),
            (0.00001, "1e-05"),
            (1.5e-7, "1.5e-07"),
            (5e-324, "5e-324"),
            (1e300, "1e+300"),
            (1.7976931348623157e308, "1.7976931348623157e+308"),
            (2.5, "2.5"),
            (0.3, "0.3"),
            (9007199254740993.0, "9007199254740992.0"),
            // Exactly halfway between ...812 and ...813: Python keeps the even digit.
            (24364314563235.0 + 0.8125, "24364314563235.812"),
            (28161555071692.0 + 0.0625, "28161555071692.062"),
        ];
        for (value, text) in cases {
            assert_eq!(float_repr(value), text);
        }
        assert_eq!(float_repr(f64::NAN), "nan");
        assert_eq!(float_repr(f64::NEG_INFINITY), "-inf");
    }
}
