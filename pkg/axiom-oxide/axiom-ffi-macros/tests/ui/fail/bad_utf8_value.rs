//! `utf8` takes `"lossy"` or `"strict"`.
use axiom_ffi::axiom_export;

#[axiom_export(utf8 = "ignore")]
pub fn f(s: &str) -> i64 {
    s.len() as i64
}

fn main() {}
