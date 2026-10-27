//! No `self`: export a free function over `&Self`.
use axiom_ffi::{axiom_export, axiom_opaque};

#[axiom_opaque]
pub struct Thing {
    n: i64,
}

impl Thing {
    #[axiom_export]
    pub fn get(&self) -> i64 {
        self.n
    }
}

fn main() {}
