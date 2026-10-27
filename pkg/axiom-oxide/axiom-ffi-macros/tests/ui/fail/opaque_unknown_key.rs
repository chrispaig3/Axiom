//! `#[axiom_opaque]` takes only `symbol`.
use axiom_ffi::axiom_opaque;

#[axiom_opaque(drop = "custom")]
pub struct Thing {
    n: i64,
}

fn main() {}
