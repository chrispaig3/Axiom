//! A source tree the snapshot test feeds to the generator. It is never
//! compiled; it exists to pin the generated module's shape for every
//! wrapper kind, the `mod` recursion, the `pub`-only rule, the
//! attribute keys, the raw-shim path and a parameter named `cell`.

use axiom_ffi::{axiom_export, axiom_opaque, AxFn2, AxFn3};

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

/// Callbacks: bound under their arrow types and passed straight through.
#[axiom_export]
pub fn map_twice(f: axiom_ffi::AxFn1, x: i64) -> i64 {
    f.call(f.call(x))
}

#[axiom_export]
pub fn combine(f: AxFn2, g: AxFn3, seed: i64) -> Option<i64> {
    Some(g.call(f.call(seed, 1), 2, 3))
}

/// A `Vec<i64>` return: `ffiWordsToVec` then `ffiFreeWords`.
#[axiom_export]
pub fn evens(upto: i64) -> Vec<i64> {
    (0..upto).filter(|n| n % 2 == 0).collect()
}

/// A `Vec<String>` return: `ffiStrsToVec` then `ffiFreeStrList`.
#[axiom_export]
pub fn pieces(text: &str) -> Vec<String> {
    text.split(',').map(String::from).collect()
}

/// A `&[i64]` parameter: an Axiom `Vec` handle, typed `Int`.
#[axiom_export]
pub fn total(xs: &[i64]) -> i64 {
    xs.iter().sum()
}

/// The collections inside `Result` and `Option`.
#[axiom_export]
pub fn try_evens(upto: i64) -> Result<Vec<i64>, String> {
    if upto < 0 { Err("negative".into()) } else { Ok(evens(upto)) }
}

#[axiom_export]
pub fn maybe_pieces(text: &str) -> Option<Vec<String>> {
    if text.is_empty() { None } else { Some(pieces(text)) }
}

/// A record: `(pub data Pixel (Pixel Int Float Bool))`, a parameter
/// destructured into one raw argument per field, a result rebuilt
/// from an `ffiCellNewN 3` cell. Declared AFTER its first use, which
/// the two-pass walk does not mind.
#[axiom_export]
pub fn pixel_brightness(p: Pixel, gain: f64) -> f64 {
    if p.on { p.level as f64 * gain } else { 0.0 }
}

#[axiom_ffi::axiom_record]
pub struct Pixel {
    pub level: i32,
    pub weight: f32,
    pub on: bool,
}

#[axiom_export]
pub fn pixel_off() -> Pixel {
    Pixel { level: 0, weight: 0.0, on: false }
}

#[axiom_export]
pub fn pixel_mix(a: Pixel, b: Pixel, t: &Thing) -> Option<Pixel> {
    Some(Pixel { level: a.level + b.level + t.n as i32, weight: a.weight, on: a.on || b.on })
}

#[axiom_export]
pub fn pixel_parse(text: &str) -> Result<Pixel, String> {
    text.parse::<i32>().map(|level| Pixel { level, weight: 1.0, on: true }).map_err(|e| e.to_string())
}

/// Slices and vectors over the other word scalars, and a slice of
/// strings: `Int` on the Axiom side, with the element note.
#[axiom_export]
pub fn mean(xs: &[f64], weights: &[u16]) -> f64 {
    xs.iter().sum::<f64>() / weights.len() as f64
}

#[axiom_export]
pub fn parity(n: i64) -> Vec<bool> {
    (0..n).map(|i| i % 2 == 0).collect()
}

#[axiom_export]
pub fn concat(parts: &[&str]) -> String {
    parts.concat()
}

/// `char` and `u64` as words: `Char` on the raw item, `Int` for the
/// bits; a `Vec<char>` result and a `&[char]` parameter are the words
/// path with an element note; a `Char` payload is cast.
#[axiom_export]
pub fn next_char(c: char) -> char {
    char::from_u32(c as u32 + 1).unwrap_or(c)
}

