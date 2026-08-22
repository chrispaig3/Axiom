//! Every shape the boundary accepts, compiled and exercised through the
//! generated shims exactly as Axiom would call them: words in, a word
//! out, an out-cell for the byte and fallible shapes.
#![allow(clippy::all)]

use axiom_ffi::{axiom_export, axiom_opaque, AxOutCell, AxStrRepr, AxWord, AX_ERR, AX_NONE, AX_OK};

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
pub fn scalars(
    a: i64, b: i32, c: i16, d: i8, e: u32, f: u16, g: u8, h: usize, i: isize, j: bool, k: f64, l: f32,
) -> i64 {
    a + b as i64 + c as i64 + d as i64 + e as i64 + f as i64 + g as i64 + h as i64 + i as i64
        + j as i64 + k as i64 + l as i64
}

#[axiom_export]
pub fn ret_i32(n: i32) -> i32 { n - 1 }

#[axiom_export]
pub fn ret_u8(n: u8) -> u8 { n }

#[axiom_export]
pub fn ret_f32(x: f32) -> f32 { x * 2.0 }

#[axiom_export]
pub fn ret_bool(x: bool) -> bool { !x }

#[axiom_export]
pub fn ret_unit(n: i64) { let _ = n; }

#[axiom_export]
pub fn ret_unit_explicit(n: i64) -> () { let _ = n; }

#[axiom_export]
pub fn nullary() -> i64 { 7 }

#[axiom_export]
pub fn text(s: &str) -> String { s.to_uppercase() }

#[axiom_export(utf8 = "lossy")]
pub fn text_lossy(s: &str) -> Vec<u8> { s.as_bytes().to_vec() }

#[axiom_export(symbol = "custom_symbol")]
pub fn renamed(b: &[u8]) -> i64 { b.len() as i64 }

#[axiom_export]
pub fn thing_new(n: i64) -> Thing { Thing { n } }

#[axiom_export]
pub fn thing_get(t: &Thing) -> i64 { t.n }

#[axiom_export]
pub fn thing_bump(t: &mut Thing) { t.n += 1; }

#[axiom_export]
pub fn thing_try(n: i64) -> Result<Thing, String> {
    if n < 0 { Err(format!("no: {n}")) } else { Ok(Thing { n }) }
}

#[axiom_export]
pub fn maybe_text(n: i64) -> Option<String> {
    if n > 0 { Some("yes".to_string()) } else { None }
}

#[axiom_export]
pub fn maybe_thing(n: i64) -> Option<Thing> {
    if n > 0 { Some(Thing { n }) } else { None }
}

#[axiom_export]
pub fn res_unit(s: &str) -> Result<(), std::num::ParseIntError> {
    s.parse::<i64>().map(|_| ())
}

#[axiom_export]
pub fn res_f64(s: &str) -> Result<f64, String> {
    s.parse::<f64>().map_err(|e| e.to_string())
}

#[axiom_export]
pub fn res_str(s: &str, n: u8) -> Result<String, String> {
    Ok(format!("{s}{n}"))
}

#[axiom_export]
pub fn widget_new(b: bool) -> Widget { if b { Widget::B } else { Widget::A } }

#[axiom_export]
pub fn widget_is_b(w: &Widget) -> bool { matches!(w, Widget::B) }

/// An Axiom `String` value as Rust sees it: the address of its three-word run.
fn ax_str(repr: &AxStrRepr) -> AxWord {
    repr as *const AxStrRepr as AxWord
}

fn cell_word(cell: &mut AxOutCell) -> AxWord {
    cell as *mut AxOutCell as AxWord
}

/// Copy the bytes a shim handed over, then free them the way Axiom glue does.
fn take_bytes(cell: &AxOutCell) -> Vec<u8> {
    let v = unsafe { std::slice::from_raw_parts(cell.payload as *const u8, cell.extra as usize) }.to_vec();
    unsafe { axiom_ffi::axffi_free_bytes(cell.payload as *mut u8, cell.extra) };
    v
}

