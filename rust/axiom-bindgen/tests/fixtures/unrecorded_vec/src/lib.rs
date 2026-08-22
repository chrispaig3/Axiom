//! A `Vec` result whose element carries no `#[axiom_record]` (and is
//! not `#[axiom_opaque]` either): the generator names the missing
//! attribute, as it does for a by-value parameter.
use axiom_ffi::axiom_export;

pub struct Plain {
    pub n: i64,
}

#[axiom_export]
pub fn plains(n: i64) -> Vec<Plain> {
    (0..n).map(|n| Plain { n }).collect()
}
