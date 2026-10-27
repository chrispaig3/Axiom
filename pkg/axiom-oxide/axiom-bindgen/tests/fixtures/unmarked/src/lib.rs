//! An opaque return whose type was never marked `#[axiom_opaque]`.
//! The macro refuses this too (the trait bound); bindgen must refuse it
//! on its own, since it never compiles the crate. Never compiled.
use axiom_ffi::axiom_export;

pub struct Plain {
    n: i64,
}

#[axiom_export]
pub fn plain_new(n: i64) -> Plain {
    Plain { n }
}
