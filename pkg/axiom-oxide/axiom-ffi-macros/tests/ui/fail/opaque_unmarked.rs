//! An opaque return needs `#[axiom_opaque]` on the type.
use axiom_ffi::axiom_export;

pub struct Plain {
    n: i64,
}

#[axiom_export]
pub fn plain_new(n: i64) -> Plain {
    Plain { n }
}

fn main() {}
