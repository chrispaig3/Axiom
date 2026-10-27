//! An opaque value cannot be taken by value: Axiom holds a handle.
use axiom_ffi::{axiom_export, axiom_opaque};

#[axiom_opaque]
pub struct Thing {
    n: i64,
}

#[axiom_export]
pub fn consume(t: Thing) -> i64 {
    t.n
}

fn main() {}
