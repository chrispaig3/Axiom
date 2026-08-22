//! The status word has three states: one level of Result/Option
//! nesting, no more - and never the same wrapper twice.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn f(n: i64) -> Result<Option<Option<i64>>, String> {
    Ok(Some(Some(n)))
}

#[axiom_export]
pub fn g(n: i64) -> Option<Option<i64>> {
    Some(Some(n))
}

fn main() {}
