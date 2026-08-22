//! A nested `Vec` is one level of word scalars: no `Vec<Vec<String>>`,
//! no `Vec<Vec<Record>>`, no `&[&[&str]]`.
use axiom_ffi::{axiom_export, axiom_record};

#[axiom_record]
pub struct Point {
    pub x: i64,
    pub y: f64,
}

#[axiom_export]
pub fn table(n: i64) -> Vec<Vec<String>> {
    vec![vec![n.to_string()]]
}

#[axiom_export]
pub fn polygons(n: i64) -> Vec<Vec<Point>> {
    vec![vec![Point { x: n, y: 0.0 }]]
}

#[axiom_export]
pub fn names(rows: &[&[&str]]) -> i64 {
    rows.len() as i64
}

fn main() {}
