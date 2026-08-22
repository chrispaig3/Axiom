//! Only `Vec<u8>` crosses directly.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn f(n: i64) -> Vec<i64> {
    vec![n]
}

fn main() {}
