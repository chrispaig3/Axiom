//! Only the word-sized scalars are written in place: a `&mut [i32]`
//! would be a converted copy that cannot be written back as the words.
use axiom_ffi::axiom_export;

#[axiom_export]
pub fn bump(xs: &mut [i32]) -> i64 {
    xs.len() as i64
}

fn main() {}
