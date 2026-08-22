//! Only `Vec<u8>`, `Vec<i64>` and `Vec<String>` cross directly.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn f(n: i64) -> Vec<i32> {
    vec![n as i32]
}

fn main() {}
