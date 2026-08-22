//! A `Vec` of records does not cross: an Axiom `Vec` holds words.
use axiom_ffi::{axiom_export, axiom_record};

#[axiom_record]
pub struct Point {
    pub x: i64,
    pub y: f64,
}

#[axiom_export]
pub fn points(n: i64) -> Vec<Point> {
    (0..n).map(|i| Point { x: i, y: 0.0 }).collect()
}

#[axiom_export]
pub fn total(ps: &[Point]) -> i64 {
    ps.iter().map(|p| p.x).sum()
}

fn main() {}
