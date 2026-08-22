//! `char` is refused with the accepted set.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn first(c: char) -> i64 {
    c as i64
}

fn main() {}