#[axiom_export]
pub fn wrap_u64(x: u64) -> u64 {
    x.wrapping_add(1)
}

#[axiom_export]
pub fn chars_of(text: &str) -> Vec<char> {
    text.chars().collect()
}

#[axiom_export]
pub fn from_chars(cs: &[char]) -> String {
    cs.iter().collect()
}

#[axiom_export]
pub fn maybe_char(c: char) -> Option<char> {
    (c != 'x').then_some(c)
}

/// A record with a `char` and a `u64` field: `Char` and `Int`.
#[axiom_ffi::axiom_record]
pub struct Glyph {
    pub c: char,
    pub code: u64,
}

#[axiom_export]
pub fn glyph_of(c: char) -> Glyph {
    Glyph { c, code: c as u64 }
}

/// Records in Vecs: `__pixelFromWords` / `__pixelToWords` loops, a
/// flattened argument, `(ffiFreeWords __p (* __n 3))`.
#[axiom_export]
pub fn pixels_dim(ps: &[Pixel], by: i32) -> Vec<Pixel> {
    ps.iter().map(|p| Pixel { level: p.level - by, weight: p.weight, on: p.on }).collect()
}

#[axiom_export]
pub fn pixels_try(ps: &[Pixel]) -> Result<Vec<Pixel>, String> {
    if ps.is_empty() { Err("none".into()) } else { Ok(pixels_dim(ps, 0)) }
}

#[axiom_export]
pub fn glyphs_maybe(n: i64) -> Option<Vec<Glyph>> {
    (n > 0).then(|| vec![Glyph { c: 'a', code: n as u64 }])
}

/// Nested Vecs: `ffiWordListsToVec` / `ffiFreeWordLists`, a `Vec` of
/// `Vec` handles in.
#[axiom_export]
pub fn grid(n: i64) -> Vec<Vec<i64>> {
    (0..n).map(|r| (0..n).map(|c| r * n + c).collect()).collect()
}

#[axiom_export]
pub fn sum_rows(rows: &[&[i64]]) -> i64 {
    rows.iter().map(|r| r.iter().sum::<i64>()).sum()
}

#[axiom_export]
pub fn try_grid_f64(n: i64) -> Result<Vec<Vec<f64>>, String> {
    if n < 0 { Err("negative".into()) } else { Ok(vec![vec![0.5; n as usize]]) }
}

/// A mutable slice: the `Vec` handle, written in place, bound raw.
#[axiom_export]
pub fn double_in_place(xs: &mut [i64]) -> i64 {
    for x in xs.iter_mut() {
        *x *= 2;
    }
    xs.len() as i64
}

/// Nested fallible results: the constructors nest over three statuses.
#[axiom_export]
pub fn maybe_parse(text: &str) -> Result<Option<i64>, String> {
    if text.is_empty() { Ok(None) } else { text.parse().map(Some).map_err(|e: std::num::ParseIntError| e.to_string()) }
}

#[axiom_export]
pub fn lookup(i: i64) -> Option<Result<Thing, String>> {
    match i { 0 => None, i if i > 0 => Some(Ok(Thing { n: i })), _ => Some(Err("neg".into())) }
}

#[axiom_export]
pub fn maybe_pixel_try(n: i64) -> Result<Option<Pixel>, String> {
    match n { 0 => Ok(None), n if n > 0 => Ok(Some(pixel_off())), _ => Err("neg".into()) }
}

#[axiom_export]
pub fn pieces_lookup(text: &str) -> Option<Result<Vec<String>, String>> {
    if text.is_empty() { None } else { Some(Ok(pieces(text))) }
}

/// Not `pub`: the macro would refuse it, and bindgen skips it.
#[axiom_export]
fn hidden(n: i64) -> i64 {
    n
}

/// A hand-written shim, bound raw: `AxWord` is `Foreign`, `i64` is `Int`.
#[unsafe(no_mangle)]
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
