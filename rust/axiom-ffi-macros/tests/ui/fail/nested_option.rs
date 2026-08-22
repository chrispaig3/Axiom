//! The status word has one slot: no `Result<Option<_>, _>`.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn f(n: i64) -> Result<Option<i64>, String> {
    Ok(Some(n))
}

fn main() {}
