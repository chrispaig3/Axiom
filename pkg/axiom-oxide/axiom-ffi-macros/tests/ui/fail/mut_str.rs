//! Axiom strings are immutable through the FFI.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn upper(s: &mut str) -> i64 {
    s.make_ascii_uppercase();
    0
}

fn main() {}
