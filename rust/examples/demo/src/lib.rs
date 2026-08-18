//! Every shape the boundary supports, in one crate.

use axiom_ffi::axiom_export;

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
pub struct Counter {
    n: i64,
}

#[axiom_export]
pub fn counter_new(start: i64) -> Counter {
    Counter { n: start }
}

#[axiom_export]
pub fn counter_value(c: &Counter) -> i64 {
    c.n
}

/// The destructor. Axiom is ARC with no finalizers, so this runs when
/// the program says so — there is no point at which the runtime could
/// call it for you.
///
/// # Safety
/// `h` must be a handle from `counter_new` that has not been closed.
#[no_mangle]
pub unsafe extern "C" fn axffi_counter_close(h: axiom_ffi::AxWord) {
    if h != 0 {
        drop(Box::from_raw(h as *mut Counter));
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
