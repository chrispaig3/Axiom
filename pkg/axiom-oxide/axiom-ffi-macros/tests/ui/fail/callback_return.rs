//! A callback is borrowed for the call; it cannot be handed back.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn f(g: axiom_ffi::AxFn1) -> axiom_ffi::AxFn1 {
    g
}

fn main() {}
