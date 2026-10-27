//! An opaque type's destructor is one symbol, so the type is monomorphic.
use axiom_ffi::axiom_opaque;

#[axiom_opaque]
pub struct Wrapper<T> {
    inner: T,
}

fn main() {}