fn main() {
    assert_eq!(axiom_ffi::ABI_VERSION, 2);
    assert_eq!(axiom_ffi::axffi_abi_version(), 2);

    // Scalars: every narrow kind in range, floats as bits, bool as 0/1.
    let two = 2.0f64.to_bits() as AxWord;
    let three = (3.0f32 as f64).to_bits() as AxWord;
    assert_eq!(axffi_scalars(1, 1, 1, -1, 1, 1, 1, 1, -1, 1, two, three), 11);
    assert_eq!(axffi_ret_i32(5), 4);
    assert_eq!(axffi_ret_i32(i32::MIN as AxWord + 1), i32::MIN as AxWord);
    assert_eq!(axffi_ret_u8(255), 255);
    assert_eq!(f64::from_bits(axffi_ret_f32(three as AxWord) as u64), 6.0);
    assert_eq!(axffi_ret_bool(1), 0);
    assert_eq!(axffi_ret_unit(5), 0);
    assert_eq!(axffi_ret_unit_explicit(5), 0);
    assert_eq!(axffi_nullary(), 7);

    // Strings in, bytes out.
    let hello = AxStrRepr { len: 5, data: b"hello\0".as_ptr(), owner: 0 };
    let mut cell = AxOutCell { payload: 0, extra: 0 };
    assert_eq!(axffi_text(ax_str(&hello), cell_word(&mut cell)), AX_OK);
    assert_eq!(take_bytes(&cell), b"HELLO");
    let bad = AxStrRepr { len: 3, data: b"a\xffa\0".as_ptr(), owner: 0 };
    assert_eq!(axffi_text_lossy(ax_str(&bad), cell_word(&mut cell)), AX_OK);
    assert_eq!(take_bytes(&cell), "a\u{FFFD}a".as_bytes());
    assert_eq!(custom_symbol(ax_str(&bad)), 3);

    // Opaque handles: the word is a boxed address; borrow, mutate, drop.
    let h = axffi_thing_new(41);
    assert_ne!(h, 0);
    assert_eq!(axffi_thing_get(h), 41);
    assert_eq!(axffi_thing_bump(h), 0);
    assert_eq!(axffi_thing_get(h), 42);
    assert_eq!(unsafe { axffi_thing_drop(h) }, 0);
    assert_eq!(unsafe { axffi_thing_drop(0) }, 0);
    assert_eq!(axffi_thing_drop_fn(), axffi_thing_drop as usize as AxWord);
    assert_eq!(<Thing as axiom_ffi::AxiomOpaque>::STEM, "thing");
    assert_eq!(<Widget as axiom_ffi::AxiomOpaque>::STEM, "widget_v2");
    let w = axffi_widget_new(1);
    assert_eq!(axffi_widget_is_b(w), 1);
    assert_eq!(unsafe { axffi_widget_v2_drop(w) }, 0);
    assert_eq!(axffi_widget_v2_drop_fn(), axffi_widget_v2_drop as usize as AxWord);

    // Result: 0 + payload, 1 + message.
    assert_eq!(axffi_thing_try(3, cell_word(&mut cell)), AX_OK);
    assert_eq!(axffi_thing_get(cell.payload), 3);
    assert_eq!(unsafe { axffi_thing_drop(cell.payload) }, 0);
    assert_eq!(axffi_thing_try(-3, cell_word(&mut cell)), AX_ERR);
    assert_eq!(take_bytes(&cell), b"no: -3");
    // A fallible shim answers invalid UTF-8 as Err, never as a value.
    assert_eq!(axffi_res_unit(ax_str(&bad), cell_word(&mut cell)), AX_ERR);
    assert_eq!(take_bytes(&cell), b"argument 1 of `res_unit` is not valid UTF-8");
    let num = AxStrRepr { len: 3, data: b"1.5\0".as_ptr(), owner: 0 };
    assert_eq!(axffi_res_unit(ax_str(&hello), cell_word(&mut cell)), AX_ERR);
    let _ = take_bytes(&cell);
    assert_eq!(axffi_res_f64(ax_str(&num), cell_word(&mut cell)), AX_OK);
    assert_eq!(f64::from_bits(cell.payload as u64), 1.5);
    assert_eq!(axffi_res_str(ax_str(&hello), 7, cell_word(&mut cell)), AX_OK);
    assert_eq!(take_bytes(&cell), b"hello7");

    // Option: 0 + payload, 2 = None.
    assert_eq!(axffi_maybe_text(1, cell_word(&mut cell)), AX_OK);
    assert_eq!(take_bytes(&cell), b"yes");
    assert_eq!(axffi_maybe_text(0, cell_word(&mut cell)), AX_NONE);
    assert_eq!(axffi_maybe_thing(9, cell_word(&mut cell)), AX_OK);
    assert_eq!(axffi_thing_get(cell.payload), 9);
    assert_eq!(unsafe { axffi_thing_drop(cell.payload) }, 0);
    assert_eq!(axffi_maybe_thing(0, cell_word(&mut cell)), AX_NONE);
}
