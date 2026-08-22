//! `Vec<T>` crosses over the word scalars only; a `u64` is not one.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn f(n: i64) -> Vec<u64> {
    vec![n as u64]
}

fn main() {}
