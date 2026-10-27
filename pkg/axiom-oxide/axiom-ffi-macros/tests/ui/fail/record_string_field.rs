//! A record is its words: a `String` field does not cross.
use axiom_ffi::axiom_record;

#[axiom_record]
pub struct Named {
    pub id: i64,
    pub name: String,
}

fn main() {}
