//! Every shape the boundary supports, in one crate.

use axiom_ffi::{axiom_export, axiom_opaque, axiom_record, AxFn1, AxFn2};
use core::sync::atomic::{AtomicI64, Ordering};

// 1. A scalar. This is the cheapest possible crossing: the generated
//    shim is `extern "C" fn axffi_add(i64, i64) -> i64`, and the Axiom
//    call site emits the same `call i64 @...` it would for an Axiom
//    function. There is no trampoline and nothing to marshal.
#[axiom_export]
pub fn add(a: i64, b: i64) -> i64 {
    a.wrapping_add(b)
}

// 2. A float. Axiom carries a Float as its IEEE-754 bits in an i64
//    (codegen.ax:4793-4801), so the shim does `f64::from_bits` in and
//    `to_bits` out. Both are free at runtime.
#[axiom_export]
pub fn hypot(x: f64, y: f64) -> f64 {
    (x * x + y * y).sqrt()
}

// 3. A borrowed string in. Zero-copy: `AxStr` reads the `{len, ptr,
//    owner}` run Axiom already holds. The `&str` is valid only for the
//    call, which is the whole reason it is a borrow.
#[axiom_export]
pub fn count_vowels(text: &str) -> i64 {
    text.chars().filter(|c| "aeiouAEIOU".contains(*c)).count() as i64
}

// 4. An owned string out. This needs two words (pointer and length) and
//    Axiom emits `ret i64` for everything, so the shim takes an out-cell
//    the Axiom glue allocated.
#[axiom_export]
pub fn shout(text: &str) -> String {
    let mut s = text.to_uppercase();
    s.push('!');
    s
}

// 5. Fallible. `Err` becomes a status word plus a message in the
//    out-cell; the Axiom glue turns it into a `(Result Int String)`.
#[axiom_export]
pub fn parse_int(text: &str) -> Result<i64, std::num::ParseIntError> {
    text.trim().parse::<i64>()
}

// 6. An opaque handle. `Counter` is never described to Axiom; Axiom
//    holds one word and passes it back. This is the mechanism that makes
//    wrapping an arbitrary crate type possible.
//
//    `#[axiom_opaque]` generates the destructor pair `axffi_counter_drop`
//    (null-checked `Box::from_raw`) and `axffi_counter_drop_fn` (its
//    address). The generated Axiom module wraps every `Counter` word in
//    a `Handle` that carries that address, so the value is dropped when
//    the last reference dies - or earlier, on `counterClose`. A borrow
//    of a closed handle aborts with "`counter_value`: handle is closed"
//    instead of dereferencing null.
#[axiom_opaque]
pub struct Counter {
    n: i64,
}

/// How many `Counter`s have been dropped so far - the observable half
/// of the handle protocol. ARC runs `Drop` when the last Axiom share of
/// a handle goes, and a fixture that cannot see that happen cannot tell
/// "reclaimed" from "leaked". Relaxed atomics: MM-PAR-1, no threads.
static COUNTERS_DROPPED: AtomicI64 = AtomicI64::new(0);

impl Drop for Counter {
    fn drop(&mut self) {
        COUNTERS_DROPPED.fetch_add(1, Ordering::Relaxed);
    }
}

#[axiom_export]
pub fn counters_dropped() -> i64 {
    COUNTERS_DROPPED.load(Ordering::Relaxed)
}

#[axiom_export]
pub fn counter_new(start: i64) -> Counter {
    Counter { n: start }
}

#[axiom_export]
pub fn counter_value(c: &Counter) -> i64 {
    c.n
}

#[axiom_export]
pub fn counter_add(c: &mut Counter, by: i64) -> i64 {
    c.n = c.n.wrapping_add(by);
    c.n
}

/// A fallible constructor: the handle travels through the out-cell on
/// `Ok`, the message on `Err`. Axiom sees `(Result Counter String)`.
#[axiom_export]
pub fn counter_try_new(start: i64) -> Result<Counter, String> {
    if start < 0 {
        Err(format!("counter cannot start below zero (got {start})"))
    } else {
        Ok(Counter { n: start })
    }
}

// 6b. `Option`. Status 2 is `None`; the wrapper answers `(Option Int)`.
#[axiom_export]
pub fn maybe(n: i64) -> Option<i64> {
    if n >= 0 {
        Some(n)
    } else {
        None
    }
}

// 6c. Narrow integers are range-checked on the way in (an out-of-range
//     word aborts with the function and argument named) and widened
//     losslessly on the way out.
#[axiom_export]
pub fn halve(n: i32) -> i32 {
    n / 2
}

