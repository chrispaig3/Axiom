//! A by-value parameter whose type carries no `#[axiom_record]`: the
//! generator names the missing attribute.
use axiom_ffi::axiom_export;

pub struct Plain {
    pub n: i64,
}

#[axiom_export]
pub fn plain_n(p: Plain) -> i64 {
    p.n
}
