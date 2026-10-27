//! A callback is one word and `Copy`: taken by value, never borrowed.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn f(g: &axiom_ffi::AxFn2) -> i64 {
    g.call(1, 2)
}

fn main() {}