#[axiom_export]
pub fn byte_plus(b: u8, delta: i64) -> i64 {
    b as i64 + delta
}

// 6d. A borrowed byte slice: no UTF-8 validation, any bytes go.
#[axiom_export]
pub fn byte_len(data: &[u8]) -> i64 {
    data.len() as i64
}

// 6e. A parameter named `cell`. The generated wrapper's own locals are
//     `__`-prefixed, so this reaches the Rust side intact rather than
//     being shadowed by the wrapper's out-cell.
#[axiom_export]
pub fn cell_twice(cell: i64) -> i64 {
    cell.wrapping_mul(2)
}

// 6f. Callbacks: Axiom -> Rust -> Axiom. An `AxFn1` is the closure
//     record word Axiom passes for a `(-> Int Int)` argument - a lambda
//     or a bare top-level function, which the compiler wraps in a
//     forwarding thunk record. `call` loads the code address from word
//     0 and calls it with the record as the hidden environment. The
//     record is borrowed for the call; a shim that wanted to keep it
//     would `axiom_retain` it.
#[axiom_export]
pub fn apply_twice(f: AxFn1, x: i64) -> i64 {
    f.call(f.call(x))
}

/// `f(f(a, b), c)`: a two-argument callback.
#[axiom_export]
pub fn fold3(f: AxFn2, a: i64, b: i64, c: i64) -> i64 {
    f.call(f.call(a, b), c)
}

// 6g. Vectors. A `Vec<i64>` return rides the out-cell as `(ptr, len)`
//     of words; the wrapper pushes each into an Axiom `Vec` and frees
//     the Rust side with `axffi_free_words`. A `Vec<String>` return is
//     `(pairs, n)`: `2n` words of `(bytesPtr, byteLen)`, each copied
//     into an Axiom String, then `axffi_free_str_list`. A `&[i64]`
//     parameter reads an Axiom `Vec` handle in place - len at word 0,
//     data at word 2 - for the call.
#[axiom_export]
pub fn range_vec(n: i64) -> Vec<i64> {
    (0..n.max(0)).collect()
}

#[axiom_export]
pub fn split_words(text: &str) -> Vec<String> {
    text.split_whitespace().map(str::to_string).collect()
}

#[axiom_export]
pub fn sum_words(xs: &[i64]) -> i64 {
    xs.iter().fold(0i64, |acc, x| acc.wrapping_add(*x))
}

// 6h. Vectors over every word scalar. A `Vec<T>` result is widened
//     into the same `(ptr, len)` of words as a `Vec<i64>` - an f64 as
//     its bits, an f32 as f64 bits, a bool as 0/1, a u8 as the word -
//     so the Axiom wrapper is unchanged and the element type is
//     whatever the program reads: `(cast Float (vecGet v i))` for
//     `halves`, `(vecGet v i)` for `flags`. A `&[T]` parameter reads
//     the Axiom `Vec` the other way: `&[f64]` reinterprets the words
//     in place (same size, same alignment, every bit pattern a float),
//     every other narrow scalar is converted into a temporary with
//     each word range-checked (out of range aborts, as a scalar
//     argument would).
//
//     `u8` is the one exception, on both sides: `&[u8]` is the byte
//     view of an Axiom String (6d) and `Vec<u8>` answers a String (4),
//     which is what they always were - so `sum_u8` takes a String and
//     `bytes_of` answers one; `sum_u16` is the range-checked Vec path.
#[axiom_export]
pub fn sum_f64(xs: &[f64]) -> f64 {
    xs.iter().sum()
}

#[axiom_export]
pub fn sum_u8(xs: &[u8]) -> i64 {
    xs.iter().map(|b| *b as i64).sum()
}

#[axiom_export]
pub fn sum_u16(xs: &[u16]) -> i64 {
    xs.iter().map(|b| *b as i64).sum()
}

#[axiom_export]
pub fn halves(n: i64) -> Vec<f64> {
    (0..n.max(0)).map(|i| i as f64 / 2.0).collect()
}

#[axiom_export]
pub fn flags(n: i64) -> Vec<bool> {
    (0..n.max(0)).map(|i| i % 2 == 0).collect()
}

#[axiom_export]
pub fn bytes_of(s: &str) -> Vec<u8> {
    s.as_bytes().to_vec()
}

