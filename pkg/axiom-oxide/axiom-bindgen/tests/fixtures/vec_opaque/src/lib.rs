//! A `Vec` of an `#[axiom_opaque]` type: handles do not cross in a
//! `Vec`, and the generator says so rather than treating the type as
//! a record.
use axiom_ffi::{axiom_export, axiom_opaque};

#[axiom_opaque]
pub struct Thing {
    pub n: i64,
}

#[axiom_export]
pub fn things(n: i64) -> Vec<Thing> {
    (0..n).map(|n| Thing { n }).collect()
}
