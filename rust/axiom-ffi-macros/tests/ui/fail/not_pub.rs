//! The shim is a public symbol; the function must be `pub`.
use axiom_ffi::axiom_export;

#[axiom_export]
fn hidden(n: i64) -> i64 {
    n
}

fn main() {}
