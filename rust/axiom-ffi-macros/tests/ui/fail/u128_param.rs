//! A 128-bit integer is two words; the refusal says to split it.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn wide(n: u128) -> i64 {
    n as i64
}

#[axiom_export]
pub fn wider() -> i128 {
    7
}

fn main() {}
