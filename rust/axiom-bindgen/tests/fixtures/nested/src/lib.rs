//! A source tree the snapshot test feeds to the generator. It is never
//! compiled; it exists to pin the generated module's shape for every
//! wrapper kind, the `mod` recursion, the `pub`-only rule, the
//! attribute keys, the raw-shim path and a parameter named `cell`.

use axiom_ffi::{axiom_export, axiom_opaque};

#[axiom_opaque]
pub struct Thing {
    n: i64,
}

#[axiom_opaque(symbol = "widget_v2")]
pub enum Widget {
    A,
    B,
}

#[axiom_export]
pub fn thing_new(n: i64) -> Thing {
    Thing { n }
}

#[axiom_export]
pub fn thing_get(t: &Thing) -> i64 {
    t.n
}

#[axiom_export]
pub fn thing_pair(a: &Thing, b: &mut Thing, scale: f64) -> f64 {
    (a.n + b.n) as f64 * scale
}

#[axiom_export]
pub fn thing_try(n: i64) -> Result<Thing, String> {
    Ok(Thing { n })
}

#[axiom_export]
pub fn thing_maybe(t: &Thing) -> Option<Thing> {
    Some(Thing { n: t.n })
}

#[axiom_export]
pub fn widget_new() -> Widget {
    Widget::A
}

/// A parameter named `cell` beside a wrapper that allocates a cell.
#[axiom_export]
pub fn echo(cell: &str) -> String {
    cell.to_string()
}

#[axiom_export(symbol = "custom_symbol", utf8 = "lossy")]
pub fn renamed(text: &str, n: u8) -> Vec<u8> {
    text.bytes().take(n as usize).collect()
}

/// Five arguments plus the out-cell: the broken-application layout.
#[axiom_export]
pub fn wide(a: i64, b: i64, c: i64, d: i64, e: i64) -> String {
    format!("{a}{b}{c}{d}{e}")
}

#[axiom_export]
pub fn ratio(a: i32, b: i32) -> Result<f64, String> {
    Ok(a as f64 / b as f64)
}

#[axiom_export]
pub fn check(flag: bool) -> Option<bool> {
    Some(!flag)
}

#[axiom_export]
pub fn nothing(n: i64) {
    let _ = n;
}

#[axiom_export]
pub fn unit_result(n: i64) -> Result<(), String> {
    if n == 0 { Err("zero".into()) } else { Ok(()) }
}

#[axiom_export]
pub fn maybe_text(n: i64) -> Option<String> {
    if n > 0 { Some("yes".into()) } else { None }
}

/// Not `pub`: the macro would refuse it, and bindgen skips it.
#[axiom_export]
fn hidden(n: i64) -> i64 {
    n
}

/// A hand-written shim, bound raw: `AxWord` is `Foreign`, `i64` is `Int`.
#[no_mangle]
pub unsafe extern "C" fn axffi_peek(h: axiom_ffi::AxWord, offset: i64) -> i64 {
    let _ = (h, offset);
    0
}

pub mod inner {
    use axiom_ffi::axiom_export;

    #[axiom_export]
    pub fn nested_add(a: i64, b: i64) -> i64 {
        a + b
    }

    pub mod deeper {
        use axiom_ffi::axiom_export;

        #[axiom_export]
        pub fn deepest(flag: bool) -> bool {
            !flag
        }
    }
}
