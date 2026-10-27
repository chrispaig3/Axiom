//! Any key but `symbol` and `utf8` is a compile error naming those two.
use axiom_ffi::axiom_export;

#[axiom_export(name = "whatever")]
pub fn attr_args(a: i64) -> i64 {
    a
}

fn main() {}