// 6i. A `&[&str]` parameter: an Axiom `Vec` of Strings, each word a
//     String handle the shim borrows as `&str` for the call. Invalid
//     UTF-8 in any element aborts, as a `&str` argument would (or is
//     `Err` from a `Result` function; `utf8 = "lossy"` converts).
#[axiom_export]
pub fn join_words(parts: &[&str]) -> String {
    parts.join(" ")
}

// 6j. A record: a struct that crosses AS ITS FIELDS. `Point` is never
//     boxed - a parameter arrives as one shim word per field
//     (`axffi_point_norm2(x, y_bits)`), a result is written into an
//     out-cell of one word per field (`ffiCellNewN 2`), and the Axiom
//     side is `(pub data Point (Point Int Float))`, destructured and
//     rebuilt by the generated wrapper. `Result<Point, _>` and
//     `Option<Point>` carry the fields the same way behind the status
//     word.
#[axiom_record]
#[derive(Clone)]
pub struct Point {
    pub x: i64,
    pub y: f64,
}

#[axiom_export]
pub fn point_norm2(p: Point) -> f64 {
    (p.x as f64) * (p.x as f64) + p.y * p.y
}

#[axiom_export]
pub fn point_origin() -> Point {
    Point { x: 0, y: 0.0 }
}

#[axiom_export]
pub fn point_scale(p: Point, k: i64) -> Point {
    Point { x: p.x.wrapping_mul(k), y: p.y * k as f64 }
}

#[axiom_export]
pub fn point_try(ok: bool) -> Result<Point, String> {
    if ok {
        Ok(Point { x: 3, y: 4.0 })
    } else {
        Err("no point".to_string())
    }
}

#[axiom_export]
pub fn point_maybe(ok: bool) -> Option<Point> {
    if ok {
        Some(Point { x: -1, y: 0.5 })
    } else {
        None
    }
}

// 6k. `char` is Axiom `Char`: the code point in the word, both ways.
//     Rust -> Axiom is `c as i64`; Axiom -> Rust is `char::from_u32`,
//     and a word that is not a Unicode scalar value (`(cast Char
//     1114112)`, a surrogate, a negative word) aborts with the
//     argument named, as a narrow integer out of range does. The same
//     rule covers a record field, a `Vec<char>` element and a `&[char]`
//     element.
#[axiom_export]
pub fn next_char(c: char) -> char {
    char::from_u32(c as u32 + 1).unwrap_or(c)
}

#[axiom_export]
pub fn char_code(c: char) -> i64 {
    c as i64
}

#[axiom_export]
pub fn chars_of(s: &str) -> Vec<char> {
    s.chars().collect()
}

#[axiom_export]
pub fn from_chars(cs: &[char]) -> String {
    cs.iter().collect()
}

// 6l. `u64` is the word's bits read unsigned, with no range check in
//     either direction: nothing is lost, and the Axiom side sees a
//     value >= 2^63 as a negative `Int`. `wrap_u64(u64::MAX)` is
//     `(wrapU64 -1)` from Axiom, and answers 0.
#[axiom_export]
pub fn wrap_u64(x: u64) -> u64 {
    x.wrapping_add(1)
}

// 6m. Records in Vecs. A `Vec<Point>` result is `n * ARITY` words
//     (element-major, field order) behind a `(ptr, n)` cell, freed as
//     that many words; the generated module rebuilds each `Point` with
//     `ffiWordAt` in its own `__pointFromWords` loop. A `&[Point]`
//     parameter is flattened on the Axiom side (`__pointToWords`) into
//     a words `Vec` the shim chunks back through `from_words`.
#[axiom_export]
pub fn points_scale(ps: &[Point], k: i64) -> Vec<Point> {
    ps.iter().map(|p| Point { x: p.x.wrapping_mul(k), y: p.y * k as f64 }).collect()
}

#[axiom_export]
pub fn points_try(ps: &[Point]) -> Result<Vec<Point>, String> {
    if ps.is_empty() {
        Err("no points".to_string())
    } else {
        Ok(ps.iter().rev().cloned().collect())
    }
}

// 6n. Nested Vecs over word scalars. A `Vec<Vec<i64>>` result is
//     `(pairs, n)`: `2n` words of `(wordsPtr, len)`, one owned buffer
//     per row, built into a `Vec` of `Vec`s by `ffiWordListsToVec` and
//     freed by `axffi_free_word_lists`. A `&[&[i64]]` parameter is a
//     `Vec` of `Vec` handles, each row borrowed in place.
#[axiom_export]
pub fn grid(n: i64) -> Vec<Vec<i64>> {
    (0..n.max(0)).map(|r| (0..n).map(|c| r * n + c).collect()).collect()
}

