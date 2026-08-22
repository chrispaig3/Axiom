//! The same for a `u64` return.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn wide() -> u64 {
    7
}

fn main() {}
