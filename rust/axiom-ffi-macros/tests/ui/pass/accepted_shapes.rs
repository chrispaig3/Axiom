//! Every shape the boundary accepts, compiled and exercised through the
//! generated shims exactly as Axiom would call them: words in, a word
//! out, an out-cell for the byte and fallible shapes.
#![allow(clippy::all)]

use axiom_ffi::{
    axiom_export, axiom_opaque, axiom_record, AxFn1, AxFn2, AxFn3, AxOutCell, AxRecord,
    AxStrRepr, AxVecRepr, AxWord, AX_ERR, AX_NONE, AX_OK,
};

/// A record declared AFTER the exports that name it (`pair_*` below
/// sit above `Pair` in this file in spirit; `Point` is used by
/// `point_norm2` before its own declaration in source order): the
/// companion macro resolves by path, not textually.
#[axiom_export]
pub fn point_norm2(p: Point) -> f64 { (p.x as f64) * (p.x as f64) + p.y * p.y }

#[axiom_opaque]
pub struct Thing {
    n: i64,
}

// Records: every word scalar kind as a field, crossing as its words.
#[axiom_record]
pub struct Point {
    pub x: i64,
    pub y: f64,
}

#[axiom_record]
#[derive(Clone)]
pub struct Mixed {
    pub a: i32,
    pub b: u8,
    pub c: bool,
    pub d: f32,
    pub e: usize,
}

#[axiom_export]
pub fn point_origin() -> Point { Point { x: 0, y: 0.0 } }

#[axiom_export]
pub fn point_scale(p: Point, k: i64) -> Point { Point { x: p.x * k, y: p.y * k as f64 } }

#[axiom_export]
pub fn point_try(ok: bool) -> Result<Point, String> {
    if ok { Ok(Point { x: 3, y: 4.0 }) } else { Err("no point".into()) }
}

#[axiom_export]
pub fn point_maybe(ok: bool) -> Option<Point> { ok.then_some(Point { x: -1, y: 0.5 }) }

#[axiom_export]
pub fn mixed_sum(m: Mixed, t: &Thing) -> i64 {
    m.a as i64 + m.b as i64 + m.c as i64 + m.d as i64 + m.e as i64 + t.n
}

#[axiom_export]
pub fn mixed_make(a: i32) -> Mixed { Mixed { a, b: 7, c: true, d: 1.5, e: 9 } }

// A record named through a module path, and two records in one call.
pub mod geom {
    #[axiom_ffi::axiom_record]
    pub struct Size {
        pub w: i64,
        pub h: i64,
    }
}

#[axiom_export]
pub fn area(s: geom::Size, p: Point) -> i64 { s.w * s.h + p.x }

// Slices over every word scalar, and a slice of strings.
#[axiom_export]
pub fn sum_f64(xs: &[f64]) -> f64 { xs.iter().sum() }

#[axiom_export]
pub fn sum_u8_bytes(xs: &[u8]) -> i64 { xs.iter().map(|b| *b as i64).sum() }

#[axiom_export]
pub fn sum_i16(xs: &[i16]) -> i64 { xs.iter().map(|b| *b as i64).sum() }

#[axiom_export]
pub fn count_true(xs: &[bool]) -> i64 { xs.iter().filter(|b| **b).count() as i64 }

#[axiom_export]
pub fn sum_f32(xs: &[f32]) -> f32 { xs.iter().sum() }

#[axiom_export]
pub fn join(parts: &[&str]) -> String { parts.join("+") }

#[axiom_export]
pub fn join_try(parts: &[&str]) -> Result<String, String> { Ok(parts.join("+")) }

#[axiom_export(utf8 = "lossy")]
pub fn join_lossy(parts: &[&str]) -> String { parts.join("+") }

#[axiom_export]
pub fn flags(n: i64) -> Vec<bool> { (0..n).map(|i| i % 2 == 0).collect() }

#[axiom_export]
pub fn halves32(n: i64) -> Vec<f32> { (0..n).map(|i| i as f32 / 2.0).collect() }

#[axiom_export]
pub fn negs(n: i64) -> Vec<i8> { (0..n).map(|i| -(i as i8)).collect() }

