//! A `u64` does not fit an i64 faithfully; the refusal lists the set.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn wide(n: u64) -> i64 {
    n as i64
}

fn main() {}
