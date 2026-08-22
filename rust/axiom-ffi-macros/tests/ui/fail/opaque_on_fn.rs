//! `#[axiom_opaque]` goes on a struct or enum.
use axiom_ffi::axiom_opaque;

#[axiom_opaque]
pub fn not_a_type() {}

fn main() {}
