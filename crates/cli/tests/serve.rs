//! `polisim serve` as a process: the first line, one reply per request, and a model that
//! cannot load (docs/spec/09-serve.md).

use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn serve(path: PathBuf, input: &str) -> (Option<i32>, Vec<String>) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_polisim"))
        .arg("serve")
        .arg(path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(input.as_bytes()).unwrap();
    let out = child.wait_with_output().unwrap();
    (out.status.code(), String::from_utf8(out.stdout).unwrap().lines().map(str::to_string).collect())
}

#[test]
fn one_json_line_per_request() {
    let (code, lines) = serve(root().join("models/toy"), "open {seed = 20261113}\n@1 step 240\nnope\nquit\nstep\n");
    assert_eq!(code, Some(0));
    assert_eq!(lines.len(), 4, "the hello, three replies, nothing after quit");
    assert!(lines[0].starts_with(r#"{"ok":true,"model":"toy""#));
    // The run is the toy baseline: its last row carries the recorded hash.
    let recorded = std::fs::read_to_string(root().join("models/toy/golden/baseline.hashes.csv")).unwrap();
    let last = recorded.lines().last().unwrap().split(',').nth(1).unwrap().to_string();
    assert!(lines[2].contains(&format!(r#""step":239,"hash":"{last}""#)));
    assert!(lines[3].contains(r#""kind":"request""#));
}

#[test]
fn a_model_that_cannot_load_says_why_and_stops() {
    let (code, lines) = serve(root().join("models/no_such_model"), "step\n");
    assert_eq!(code, Some(1));
    assert_eq!(lines.len(), 1);
    assert!(lines[0].starts_with(r#"{"error":"#) && lines[0].ends_with(r#""kind":"model"}"#), "{}", lines[0]);
}
