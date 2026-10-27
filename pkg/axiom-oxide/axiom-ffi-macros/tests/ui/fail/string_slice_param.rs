//! An owned `String` cannot be borrowed out of an Axiom Vec: take `&[&str]`.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn f(words: &[String]) -> i64 {
    words.len() as i64
}

#[axiom_export]
pub fn g(words: Vec<String>) -> i64 {
    words.len() as i64
}

fn main() {}