#[axiom_export]
pub fn try_flags(n: i64) -> Result<Vec<bool>, String> {
    if n < 0 { Err("negative".into()) } else { Ok(flags(n)) }
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

// Callbacks: the closure record word, called through word 0.
#[axiom_export]
pub fn twice(f: AxFn1, x: i64) -> i64 { f.call(f.call(x)) }

#[axiom_export]
pub fn fold(f: AxFn2, a: i64, b: i64, c: i64) -> i64 { f.call(f.call(a, b), c) }

#[axiom_export]
pub fn three(f: axiom_ffi::AxFn3) -> i64 { f.call(1, 2, 3) }

// Collections: words and strings out through the cell, words in as a Vec handle.
#[axiom_export]
pub fn range(n: i64) -> Vec<i64> { (0..n).collect() }

#[axiom_export]
pub fn words(s: &str) -> Vec<String> { s.split(' ').map(String::from).collect() }

#[axiom_export]
pub fn total(xs: &[i64]) -> i64 { xs.iter().sum() }

#[axiom_export]
pub fn try_range(n: i64) -> Result<Vec<i64>, String> {
    if n < 0 { Err("negative".into()) } else { Ok(range(n)) }
}

#[axiom_export]
pub fn maybe_words(s: &str) -> Option<Vec<String>> {
    if s.is_empty() { None } else { Some(words(s)) }
}

// `char` and `u64` as words: parameters, returns, record fields, Vec
// elements, slice elements and payloads.
#[axiom_export]
pub fn next_char(c: char) -> char { char::from_u32(c as u32 + 1).unwrap_or(c) }

#[axiom_export]
pub fn wrap_u64(x: u64) -> u64 { x.wrapping_add(1) }

#[axiom_export]
pub fn chars_of(s: &str) -> Vec<char> { s.chars().collect() }

#[axiom_export]
pub fn from_chars(cs: &[char]) -> String { cs.iter().collect() }

#[axiom_export]
pub fn sum_u64(xs: &[u64]) -> u64 { xs.iter().fold(0u64, |a, b| a.wrapping_add(*b)) }

#[axiom_export]
pub fn big(n: i64) -> Vec<u64> { (0..n).map(|i| u64::MAX - i as u64).collect() }

#[axiom_export]
pub fn maybe_char(c: char) -> Option<char> { (c != 'x').then_some(c) }

#[axiom_export]
pub fn try_u64(s: &str) -> Result<u64, String> { s.parse::<u64>().map_err(|e| e.to_string()) }

#[axiom_record]
pub struct Glyph {
    pub c: char,
    pub code: u64,
}

#[axiom_export]
pub fn glyph_of(c: char) -> Glyph { Glyph { c, code: c as u64 } }

#[axiom_export]
pub fn glyph_code(g: Glyph) -> u64 { g.code.wrapping_add(g.c as u64) }

// Records in Vecs, each way, bare and behind a status.
#[axiom_export]
pub fn points_scale(ps: &[Point], k: i64) -> Vec<Point> {
    ps.iter().map(|p| Point { x: p.x * k, y: p.y * k as f64 }).collect()
}

#[axiom_export]
pub fn points_try(ps: &[Point]) -> Result<Vec<Point>, String> {
    if ps.is_empty() { Err("no points".into()) } else { Ok(points_scale(ps, 1)) }
}

#[axiom_export]
pub fn points_maybe(n: i64) -> Option<Vec<Point>> {
    (n >= 0).then(|| (0..n).map(|i| Point { x: i, y: 0.5 }).collect())
}

#[axiom_export]
pub fn mixed_all(ms: &[Mixed]) -> Vec<Mixed> { ms.to_vec() }

// Nested Vecs over word scalars: in place for i64/f64/u64, converted
// for the rest.
#[axiom_export]
pub fn grid(n: i64) -> Vec<Vec<i64>> { (0..n).map(|r| (0..n).map(|c| r * n + c).collect()).collect() }

#[axiom_export]
pub fn grid_f32(n: i64) -> Vec<Vec<f32>> { (0..n).map(|r| vec![r as f32 / 2.0; 2]).collect() }

#[axiom_export]
pub fn sum_rows(rows: &[&[i64]]) -> i64 { rows.iter().map(|r| r.iter().sum::<i64>()).sum() }

#[axiom_export]
pub fn sum_rows_f64(rows: &[&[f64]]) -> f64 { rows.iter().map(|r| r.iter().sum::<f64>()).sum() }

#[axiom_export]
pub fn sum_rows_u64(rows: &[&[u64]]) -> u64 { rows.iter().flat_map(|r| r.iter()).fold(0u64, |a, b| a.wrapping_add(*b)) }

#[axiom_export]
pub fn count_rows_true(rows: &[&[bool]]) -> i64 {
    rows.iter().map(|r| r.iter().filter(|b| **b).count() as i64).sum()
}

#[axiom_export]
pub fn try_grid(n: i64) -> Result<Vec<Vec<i64>>, String> {
    if n < 0 { Err("negative".into()) } else { Ok(grid(n)) }
}

// Mutable slices, in place.
#[axiom_export]
pub fn double_in_place(xs: &mut [i64]) -> i64 {
    for x in xs.iter_mut() { *x *= 2; }
    xs.len() as i64
}

#[axiom_export]
pub fn halve_in_place(xs: &mut [f64]) {
    for x in xs.iter_mut() { *x /= 2.0; }
}

#[axiom_export]
pub fn bump_in_place(xs: &mut [u64]) -> u64 {
    for x in xs.iter_mut() { *x = x.wrapping_add(1); }
    xs.iter().copied().fold(0u64, u64::wrapping_add)
}

// Nested fallible results over the three statuses.
#[axiom_export]
pub fn maybe_parse(s: &str) -> Result<Option<i64>, String> {
    let s = s.trim();
    if s.is_empty() { return Ok(None); }
    s.parse::<i64>().map(Some).map_err(|e| e.to_string())
}

#[axiom_export]
pub fn lookup(i: i64) -> Option<Result<i64, String>> {
    match i { 0 => None, i if i > 0 => Some(Ok(i * 10)), i => Some(Err(format!("negative {i}"))) }
}

#[axiom_export]
pub fn maybe_point(i: i64) -> Result<Option<Point>, String> {
    match i { 0 => Ok(None), i if i > 0 => Ok(Some(Point { x: i, y: 1.5 })), _ => Err("neg".into()) }
}

#[axiom_export]
pub fn find_thing(i: i64) -> Option<Result<Thing, String>> {
    match i { 0 => None, i if i > 0 => Some(Ok(Thing { n: i })), _ => Some(Err("neg".into())) }
}

#[axiom_export]
pub fn maybe_words_try(s: &str) -> Result<Option<Vec<i64>>, String> {
    if s.is_empty() { Ok(None) } else { Ok(Some(vec![s.len() as i64])) }
}

#[axiom_export]
pub fn text_lookup(s: &str) -> Option<Result<String, String>> {
    if s.is_empty() { None } else { Some(Ok(s.to_uppercase())) }
}

/// What the compiler emits for `(lambda (x) (+ x k))` with `k` captured
/// in word 1: the hidden environment first, then the argument.
extern "C" fn lam_add_k(env: AxWord, x: AxWord) -> AxWord {
    let k = unsafe { *(env as *const AxWord).add(1) };
    x + k
}

/// Every Axiom function value absorbs ONE argument: `(lambda (a b) ..)`
/// is `(lambda (a) (lambda (b) ..))`, so the outer link answers the
/// inner link's record (`[code, a]`), owned by the caller. This is the
/// chain `AxFn2::call` / `AxFn3::call` walk, releasing each link.
extern "C" fn lam_plus_outer(_env: AxWord, a: AxWord) -> AxWord {
    Box::into_raw(Box::new([lam_add_k as usize as AxWord, a])) as AxWord
}

extern "C" fn lam_sum3_outer(_env: AxWord, a: AxWord) -> AxWord {
    Box::into_raw(Box::new([lam_sum3_middle as usize as AxWord, a])) as AxWord
}

extern "C" fn lam_sum3_middle(env: AxWord, b: AxWord) -> AxWord {
    let a = unsafe { *(env as *const AxWord).add(1) };
    Box::into_raw(Box::new([lam_add_k as usize as AxWord, a + b])) as AxWord
}

/// No Axiom runtime is linked here, so the chain's releases land on a
/// stub that frees the two-word links the outer/middle steps boxed.
#[no_mangle]
pub extern "C" fn axiom_release(h: AxWord) {
    RELEASED.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    drop(unsafe { Box::from_raw(h as *mut [AxWord; 2]) });
}

#[no_mangle]
pub extern "C" fn axiom_retain(_h: AxWord) {}

static RELEASED: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

/// Copy the words a shim handed over, then free them the way Axiom glue does.
fn take_words(cell: &AxOutCell) -> Vec<i64> {
    let v = unsafe { std::slice::from_raw_parts(cell.payload as *const i64, cell.extra as usize) }.to_vec();
    unsafe { axiom_ffi::axffi_free_words(cell.payload as *mut i64, cell.extra) };
    v
}

/// Copy every string of a `(pairs, n)` list, then free the list.
fn take_strs(cell: &AxOutCell) -> Vec<String> {
    let n = cell.extra as usize;
    let pairs = unsafe { std::slice::from_raw_parts(cell.payload as *const i64, n * 2) };
    let v = pairs
        .chunks_exact(2)
        .map(|p| unsafe { std::slice::from_raw_parts(p[0] as *const u8, p[1] as usize) })
        .map(|b| String::from_utf8(b.to_vec()).unwrap())
        .collect();
    unsafe { axiom_ffi::axffi_free_str_list(cell.payload as *mut i64, cell.extra) };
    v
}

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

    // Callbacks: a record is [code, captures..]; the shim calls word 0
    // with the record as the environment.
    let add_ten: [AxWord; 2] = [lam_add_k as usize as AxWord, 10];
    let add_ten_rec = add_ten.as_ptr() as AxWord;
    assert_eq!(axffi_twice(add_ten_rec, 1), 21);
    // Two and three arguments: one link per argument, each released.
    let plus: [AxWord; 1] = [lam_plus_outer as usize as AxWord];
    assert_eq!(axffi_fold(plus.as_ptr() as AxWord, 1, 2, 3), 6);
    assert_eq!(RELEASED.load(std::sync::atomic::Ordering::Relaxed), 2);
    let sum3: [AxWord; 1] = [lam_sum3_outer as usize as AxWord];
    assert_eq!(axffi_three(sum3.as_ptr() as AxWord), 6);
    assert_eq!(RELEASED.load(std::sync::atomic::Ordering::Relaxed), 4);
    let direct = unsafe { <AxFn1 as axiom_ffi::AxCallback>::from_raw(add_ten_rec) };
    assert_eq!(direct.call(5), 15);
    assert_eq!(direct.as_word(), add_ten_rec);
    assert_eq!(<AxFn2 as axiom_ffi::AxCallback>::ARITY, 2);
    assert_eq!(<AxFn3 as axiom_ffi::AxCallback>::ARITY, 3);

    // Words out: (ptr, len); an empty Vec is (dangling, 0) and frees as a no-op.
    assert_eq!(axffi_range(4, cell_word(&mut cell)), AX_OK);
    assert_eq!(take_words(&cell), vec![0, 1, 2, 3]);
    assert_eq!(axffi_range(0, cell_word(&mut cell)), AX_OK);
    assert_eq!(cell.extra, 0);
    assert_eq!(take_words(&cell), Vec::<i64>::new());
    // Strings out: (pairs, n).
    let text = AxStrRepr { len: 9, data: b"ab cd efg\0".as_ptr(), owner: 0 };
    assert_eq!(axffi_words(ax_str(&text), cell_word(&mut cell)), AX_OK);
    assert_eq!(take_strs(&cell), vec!["ab", "cd", "efg"]);
    // Words in: an Axiom Vec handle, len at word 0 and data at word 2.
    let data = [5i64, 6, 7, 0, 0];
    let vec = AxVecRepr { len: 3, cap: 5, data: data.as_ptr() };
    assert_eq!(axffi_total(&vec as *const AxVecRepr as AxWord), 18);
    let empty = AxVecRepr { len: 0, cap: 8, data: std::ptr::null() };
    assert_eq!(axffi_total(&empty as *const AxVecRepr as AxWord), 0);
    // Inside Result and Option.
    assert_eq!(axffi_try_range(3, cell_word(&mut cell)), AX_OK);
    assert_eq!(take_words(&cell), vec![0, 1, 2]);
    assert_eq!(axffi_try_range(-1, cell_word(&mut cell)), AX_ERR);
    assert_eq!(take_bytes(&cell), b"negative");
    assert_eq!(axffi_maybe_words(ax_str(&text), cell_word(&mut cell)), AX_OK);
    assert_eq!(take_strs(&cell).len(), 3);
    let none = AxStrRepr { len: 0, data: b"\0".as_ptr(), owner: 0 };
    assert_eq!(axffi_maybe_words(ax_str(&none), cell_word(&mut cell)), AX_NONE);

    // Records: a parameter is one word per field, a result is ARITY
    // words from the cell's first word (the cell is ffiCellNewN ARITY,
    // so a five-field record needs a five-word cell here too).
    assert_eq!(<Point as AxRecord>::ARITY, 2);
    assert_eq!(<Mixed as AxRecord>::ARITY, 5);
    let four = 4.0f64.to_bits() as AxWord;
    assert_eq!(f64::from_bits(axffi_point_norm2(3, four) as u64), 25.0);
    let mut big = [0 as AxWord; 5];
    let big_word = big.as_mut_ptr() as AxWord;
    assert_eq!(axffi_point_origin(big_word), AX_OK);
    assert_eq!(big[0], 0);
    assert_eq!(f64::from_bits(big[1] as u64), 0.0);
    assert_eq!(axffi_point_scale(2, 1.5f64.to_bits() as AxWord, 4, big_word), AX_OK);
    assert_eq!(big[0], 8);
    assert_eq!(f64::from_bits(big[1] as u64), 6.0);
    assert_eq!(axffi_point_try(1, big_word), AX_OK);
    assert_eq!((big[0], f64::from_bits(big[1] as u64)), (3, 4.0));
    assert_eq!(axffi_point_try(0, cell_word(&mut cell)), AX_ERR);
    assert_eq!(take_bytes(&cell), b"no point");
    assert_eq!(axffi_point_maybe(1, big_word), AX_OK);
    assert_eq!((big[0], f64::from_bits(big[1] as u64)), (-1, 0.5));
    assert_eq!(axffi_point_maybe(0, big_word), AX_NONE);
    // Every field kind: narrow ints range-checked like arguments, bool
    // 0/1, f32 as f64 bits, usize a word.
    let t = axffi_thing_new(100);
    assert_eq!(axffi_mixed_sum(-5, 255, 1, 2.75f64.to_bits() as AxWord, 9, t), -5 + 255 + 1 + 2 + 9 + 100);
    assert_eq!(unsafe { axffi_thing_drop(t) }, 0);
    assert_eq!(axffi_mixed_make(-3, big_word), AX_OK);
    assert_eq!(big, [-3, 7, 1, 1.5f64.to_bits() as AxWord, 9]);
    let m = <Mixed as AxRecord>::from_words(&big);
    assert_eq!((m.a, m.b, m.c, m.d, m.e), (-3, 7, true, 1.5, 9));
    let mut back = [0 as AxWord; 5];
    m.write_words(&mut back);
    assert_eq!(back, big);
    assert_eq!(axffi_area(3, 4, 10, four), 22);
    assert_eq!(<geom::Size as AxRecord>::ARITY, 2);

    // Slices over every word scalar: f64 in place, the rest converted.
    let fdata = [1.25f64.to_bits() as i64, 2.5f64.to_bits() as i64, (-0.75f64).to_bits() as i64];
    let fvec = AxVecRepr { len: 3, cap: 3, data: fdata.as_ptr() };
    assert_eq!(f64::from_bits(axffi_sum_f64(&fvec as *const AxVecRepr as AxWord) as u64), 3.0);
    let idata = [-300i64, 300, 7];
    let ivec = AxVecRepr { len: 3, cap: 3, data: idata.as_ptr() };
    assert_eq!(axffi_sum_i16(&ivec as *const AxVecRepr as AxWord), 7);
    let bdata = [1i64, 0, 1, 1];
    let bvec = AxVecRepr { len: 4, cap: 4, data: bdata.as_ptr() };
    assert_eq!(axffi_count_true(&bvec as *const AxVecRepr as AxWord), 3);
    let f32data = [(0.5f32 as f64).to_bits() as i64, (1.5f32 as f64).to_bits() as i64];
    let f32vec = AxVecRepr { len: 2, cap: 2, data: f32data.as_ptr() };
    assert_eq!(f64::from_bits(axffi_sum_f32(&f32vec as *const AxVecRepr as AxWord) as u64), 2.0);
    // `&[u8]` is still the byte view of a String, not a Vec.
    assert_eq!(axffi_sum_u8_bytes(ax_str(&hello)), b"hello".iter().map(|b| *b as i64).sum::<i64>());
    // A slice of strings: a Vec whose words are String handles.
    let brave = AxStrRepr { len: 5, data: b"brave ".as_ptr(), owner: 0 };
    let sdata = [ax_str(&hello), ax_str(&brave)];
    let svec = AxVecRepr { len: 2, cap: 2, data: sdata.as_ptr() };
    let svec_word = &svec as *const AxVecRepr as AxWord;
    assert_eq!(axffi_join(svec_word, cell_word(&mut cell)), AX_OK);
    assert_eq!(take_bytes(&cell), b"hello+brave");
    let bad_data = [ax_str(&hello), ax_str(&bad)];
    let bad_vec = AxVecRepr { len: 2, cap: 2, data: bad_data.as_ptr() };
    let bad_word = &bad_vec as *const AxVecRepr as AxWord;
    assert_eq!(axffi_join_try(bad_word, cell_word(&mut cell)), AX_ERR);
    assert_eq!(take_bytes(&cell), b"element 1 of argument 1 of `join_try` is not valid UTF-8");
    assert_eq!(axffi_join_lossy(bad_word, cell_word(&mut cell)), AX_OK);
    assert_eq!(take_bytes(&cell), "hello+a\u{FFFD}a".as_bytes());
    let empty_vec = AxVecRepr { len: 0, cap: 0, data: std::ptr::null() };
    assert_eq!(axffi_join(&empty_vec as *const AxVecRepr as AxWord, cell_word(&mut cell)), AX_OK);
    assert_eq!(take_bytes(&cell), b"");
    // Vec<T> results: every element widened to a word.
    assert_eq!(axffi_flags(4, cell_word(&mut cell)), AX_OK);
    assert_eq!(take_words(&cell), vec![1, 0, 1, 0]);
    assert_eq!(axffi_halves32(3, cell_word(&mut cell)), AX_OK);
    assert_eq!(take_words(&cell), vec![0, (0.5f64).to_bits() as i64, 1.0f64.to_bits() as i64]);
    assert_eq!(axffi_negs(3, cell_word(&mut cell)), AX_OK);
    assert_eq!(take_words(&cell), vec![0, -1, -2]);
    assert_eq!(axffi_try_flags(2, cell_word(&mut cell)), AX_OK);
    assert_eq!(take_words(&cell), vec![1, 0]);
    assert_eq!(axffi_try_flags(-1, cell_word(&mut cell)), AX_ERR);
    assert_eq!(take_bytes(&cell), b"negative");

    // `char` and `u64`: the code point and the unsigned bits, in every
    // position; a bad code point would abort (probed by the Axiom gate).
    assert_eq!(axffi_next_char('a' as AxWord), 'b' as AxWord);
    assert_eq!(axffi_wrap_u64(-1), 0);
    assert_eq!(axffi_wrap_u64(5), 6);
    let hi = AxStrRepr { len: 2, data: b"hi\0".as_ptr(), owner: 0 };
    assert_eq!(axffi_chars_of(ax_str(&hi), cell_word(&mut cell)), AX_OK);
    assert_eq!(take_words(&cell), vec!['h' as i64, 'i' as i64]);
    let cdata = ['o' as i64, 'k' as i64];
    let cvec = AxVecRepr { len: 2, cap: 2, data: cdata.as_ptr() };
    assert_eq!(axffi_from_chars(&cvec as *const AxVecRepr as AxWord, cell_word(&mut cell)), AX_OK);
    assert_eq!(take_bytes(&cell), b"ok");
    let udata = [-1i64, 2];
    let uvec = AxVecRepr { len: 2, cap: 2, data: udata.as_ptr() };
    assert_eq!(axffi_sum_u64(&uvec as *const AxVecRepr as AxWord), 1);
    assert_eq!(axffi_big(2, cell_word(&mut cell)), AX_OK);
    assert_eq!(take_words(&cell), vec![-1, -2]);
    assert_eq!(axffi_maybe_char('q' as AxWord, cell_word(&mut cell)), AX_OK);
    assert_eq!(cell.payload, 'q' as AxWord);
    assert_eq!(axffi_maybe_char('x' as AxWord, cell_word(&mut cell)), AX_NONE);
    let huge = AxStrRepr { len: 20, data: b"18446744073709551615\0".as_ptr(), owner: 0 };
    assert_eq!(axffi_try_u64(ax_str(&huge), cell_word(&mut cell)), AX_OK);
    assert_eq!(cell.payload, -1);
    assert_eq!(axffi_glyph_of('z' as AxWord, big_word), AX_OK);
    assert_eq!((big[0], big[1]), ('z' as AxWord, 'z' as AxWord));
    assert_eq!(axffi_glyph_code('z' as AxWord, -1), ('z' as u64).wrapping_add(u64::MAX) as AxWord);
    assert_eq!(<Glyph as AxRecord>::ARITY, 2);

    // Records in Vecs: `&[Point]` is ARITY words per element, chunked;
    // `Vec<Point>` answers (ptr, n) over n * ARITY words.
    let pdata = [1i64, 0.5f64.to_bits() as i64, -2, 1.25f64.to_bits() as i64];
    let pvec = AxVecRepr { len: 4, cap: 4, data: pdata.as_ptr() };
    let pvec_word = &pvec as *const AxVecRepr as AxWord;
    assert_eq!(axffi_points_scale(pvec_word, 4, cell_word(&mut cell)), AX_OK);
    assert_eq!(cell.extra, 2);
    let scaled = unsafe { std::slice::from_raw_parts(cell.payload as *const i64, 4) }.to_vec();
    unsafe { axiom_ffi::axffi_free_words(cell.payload as *mut i64, cell.extra * 2) };
    assert_eq!(scaled, vec![4, 2.0f64.to_bits() as i64, -8, 5.0f64.to_bits() as i64]);
    assert_eq!(axffi_points_try(pvec_word, cell_word(&mut cell)), AX_OK);
    assert_eq!(cell.extra, 2);
    unsafe { axiom_ffi::axffi_free_words(cell.payload as *mut i64, cell.extra * 2) };
    assert_eq!(axffi_points_try(&empty_vec as *const AxVecRepr as AxWord, cell_word(&mut cell)), AX_ERR);
    assert_eq!(take_bytes(&cell), b"no points");
    assert_eq!(axffi_points_maybe(3, cell_word(&mut cell)), AX_OK);
    assert_eq!(cell.extra, 3);
    let three = unsafe { std::slice::from_raw_parts(cell.payload as *const i64, 6) }.to_vec();
    unsafe { axiom_ffi::axffi_free_words(cell.payload as *mut i64, 6) };
    assert_eq!(three[4], 2);
    assert_eq!(axffi_points_maybe(-1, cell_word(&mut cell)), AX_NONE);
    assert_eq!(axffi_points_maybe(0, cell_word(&mut cell)), AX_OK);
    assert_eq!(cell.extra, 0);
    unsafe { axiom_ffi::axffi_free_words(cell.payload as *mut i64, 0) };
    let mdata = [-3i64, 7, 1, 1.5f64.to_bits() as i64, 9];
    let mvec = AxVecRepr { len: 5, cap: 5, data: mdata.as_ptr() };
    assert_eq!(axffi_mixed_all(&mvec as *const AxVecRepr as AxWord, cell_word(&mut cell)), AX_OK);
    assert_eq!(cell.extra, 1);
    let back = unsafe { std::slice::from_raw_parts(cell.payload as *const i64, 5) }.to_vec();
    unsafe { axiom_ffi::axffi_free_words(cell.payload as *mut i64, 5) };
    assert_eq!(back, mdata);

    // Nested Vecs: (pairs, n) out, a Vec of Vec handles in.
    assert_eq!(axffi_grid(2, cell_word(&mut cell)), AX_OK);
    assert_eq!(cell.extra, 2);
    let pairs = unsafe { std::slice::from_raw_parts(cell.payload as *const i64, 4) }.to_vec();
    let row1 = unsafe { std::slice::from_raw_parts(pairs[2] as *const i64, pairs[3] as usize) }.to_vec();
    assert_eq!(row1, vec![2, 3]);
    unsafe { axiom_ffi::axffi_free_word_lists(cell.payload as *mut i64, cell.extra) };
    assert_eq!(axffi_grid_f32(2, cell_word(&mut cell)), AX_OK);
    let pairs = unsafe { std::slice::from_raw_parts(cell.payload as *const i64, 4) }.to_vec();
    let row1 = unsafe { std::slice::from_raw_parts(pairs[2] as *const i64, pairs[3] as usize) }.to_vec();
    assert_eq!(row1, vec![0.5f64.to_bits() as i64; 2]);
    unsafe { axiom_ffi::axffi_free_word_lists(cell.payload as *mut i64, cell.extra) };
    assert_eq!(axffi_grid(0, cell_word(&mut cell)), AX_OK);
    assert_eq!(cell.extra, 0);
    unsafe { axiom_ffi::axffi_free_word_lists(cell.payload as *mut i64, 0) };
    let rows = [&vec as *const AxVecRepr as AxWord, &ivec as *const AxVecRepr as AxWord];
    let rvec = AxVecRepr { len: 2, cap: 2, data: rows.as_ptr() };
    assert_eq!(axffi_sum_rows(&rvec as *const AxVecRepr as AxWord), 18 + 7);
    let frows = [&fvec as *const AxVecRepr as AxWord];
    let frvec = AxVecRepr { len: 1, cap: 1, data: frows.as_ptr() };
    assert_eq!(f64::from_bits(axffi_sum_rows_f64(&frvec as *const AxVecRepr as AxWord) as u64), 3.0);
    let urows = [&uvec as *const AxVecRepr as AxWord];
    let urvec = AxVecRepr { len: 1, cap: 1, data: urows.as_ptr() };
    assert_eq!(axffi_sum_rows_u64(&urvec as *const AxVecRepr as AxWord), 1);
    let brows = [&bvec as *const AxVecRepr as AxWord, &bvec as *const AxVecRepr as AxWord];
    let brvec = AxVecRepr { len: 2, cap: 2, data: brows.as_ptr() };
    assert_eq!(axffi_count_rows_true(&brvec as *const AxVecRepr as AxWord), 6);
    assert_eq!(axffi_sum_rows(&empty_vec as *const AxVecRepr as AxWord), 0);
    assert_eq!(axffi_try_grid(-1, cell_word(&mut cell)), AX_ERR);
    assert_eq!(take_bytes(&cell), b"negative");

    // Mutable slices: the Vec's own words change.
    let mut mdata = [1i64, -2, 30];
    let mvec = AxVecRepr { len: 3, cap: 3, data: mdata.as_mut_ptr() };
    assert_eq!(axffi_double_in_place(&mvec as *const AxVecRepr as AxWord), 3);
    assert_eq!(mdata, [2, -4, 60]);
    let mut fd = [1.0f64.to_bits() as i64, 3.0f64.to_bits() as i64];
    let fmv = AxVecRepr { len: 2, cap: 2, data: fd.as_mut_ptr() };
    assert_eq!(axffi_halve_in_place(&fmv as *const AxVecRepr as AxWord), 0);
    assert_eq!(fd, [0.5f64.to_bits() as i64, 1.5f64.to_bits() as i64]);
    let mut ud = [-1i64, 1];
    let umv = AxVecRepr { len: 2, cap: 2, data: ud.as_mut_ptr() };
    assert_eq!(axffi_bump_in_place(&umv as *const AxVecRepr as AxWord), 2);
    assert_eq!(ud, [0, 2]);
    assert_eq!(axffi_double_in_place(&empty_vec as *const AxVecRepr as AxWord), 0);

    // Nested fallible: 0 / 2 / 1 map onto the nested constructors.
    let forty_two = AxStrRepr { len: 2, data: b"42\0".as_ptr(), owner: 0 };
    assert_eq!(axffi_maybe_parse(ax_str(&forty_two), cell_word(&mut cell)), AX_OK);
    assert_eq!(cell.payload, 42);
    assert_eq!(axffi_maybe_parse(ax_str(&none), cell_word(&mut cell)), AX_NONE);
    assert_eq!(axffi_maybe_parse(ax_str(&hello), cell_word(&mut cell)), AX_ERR);
    assert_eq!(take_bytes(&cell), b"invalid digit found in string");
    // An invalid `&str` into a nested fallible shim is the Err state.
    assert_eq!(axffi_maybe_parse(ax_str(&bad), cell_word(&mut cell)), AX_ERR);
    assert_eq!(take_bytes(&cell), b"argument 1 of `maybe_parse` is not valid UTF-8");
    assert_eq!(axffi_lookup(3, cell_word(&mut cell)), AX_OK);
    assert_eq!(cell.payload, 30);
    assert_eq!(axffi_lookup(0, cell_word(&mut cell)), AX_NONE);
    assert_eq!(axffi_lookup(-2, cell_word(&mut cell)), AX_ERR);
    assert_eq!(take_bytes(&cell), b"negative -2");
    assert_eq!(axffi_maybe_point(2, big_word), AX_OK);
    assert_eq!((big[0], f64::from_bits(big[1] as u64)), (2, 1.5));
    assert_eq!(axffi_maybe_point(0, big_word), AX_NONE);
    assert_eq!(axffi_maybe_point(-1, cell_word(&mut cell)), AX_ERR);
    assert_eq!(take_bytes(&cell), b"neg");
    assert_eq!(axffi_find_thing(5, cell_word(&mut cell)), AX_OK);
    assert_eq!(axffi_thing_get(cell.payload), 5);
    assert_eq!(unsafe { axffi_thing_drop(cell.payload) }, 0);
    assert_eq!(axffi_find_thing(0, cell_word(&mut cell)), AX_NONE);
    assert_eq!(axffi_find_thing(-1, cell_word(&mut cell)), AX_ERR);
    assert_eq!(take_bytes(&cell), b"neg");
    assert_eq!(axffi_maybe_words_try(ax_str(&hello), cell_word(&mut cell)), AX_OK);
    assert_eq!(take_words(&cell), vec![5]);
    assert_eq!(axffi_maybe_words_try(ax_str(&none), cell_word(&mut cell)), AX_NONE);
    assert_eq!(axffi_text_lookup(ax_str(&hello), cell_word(&mut cell)), AX_OK);
    assert_eq!(take_bytes(&cell), b"HELLO");
    assert_eq!(axffi_text_lookup(ax_str(&none), cell_word(&mut cell)), AX_NONE);

    // Every shim carries its signature descriptor, a no-op named for
    // the shape: one tag per word in, `_`, one for the word out.
    assert_eq!(axffi_next_char__sig_i_i(), 0);
    assert_eq!(axffi_wrap_u64__sig_i_i(), 0);
    assert_eq!(axffi_glyph_code__sig_ii_i(), 0);
    assert_eq!(axffi_points_scale__sig_iii_i(), 0);
    assert_eq!(axffi_sum_rows_f64__sig_i_f(), 0);
    assert_eq!(axffi_double_in_place__sig_i_i(), 0);
    assert_eq!(axffi_maybe_parse__sig_si_i(), 0);
    assert_eq!(axffi_lookup__sig_ii_i(), 0);
    assert_eq!(axffi_point_norm2__sig_if_f(), 0);
    assert_eq!(axffi_point_origin__sig_i_i(), 0);
    assert_eq!(axffi_point_scale__sig_ifii_i(), 0);
    assert_eq!(axffi_point_maybe__sig_ii_i(), 0);
    assert_eq!(axffi_mixed_sum__sig_iiifii_i(), 0);
    assert_eq!(axffi_area__sig_iiif_i(), 0);
    assert_eq!(axffi_sum_f64__sig_i_f(), 0);
    assert_eq!(axffi_join__sig_ii_i(), 0);
    assert_eq!(axffi_flags__sig_ii_i(), 0);
    assert_eq!(axffi_scalars__sig_iiiiiiiiiiff_i(), 0);
    assert_eq!(axffi_ret_f32__sig_f_f(), 0);
    assert_eq!(axffi_nullary__sig__i(), 0);
    assert_eq!(axffi_text__sig_si_i(), 0);
    assert_eq!(custom_symbol__sig_s_i(), 0);
    assert_eq!(axffi_thing_new__sig_i_i(), 0);
    assert_eq!(axffi_thing_bump__sig_i_i(), 0);
    assert_eq!(axffi_res_str__sig_sii_i(), 0);
    assert_eq!(axffi_twice__sig_ci_i(), 0);
    assert_eq!(axffi_fold__sig_ciii_i(), 0);
    assert_eq!(axffi_range__sig_ii_i(), 0);
    assert_eq!(axffi_words__sig_si_i(), 0);
    assert_eq!(axffi_total__sig_i_i(), 0);
}
