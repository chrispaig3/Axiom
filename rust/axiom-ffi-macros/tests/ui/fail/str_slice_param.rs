//! A slice of strings does not cross: the message says why.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn f(words: &[&str]) -> i64 {
    words.len() as i64
}

fn main() {}