#[axiom_export]
pub fn sum_rows(rows: &[&[i64]]) -> i64 {
    rows.iter().map(|r| r.iter().sum::<i64>()).sum()
}

// 6o. A mutable slice: `&mut [i64]` is the Axiom `Vec`'s live
//     elements, written in place - the caller reads the doubled values
//     back from the same `Vec`. `&mut [f64]` and `&mut [u64]` are the
//     same words under another name; any other element type would need
//     a converted copy that could not be written back, so it is refused.
#[axiom_export]
pub fn double_in_place(xs: &mut [i64]) -> i64 {
    for x in xs.iter_mut() {
        *x = x.wrapping_mul(2);
    }
    xs.len() as i64
}

// 6p. Nested fallible results over the same three statuses.
//     `Result<Option<i64>, String>`: 0 = `(Ok (Some v))`, 2 =
//     `(Ok None)`, 1 = `(Err m)`; `Option<Result<i64, String>>`: 0 =
//     `(Some (Ok v))`, 1 = `(Some (Err m))`, 2 = `None`.
#[axiom_export]
pub fn maybe_parse(s: &str) -> Result<Option<i64>, String> {
    let s = s.trim();
    if s.is_empty() {
        return Ok(None);
    }
    s.parse::<i64>().map(Some).map_err(|e| e.to_string())
}

#[axiom_export]
pub fn lookup(i: i64) -> Option<Result<i64, String>> {
    match i {
        0 => None,
        i if i > 0 => Some(Ok(i * 10)),
        i => Some(Err(format!("negative index {i}"))),
    }
}

// 7. Arity edges. A ZERO-argument extern is the one shape with a
//    distinct codegen path: `emitPlainCall` has no empty-args branch
//    and would emit the invalid `@f(i64 )`, so a nullary reference must
//    go down the `@f()` path instead. Unreachable for ordinary Axiom
//    functions (the AST's application node always carries one
//    argument), and reachable here.
#[axiom_export]
pub fn abi_probe() -> i64 {
    0x5A15
}

#[axiom_export]
pub fn sum3(a: i64, b: i64, c: i64) -> i64 {
    a.wrapping_add(b).wrapping_add(c)
}

#[axiom_export]
pub fn sum5(a: i64, b: i64, c: i64, d: i64, e: i64) -> i64 {
    a.wrapping_add(b).wrapping_add(c).wrapping_add(d).wrapping_add(e)
}

// 8. The retain/release protocol.
//
// Rust may not keep an Axiom heap value beyond the shim that received
// it: the borrow is the call, ARC may release the block the moment it
// returns, and an arena reset may reclaim it wholesale. A shim that
// wants to keep one takes a share with `axiom_retain` and pairs it with
// `axiom_release` — both have external linkage in every emitted module.
//
// The slot is an `AtomicI64` and NOT for thread-safety: MM-PAR-1 says
// Axiom has no threads at all, and all allocator state is
// process-private (invariant I11), so a plain global would be sound.
// It is atomic because `static mut` is being removed from Rust, and a
// Relaxed load on a word costs nothing.
static KEPT: AtomicI64 = AtomicI64::new(0);

/// Retain an Axiom value and stash it. Answers its byte length, so the
/// caller has something to compare against later.
///
/// # Safety
/// `s` must be a live Axiom `String` word.
#[no_mangle]
pub unsafe extern "C" fn axffi_str_keep(s: axiom_ffi::AxWord) -> i64 {
    axiom_ffi::axiom_retain(s);
    KEPT.store(s, Ordering::Relaxed);
    axiom_ffi::AxStr::from_raw(s).len() as i64
}

/// Read the stashed value back. Answers -1 when nothing is held.
///
/// This is the call that would read freed memory without the retain
/// above, which is why the fixture compares its answer rather than
/// merely checking that it returned.
///
/// # Safety
/// Valid only between a `keep` and its paired `drop`.
#[no_mangle]
pub unsafe extern "C" fn axffi_str_recall() -> i64 {
    let w = KEPT.load(Ordering::Relaxed);
    if w == 0 {
        return -1;
    }
    axiom_ffi::AxStr::from_raw(w).len() as i64
}

/// Release the share taken by `keep`. Pairs 1:1 with it.
///
/// # Safety
/// Must not be called twice for one `keep`.
#[no_mangle]
pub unsafe extern "C" fn axffi_str_drop() -> i64 {
    let w = KEPT.swap(0, Ordering::Relaxed);
    if w != 0 {
        axiom_ffi::axiom_release(w);
    }
    0
}
