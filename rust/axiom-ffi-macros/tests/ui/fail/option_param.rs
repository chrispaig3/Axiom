//! `Option` may only be returned.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn f(n: Option<i64>) -> i64 {
    n.unwrap_or(0)
}

fn main() {}
