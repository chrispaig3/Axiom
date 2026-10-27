//! Two Rust spellings that fold to one Axiom name. Never compiled.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn foo_bar(a: i64) -> i64 {
    a
}

#[allow(non_snake_case)]
#[axiom_export]
pub fn fooBar(a: i64) -> i64 {
    a + 1
}
