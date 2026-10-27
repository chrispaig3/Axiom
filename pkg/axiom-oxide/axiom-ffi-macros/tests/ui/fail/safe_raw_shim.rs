use axiom_ffi::axiom_export;

#[axiom_export]
pub fn first(xs: &[i64]) -> i64 {
    xs[0]
}

fn main() {
    axffi_first(1);
}
