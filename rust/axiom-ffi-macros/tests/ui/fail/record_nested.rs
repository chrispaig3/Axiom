//! A record inside a record does not cross: flatten the words.
use axiom_ffi::axiom_record;

#[axiom_record]
pub struct Point {
    pub x: i64,
    pub y: f64,
}

#[axiom_record]
pub struct Line {
    pub from: Point,
    pub to: Point,
}

fn main() {}
