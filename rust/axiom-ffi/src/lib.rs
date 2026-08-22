//! Write Rust that Axiom can call.
//!
//! ```ignore
//! use axiom_ffi::{axiom_export, axiom_opaque};
//!
//! #[axiom_export]
//! pub fn sha256_hex(input: &str) -> String {
//!     use sha2::{Digest, Sha256};
//!     let d = Sha256::digest(input.as_bytes());
//!     d.iter().map(|b| format!("{b:02x}")).collect()
//! }
//!
//! #[axiom_opaque]
//! pub struct Hasher(sha2::Sha256);
//!
//! #[axiom_export]
//! pub fn hasher_new() -> Hasher { Hasher(Default::default()) }
//! ```
//!
//! `#[axiom_export]` generates `axffi_sha256_hex`, a `#[no_mangle]
//! extern "C"` shim whose signature is all `i64`; `axiom-bindgen` reads
//! the same annotations and writes the Axiom module that binds it:
//!
//! ```text
//! (pub extern "axiom_demo"
//!   (sha256HexRaw :: (-> String Int Int) (symbol "axffi_sha256_hex")))
//! (pub :: sha256Hex (-> String String))
//! ```
//!
//! `#[axiom_opaque]` marks a type Axiom holds as a handle and generates
//! its destructor (`axffi_hasher_drop`) plus `axffi_hasher_drop_fn`,
//! which hands Axiom the destructor's address so the handle releases the
//! value when its count reaches zero. `#[axiom_record]` marks a struct
//! of word scalars that crosses AS ITS FIELDS instead - one shim word
//! per field, an Axiom `data` with one positional field each - and
//! derives [`AxRecord`] for it.
//!
//! # The two build modes, measured
//!
//! | mode | `nm -u` on the linked Axiom executable | freestanding |
//! |---|---|---|
//! | `no_std` + `panic = "abort"` | **empty** | preserved |
//! | `std` | 188 symbols, 18 forbidden | relaxed, gated by allowlist |
//!
//! Both link and both run. The difference is only whether
//! `scripts/check-freestanding.sh`'s blanket ban still applies or the
//! MM-FFI-5 allowlist gate takes over.
//!
//! A `no_std` crate depends on this one with `default-features = false,
//! features = ["nostd-runtime"]` and needs nothing else: the feature
//! supplies the global allocator over `axiom_alloc`, the panic handler,
//! the personality stub and the memory intrinsics the precompiled
//! `alloc` rlib references. See the `nostd_runtime` module.
//!
//! # Panics and aborts
//!
//! `extern "C"` aborts on unwind (Rust 1.81+), and Axiom has no
//! unwinding at all — its emitter never writes an `invoke` or a
//! `landingpad`. So a panic that reaches the boundary ends the process.
//! Set `panic = "abort"` to make that explicit and to drop the landing
//! pads from the archive. The generated shims also abort deliberately,
//! with a message on fd 2 and exit status 72 (the status Axiom's own
//! runtime traps use), when an argument cannot be honoured: a narrow
//! integer out of range, a `char` word that is not a Unicode scalar
//! value, invalid UTF-8 into an infallible `&str`, a closed handle.
//! Axiom has no way to receive an error from an infallible call, so
//! the alternative would be a silent wrong answer.

#![cfg_attr(not(feature = "std"), no_std)]

#[cfg(all(feature = "std", feature = "nostd-runtime"))]
compile_error!(
    "axiom-ffi: the `nostd-runtime` feature replaces std's allocator and panic \
     handler; use it with `default-features = false`"
);

extern crate alloc;

pub use axiom_abi::{
    axiom_alloc, axiom_release, axiom_retain, AxCallback, AxFn1, AxFn2, AxFn3, AxOutCell,
    AxRecord, AxStatus, AxStr, AxStrRepr, AxVec, AxVecRepr, AxWord, AX_ERR, AX_NONE, AX_OK,
};
pub use axiom_ffi_macros::{axiom_export, axiom_opaque, axiom_record};
#[doc(hidden)]
pub use axiom_ffi_macros::__axiom_export_resolved;

#[cfg(feature = "nostd-runtime")]
pub mod nostd_runtime;

#[cfg(feature = "host")]
pub mod host;

/// A type Axiom holds as an opaque handle. Implemented by
/// `#[axiom_opaque]`, never by hand.
///
/// The bound is what makes "an opaque return needs `#[axiom_opaque]`"
/// a compile error rather than a leak: the shim for a function that
/// returns or borrows `T` calls into [`__private`] helpers that require
/// it, so a type that was never marked has no drop function and is
/// refused with the message below.
#[diagnostic::on_unimplemented(
    message = "`{Self}` crosses the Axiom boundary as an opaque handle but is not marked `#[axiom_opaque]`",
    label = "this type needs `#[axiom_opaque]`",
    note = "put `#[axiom_opaque]` on the declaration of `{Self}`: it generates the destructor Axiom's handle calls when the last reference dies"
)]
pub trait AxiomOpaque: Sized {
    /// The symbol stem: `axffi_<STEM>_drop` is the destructor.
    const STEM: &'static str;
    /// The destructor itself.
    const DROP: unsafe extern "C" fn(AxWord) -> AxWord;
}

/// A type that may be named bare in an exported signature: marked
/// `#[axiom_opaque]` (Axiom holds a handle) or `#[axiom_record]` (it
/// crosses as its fields). Implemented by the two attributes, never by
/// hand.
///
/// A shim that hands back or takes such a type by value learns WHICH
/// of the two it is from the type's companion macro (see
/// `axiom_ffi_classify::companion_module`); this bound is asserted
/// beside that expansion so an unmarked type is reported as the
/// missing attribute rather than only as an unresolved macro.
#[diagnostic::on_unimplemented(
    message = "`{Self}` crosses the Axiom boundary but is not marked `#[axiom_opaque]` or `#[axiom_record]`",
    label = "this type needs `#[axiom_opaque]` or `#[axiom_record]`",
    note = "put `#[axiom_opaque]` on the declaration of `{Self}` for Axiom to hold it as a handle (its destructor runs when the last reference dies), or `#[axiom_record]` for it to cross as its word-scalar fields"
)]
pub trait AxiomMarked: Sized {}

/// Implementation details the generated shims call. Not a stable API.
#[doc(hidden)]
pub mod __private {
    use super::{AxCallback, AxOutCell, AxRecord, AxStr, AxVec, AxWord, AxiomOpaque, AX_ERR};
    use alloc::boxed::Box;
    use alloc::string::String;
    use core::fmt::Arguments;

    /// `alloc::vec::Vec`, for a generated shim in a `no_std` crate.
    pub use alloc::vec::Vec;

    /// A scalar that is one word on the wire: the conversions the
    /// `Vec<T>` / `&[T]` shapes and record fields use. `to_word` never
    /// fails; `from_word` answers `None` for a word that holds no value
    /// of the type (a narrow integer out of range, a bool not 0 or 1,
    /// a char that is not a Unicode scalar value).
    pub trait WordScalar: Copy {
        const NAME: &'static str;
        /// How a word that holds no value is described: out of range
        /// for an integer, not 0 or 1 for a bool.
        const REFUSAL: &'static str = "is out of range";
        fn to_word(self) -> AxWord;
        fn from_word(w: AxWord) -> Option<Self>;
    }

    macro_rules! int_scalar {
        ($($t:ident),*) => {$(
            impl WordScalar for $t {
                const NAME: &'static str = stringify!($t);
                #[inline]
                fn to_word(self) -> AxWord {
                    self as AxWord
                }
                #[inline]
                fn from_word(w: AxWord) -> Option<Self> {
                    <$t>::try_from(w).ok()
                }
            }
        )*};
    }
    int_scalar!(i64, i32, i16, i8, u32, u16, u8, usize, isize);

    /// The word's 64 bits read unsigned: no range check either way,
    /// because nothing is lost (Axiom sees a value >= 2^63 as negative).
    impl WordScalar for u64 {
        const NAME: &'static str = "u64";
        #[inline]
        fn to_word(self) -> AxWord {
            self as AxWord
        }
        #[inline]
        fn from_word(w: AxWord) -> Option<Self> {
            Some(w as u64)
        }
    }

    /// The code point in the word. A word that is not a Unicode scalar
    /// value - above `0x10FFFF`, a surrogate, negative - holds no `char`.
    impl WordScalar for char {
        const NAME: &'static str = "char";
        const REFUSAL: &'static str = "is not a Unicode scalar value";
        #[inline]
        fn to_word(self) -> AxWord {
            self as AxWord
        }
        #[inline]
        fn from_word(w: AxWord) -> Option<Self> {
            u32::try_from(w).ok().and_then(char::from_u32)
        }
    }

    impl WordScalar for bool {
        const NAME: &'static str = "bool";
        const REFUSAL: &'static str = "is not 0 or 1";
        #[inline]
        fn to_word(self) -> AxWord {
            self as AxWord
        }
        #[inline]
        fn from_word(w: AxWord) -> Option<Self> {
            match w {
                0 => Some(false),
                1 => Some(true),
                _ => None,
            }
        }
    }

    impl WordScalar for f64 {
        const NAME: &'static str = "f64";
        #[inline]
        fn to_word(self) -> AxWord {
            self.to_bits() as AxWord
        }
        #[inline]
        fn from_word(w: AxWord) -> Option<Self> {
            Some(f64::from_bits(w as u64))
        }
    }

    impl WordScalar for f32 {
        const NAME: &'static str = "f32";
        #[inline]
        fn to_word(self) -> AxWord {
            (self as f64).to_bits() as AxWord
        }
        #[inline]
        fn from_word(w: AxWord) -> Option<Self> {
            Some(f64::from_bits(w as u64) as f32)
        }
    }

    /// End the process with a message: `axiom-ffi: <message>` on fd 2,
    /// exit status 72 like Axiom's own runtime traps.
    #[cold]
    pub fn abort(args: Arguments<'_>) -> ! {
        #[cfg(feature = "std")]
        {
            std::eprintln!("axiom-ffi: {args}");
            std::process::exit(72)
        }
        #[cfg(all(not(feature = "std"), feature = "nostd-runtime"))]
        {
            let msg = alloc::format!("axiom-ffi: {args}\n");
            super::nostd_runtime::write_stderr(msg.as_bytes());
            super::nostd_runtime::exit(72)
        }
        #[cfg(all(not(feature = "std"), not(feature = "nostd-runtime")))]
        {
            panic!("axiom-ffi: {args}")
        }
    }

    /// Hand owned bytes to Axiom as a `(ptr, len)` pair.
    ///
    /// Axiom's generated glue copies them into a real `strAlloc` block
    /// and then calls [`axffi_free_bytes`](super::axffi_free_bytes).
    /// Rust keeps ownership until that free, which is why this leaks
    /// deliberately rather than returning a borrow of a temporary.
    pub fn leak_bytes(v: Vec<u8>) -> (AxWord, AxWord) {
        let boxed: Box<[u8]> = v.into_boxed_slice();
        let len = boxed.len() as AxWord;
        let p = Box::into_raw(boxed) as *mut u8;
        (p as AxWord, len)
    }

    /// Render an error into owned bytes for the out-cell.
    pub fn error_bytes<E: core::fmt::Display>(e: &E) -> (AxWord, AxWord) {
        use alloc::string::ToString;
        leak_bytes(e.to_string().into_bytes())
    }

    /// Hand owned words to Axiom as a `(ptr, len)` pair. Axiom's glue
    /// pushes each into a `Vec` and calls
    /// [`axffi_free_words`](super::axffi_free_words).
    pub fn leak_words(v: Vec<i64>) -> (AxWord, AxWord) {
        let boxed: Box<[i64]> = v.into_boxed_slice();
        let len = boxed.len() as AxWord;
        let p = Box::into_raw(boxed) as *mut i64;
        (p as AxWord, len)
    }

    /// Hand owned strings to Axiom as `(ptr, n)`: `ptr` holds `2n`
    /// words, a `(bytesPtr, byteLen)` pair per string, each pair what
    /// [`leak_bytes`] answers. Axiom's glue copies every string and
    /// calls [`axffi_free_str_list`](super::axffi_free_str_list),
    /// which frees the strings and then the pair buffer.
    pub fn leak_strs(v: Vec<String>) -> (AxWord, AxWord) {
        let n = v.len() as AxWord;
        let mut pairs: Vec<i64> = Vec::with_capacity(v.len() * 2);
        for s in v {
            let (p, len) = leak_bytes(s.into_bytes());
            pairs.push(p);
            pairs.push(len);
        }
        let (p, _) = leak_words(pairs);
        (p, n)
    }

    /// Move an opaque value onto the heap and hand Axiom its address.
    pub fn leak_opaque<T: AxiomOpaque>(v: T) -> AxWord {
        Box::into_raw(Box::new(v)) as AxWord
    }

    /// The destructor body `#[axiom_opaque]` generates: a null-checked
    /// `Box::from_raw`. Answers 0 because every Axiom call reads a word.
    ///
    /// # Safety
    /// `word` is 0 or an address from [`leak_opaque`] not yet dropped.
    pub unsafe fn drop_opaque<T: AxiomOpaque>(word: AxWord) -> AxWord {
        if word != 0 {
            drop(Box::from_raw(word as *mut T));
        }
        0
    }

    /// Borrow an opaque value for the duration of a call.
    ///
    /// A 0 word is a handle Axiom has already closed (or a null a
    /// fallible constructor never filled); dereferencing it would be
    /// the silent-crash case, so it aborts with the function's name.
    ///
    /// # Safety
    /// `word` is 0 or an address from [`leak_opaque`] not yet dropped.
    #[inline]
    pub unsafe fn borrow<'a, T: AxiomOpaque>(word: AxWord, func: &str) -> &'a T {
        if word == 0 {
            abort(format_args!("`{func}`: handle is closed"));
        }
        &*(word as *const T)
    }

    /// Borrow mutably. Axiom has no threads (MM-PAR-1), so the only way
    /// to alias is to pass the same handle twice in one call.
    ///
    /// # Safety
    /// As [`borrow`], and no other borrow of the value may be live.
    #[inline]
    pub unsafe fn borrow_mut<'a, T: AxiomOpaque>(word: AxWord, func: &str) -> &'a mut T {
        if word == 0 {
            abort(format_args!("`{func}`: handle is closed"));
        }
        &mut *(word as *mut T)
    }

    /// Check a scalar argument the word may not hold: a narrow integer
    /// (out of range) or a `char` (not a Unicode scalar value). A word
    /// that holds no value aborts: an infallible shim has no channel for
    /// an error, and truncation is the silent-wrong-answer case.
    #[inline]
    pub fn narrow<T: WordScalar>(word: AxWord, func: &str, idx: usize, name: &str) -> T {
        match T::from_word(word) {
            Some(v) => v,
            None => abort(format_args!(
                "`{func}`: argument {idx} (`{name}`: {}) {}: {word}",
                T::NAME,
                T::REFUSAL
            )),
        }
    }

    /// The UTF-8 failure message a fallible shim answers as `Err`.
    fn utf8_message(func: &str, idx: usize) -> String {
        alloc::format!("argument {idx} of `{func}` is not valid UTF-8")
    }

    /// A `&str` argument of an infallible shim: invalid UTF-8 aborts.
    ///
    /// # Safety
    /// `word` must be a live Axiom `String` for the call.
    #[inline]
    pub unsafe fn str_strict<'a>(word: AxWord, func: &str, idx: usize) -> &'a str {
        match AxStr::from_raw(word).as_str() {
            Ok(s) => s,
            Err(_) => abort(format_args!("{}", utf8_message(func, idx))),
        }
    }

    /// A `&str` argument of a fallible shim: invalid UTF-8 is `Err`.
    ///
    /// # Safety
    /// `word` must be a live Axiom `String` for the call.
    #[inline]
    pub unsafe fn str_fallible<'a>(word: AxWord, func: &str, idx: usize) -> Result<&'a str, String> {
        AxStr::from_raw(word)
            .as_str()
            .map_err(|_| utf8_message(func, idx))
    }

    /// A `&str` argument under `utf8 = "lossy"`.
    ///
    /// # Safety
    /// `word` must be a live Axiom `String` for the call.
    #[inline]
    pub unsafe fn str_lossy<'a>(word: AxWord) -> alloc::borrow::Cow<'a, str> {
        String::from_utf8_lossy(AxStr::from_raw(word).as_bytes())
    }

    /// A `&[u8]` argument.
    ///
    /// # Safety
    /// `word` must be a live Axiom `String` for the call.
    #[inline]
    pub unsafe fn bytes<'a>(word: AxWord) -> &'a [u8] {
        AxStr::from_raw(word).as_bytes()
    }

    /// A `&[i64]` argument: the live words of an Axiom `Vec`. A 0 word
    /// is no vector at all and aborts rather than reading address 0.
    ///
    /// # Safety
    /// `word` must be 0 or a live Axiom `Vec` handle for the call.
    #[inline]
    pub unsafe fn words<'a>(word: AxWord, func: &str, idx: usize, name: &str) -> &'a [i64] {
        if word == 0 {
            abort(format_args!("`{func}`: argument {idx} (`{name}`: &[i64]) is not a Vec: 0"));
        }
        AxVec::from_raw(word).as_slice()
    }

    /// A `&[f64]` argument: the live words of an Axiom `Vec`, read as
    /// the Float bits they hold. No copy: `i64` and `f64` have the same
    /// size and alignment (8 bytes on every target Axiom emits for),
    /// every bit pattern is a valid `f64`, and the view is borrowed for
    /// the call exactly as the `i64` view is.
    ///
    /// # Safety
    /// `word` must be 0 or a live Axiom `Vec` handle for the call.
    #[inline]
    pub unsafe fn words_f64<'a>(word: AxWord, func: &str, idx: usize, name: &str) -> &'a [f64] {
        if word == 0 {
            abort(format_args!("`{func}`: argument {idx} (`{name}`: &[f64]) is not a Vec: 0"));
        }
        let s = AxVec::from_raw(word).as_slice();
        // SAFETY: same size, same alignment, no invalid bit pattern;
        // the lifetime and length are the word slice's own.
        core::slice::from_raw_parts(s.as_ptr() as *const f64, s.len())
    }

    /// A `&[u64]` argument: the live words of an Axiom `Vec`, read as
    /// the unsigned bits they hold. No copy, as for [`words_f64`].
    ///
    /// # Safety
    /// `word` must be 0 or a live Axiom `Vec` handle for the call.
    #[inline]
    pub unsafe fn words_u64<'a>(word: AxWord, func: &str, idx: usize, name: &str) -> &'a [u64] {
        if word == 0 {
            abort(format_args!("`{func}`: argument {idx} (`{name}`: &[u64]) is not a Vec: 0"));
        }
        let s = AxVec::from_raw(word).as_slice();
        // SAFETY: same size, same alignment, every bit pattern a u64.
        core::slice::from_raw_parts(s.as_ptr() as *const u64, s.len())
    }

    /// A `&[T]` argument for any other word scalar: every word of the
    /// Axiom `Vec` converted into a temporary `Vec<T>`. A word that
    /// holds no `T` (a narrow integer out of range, a bool not 0 or 1,
    /// a char that is no Unicode scalar value) aborts with the element
    /// named, as a scalar argument would.
    ///
    /// # Safety
    /// `word` must be 0 or a live Axiom `Vec` handle for the call.
    pub unsafe fn words_as<T: WordScalar>(word: AxWord, func: &str, idx: usize, name: &str) -> Vec<T> {
        if word == 0 {
            abort(format_args!(
                "`{func}`: argument {idx} (`{name}`: &[{}]) is not a Vec: 0",
                T::NAME
            ));
        }
        convert_words(AxVec::from_raw(word).as_slice(), func, idx, name, T::NAME, None)
    }

    /// Convert `s` into a `Vec<T>`, aborting on a word that holds no
    /// `T`; `row` names the inner list of a nested argument.
    fn convert_words<T: WordScalar>(
        s: &[i64],
        func: &str,
        idx: usize,
        name: &str,
        shown: &str,
        row: Option<usize>,
    ) -> Vec<T> {
        let mut out = Vec::with_capacity(s.len());
        for (k, &w) in s.iter().enumerate() {
            match T::from_word(w) {
                Some(v) => out.push(v),
                None => match row {
                    None => abort(format_args!(
                        "`{func}`: argument {idx} (`{name}`: &[{shown}]) element {k} {}: {w}",
                        T::REFUSAL
                    )),
                    Some(r) => abort(format_args!(
                        "`{func}`: argument {idx} (`{name}`: &[&[{shown}]]) element {k} of \
                         list {r} {}: {w}",
                        T::REFUSAL
                    )),
                },
            }
        }
        out
    }

    /// Widen a `Vec<T>` of word scalars into the words Axiom reads
    /// (ints sign/zero-extended, bool 0/1, floats as f64 bits), for
    /// [`leak_words`].
    pub fn to_words<T: WordScalar>(v: Vec<T>) -> Vec<i64> {
        v.into_iter().map(T::to_word).collect()
    }

    /// A `&mut [i64]` argument: the live words of an Axiom `Vec`,
    /// written in place. What the call writes is what the Axiom caller
    /// reads back from the same `Vec`.
    ///
    /// # Safety
    /// `word` must be 0 or a live Axiom `Vec` handle for the call, and
    /// no other view of its words may be live (the same `Vec` passed
    /// twice in one call is the only way to alias).
    #[inline]
    pub unsafe fn words_mut<'a>(word: AxWord, func: &str, idx: usize, name: &str) -> &'a mut [i64] {
        if word == 0 {
            abort(format_args!("`{func}`: argument {idx} (`{name}`: &mut [i64]) is not a Vec: 0"));
        }
        AxVec::from_raw(word).as_mut_slice()
    }

    /// A `&mut [f64]` argument: the live words written in place as the
    /// floats their bits are (same size, same alignment, every bit
    /// pattern a float, and every float a word back).
    ///
    /// # Safety
    /// As [`words_mut`].
    #[inline]
    pub unsafe fn words_mut_f64<'a>(word: AxWord, func: &str, idx: usize, name: &str) -> &'a mut [f64] {
        if word == 0 {
            abort(format_args!("`{func}`: argument {idx} (`{name}`: &mut [f64]) is not a Vec: 0"));
        }
        let s = AxVec::from_raw(word).as_mut_slice();
        // SAFETY: same size, same alignment, no invalid bit pattern in
        // either direction; the lifetime and length are the word slice's.
        core::slice::from_raw_parts_mut(s.as_mut_ptr() as *mut f64, s.len())
    }

    /// A `&mut [u64]` argument: the live words written in place as
    /// their unsigned bits.
    ///
    /// # Safety
    /// As [`words_mut`].
    #[inline]
    pub unsafe fn words_mut_u64<'a>(word: AxWord, func: &str, idx: usize, name: &str) -> &'a mut [u64] {
        if word == 0 {
            abort(format_args!("`{func}`: argument {idx} (`{name}`: &mut [u64]) is not a Vec: 0"));
        }
        let s = AxVec::from_raw(word).as_mut_slice();
        // SAFETY: as `words_mut_f64`.
        core::slice::from_raw_parts_mut(s.as_mut_ptr() as *mut u64, s.len())
    }

    /// The inner `Vec` handles of a `&[&[T]]` argument: an Axiom `Vec`
    /// whose words are `Vec` handles, each checked against 0.
    ///
    /// # Safety
    /// `word` must be 0 or a live Axiom `Vec` of `Vec` handles for the call.
    unsafe fn list_words<'a>(word: AxWord, func: &str, idx: usize, name: &str, shown: &str) -> &'a [i64] {
        if word == 0 {
            abort(format_args!("`{func}`: argument {idx} (`{name}`: &[&[{shown}]]) is not a Vec: 0"));
        }
        let rows = AxVec::from_raw(word).as_slice();
        for (r, &h) in rows.iter().enumerate() {
            if h == 0 {
                abort(format_args!(
                    "`{func}`: argument {idx} (`{name}`: &[&[{shown}]]) list {r} is not a Vec: 0"
                ));
            }
        }
        rows
    }

    /// A `&[&[i64]]` argument: one borrowed word slice per inner `Vec`,
    /// no copy.
    ///
    /// # Safety
    /// `word` must be 0 or a live Axiom `Vec` of `Vec` handles for the call.
    pub unsafe fn word_lists<'a>(word: AxWord, func: &str, idx: usize, name: &str) -> Vec<&'a [i64]> {
        list_words(word, func, idx, name, "i64")
            .iter()
            .map(|&h| AxVec::from_raw(h).as_slice())
            .collect()
    }

    /// A `&[&[f64]]` argument: each inner `Vec` reinterpreted in place
    /// as [`words_f64`] does.
    ///
    /// # Safety
    /// As [`word_lists`].
    pub unsafe fn word_lists_f64<'a>(word: AxWord, func: &str, idx: usize, name: &str) -> Vec<&'a [f64]> {
        list_words(word, func, idx, name, "f64")
            .iter()
            .map(|&h| {
                let s = AxVec::from_raw(h).as_slice();
                core::slice::from_raw_parts(s.as_ptr() as *const f64, s.len())
            })
            .collect()
    }

    /// A `&[&[u64]]` argument: each inner `Vec` reinterpreted in place
    /// as [`words_u64`] does.
    ///
    /// # Safety
    /// As [`word_lists`].
    pub unsafe fn word_lists_u64<'a>(word: AxWord, func: &str, idx: usize, name: &str) -> Vec<&'a [u64]> {
        list_words(word, func, idx, name, "u64")
            .iter()
            .map(|&h| {
                let s = AxVec::from_raw(h).as_slice();
                core::slice::from_raw_parts(s.as_ptr() as *const u64, s.len())
            })
            .collect()
    }

    /// A `&[&[T]]` argument for any other word scalar: every inner `Vec`
    /// converted into a temporary `Vec<T>` (the shim borrows a
    /// `Vec<&[T]>` over them). A word that holds no `T` aborts with the
    /// list and element named.
    ///
    /// # Safety
    /// As [`word_lists`].
    pub unsafe fn word_lists_as<T: WordScalar>(
        word: AxWord,
        func: &str,
        idx: usize,
        name: &str,
    ) -> Vec<Vec<T>> {
        list_words(word, func, idx, name, T::NAME)
            .iter()
            .enumerate()
            .map(|(r, &h)| {
                convert_words(AxVec::from_raw(h).as_slice(), func, idx, name, T::NAME, Some(r))
            })
            .collect()
    }

    /// Hand owned word lists to Axiom as `(ptr, n)`: `ptr` holds `2n`
    /// words, a `(wordsPtr, len)` pair per inner list, each pair what
    /// [`leak_words`] answers. Axiom's glue builds a `Vec` of `Vec`s and
    /// calls [`axffi_free_word_lists`](super::axffi_free_word_lists),
    /// which frees every inner buffer and then the pairs.
    pub fn leak_word_lists(v: Vec<Vec<i64>>) -> (AxWord, AxWord) {
        let n = v.len() as AxWord;
        let mut pairs: Vec<i64> = Vec::with_capacity(v.len() * 2);
        for inner in v {
            let (p, len) = leak_words(inner);
            pairs.push(p);
            pairs.push(len);
        }
        let (p, _) = leak_words(pairs);
        (p, n)
    }

    /// Widen a `Vec<Vec<T>>` of word scalars into word lists, for
    /// [`leak_word_lists`].
    pub fn to_word_lists<T: WordScalar>(v: Vec<Vec<T>>) -> Vec<Vec<i64>> {
        v.into_iter().map(to_words).collect()
    }

    /// A `&[R]` argument over an `#[axiom_record]`: the Axiom `Vec`
    /// holds `R::ARITY` words per element (the generated wrapper
    /// flattened the records), chunked into a temporary `Vec<R>`. A
    /// word count that is not a multiple of the arity aborts: the
    /// vector was not built by the wrapper.
    ///
    /// # Safety
    /// `word` must be 0 or a live Axiom `Vec` handle for the call.
    pub unsafe fn records<R: AxRecord>(word: AxWord, func: &str, idx: usize, name: &str, record: &str) -> Vec<R> {
        if word == 0 {
            abort(format_args!("`{func}`: argument {idx} (`{name}`: &[{record}]) is not a Vec: 0"));
        }
        let s = AxVec::from_raw(word).as_slice();
        if !s.len().is_multiple_of(R::ARITY) {
            abort(format_args!(
                "`{func}`: argument {idx} (`{name}`: &[{record}]) holds {} words, not a multiple \
                 of the record's {} fields",
                s.len(),
                R::ARITY
            ));
        }
        s.chunks_exact(R::ARITY).map(R::from_words).collect()
    }

    /// Hand owned records to Axiom as `(ptr, n)`: `ptr` holds
    /// `n * R::ARITY` words, element-major in field order, freed by
    /// Axiom's glue as that many words with
    /// [`axffi_free_words`](super::axffi_free_words).
    pub fn leak_records<R: AxRecord>(v: Vec<R>) -> (AxWord, AxWord) {
        let n = v.len() as AxWord;
        let mut words: Vec<i64> = alloc::vec![0; v.len() * R::ARITY];
        for (r, chunk) in v.iter().zip(words.chunks_exact_mut(R::ARITY)) {
            r.write_words(chunk);
        }
        let (p, _) = leak_words(words);
        (p, n)
    }

    /// The element words of a `&[&str]` argument: an Axiom `Vec` whose
    /// words are String handles.
    ///
    /// # Safety
    /// `word` must be 0 or a live Axiom `Vec` of Strings for the call.
    unsafe fn str_words<'a>(word: AxWord, func: &str, idx: usize, name: &str) -> &'a [i64] {
        if word == 0 {
            abort(format_args!("`{func}`: argument {idx} (`{name}`: &[&str]) is not a Vec: 0"));
        }
        AxVec::from_raw(word).as_slice()
    }

    /// The UTF-8 failure message for one element of a `&[&str]`.
    fn utf8_element_message(func: &str, idx: usize, k: usize) -> String {
        alloc::format!("element {k} of argument {idx} of `{func}` is not valid UTF-8")
    }

    /// A `&[&str]` argument of an infallible shim: every String of the
    /// Axiom `Vec` borrowed as `&str`; invalid UTF-8 aborts.
    ///
    /// # Safety
    /// `word` must be 0 or a live Axiom `Vec` of Strings for the call.
    pub unsafe fn strs_strict<'a>(word: AxWord, func: &str, idx: usize, name: &str) -> Vec<&'a str> {
        let mut out = Vec::new();
        for (k, &s) in str_words(word, func, idx, name).iter().enumerate() {
            match AxStr::from_raw(s).as_str() {
                Ok(v) => out.push(v),
                Err(_) => abort(format_args!("{}", utf8_element_message(func, idx, k))),
            }
        }
        out
    }

    /// A `&[&str]` argument of a fallible shim: invalid UTF-8 is `Err`.
    ///
    /// # Safety
    /// `word` must be 0 or a live Axiom `Vec` of Strings for the call.
    pub unsafe fn strs_fallible<'a>(
        word: AxWord,
        func: &str,
        idx: usize,
        name: &str,
    ) -> Result<Vec<&'a str>, String> {
        let mut out = Vec::new();
        for (k, &s) in str_words(word, func, idx, name).iter().enumerate() {
            match AxStr::from_raw(s).as_str() {
                Ok(v) => out.push(v),
                Err(_) => return Err(utf8_element_message(func, idx, k)),
            }
        }
        Ok(out)
    }

    /// A `&[&str]` argument under `utf8 = "lossy"`: the converted
    /// strings, owned (the shim borrows a `Vec<&str>` from them).
    ///
    /// # Safety
    /// `word` must be 0 or a live Axiom `Vec` of Strings for the call.
    pub unsafe fn strs_lossy(word: AxWord, func: &str, idx: usize, name: &str) -> Vec<String> {
        str_words(word, func, idx, name)
            .iter()
            .map(|&s| String::from_utf8_lossy(AxStr::from_raw(s).as_bytes()).into_owned())
            .collect()
    }

    /// Range-check a narrow integer FIELD of a record parameter. Out of
    /// range aborts with the record and field named, as a scalar
    /// argument's abort names the function and argument.
    #[inline]
    pub fn record_field<T: WordScalar>(word: AxWord, record: &str, field: &str) -> T {
        match T::from_word(word) {
            Some(v) => v,
            None => abort(format_args!(
                "`{record}`: field `{field}` ({}) {}: {word}",
                T::NAME,
                T::REFUSAL
            )),
        }
    }

    /// Write a record result into the out-cell: `R::ARITY` words from
    /// the cell's first word.
    ///
    /// # Safety
    /// `out` must be the address of a cell of at least `R::ARITY` words
    /// Axiom glue allocated for this call (`ffiCellNewN`).
    #[inline]
    pub unsafe fn write_record<R: AxRecord>(out: AxWord, v: &R) {
        let words = core::slice::from_raw_parts_mut(out as *mut AxWord, R::ARITY);
        v.write_words(words)
    }

    /// A callback argument. A 0 word is no closure record and aborts
    /// rather than loading a code address from address 0.
    ///
    /// # Safety
    /// `word` must be 0 or a live Axiom closure record of `F::ARITY`
    /// for the call.
    #[inline]
    pub unsafe fn callback<F: AxCallback>(word: AxWord, func: &str, idx: usize, name: &str) -> F {
        if word == 0 {
            abort(format_args!(
                "`{func}`: argument {idx} (`{name}`: a function of {} argument{}) is not a \
                 closure: 0",
                F::ARITY,
                if F::ARITY == 1 { "" } else { "s" }
            ));
        }
        F::from_raw(word)
    }

    /// Write an error message into the cell and answer `AX_ERR`.
    pub fn err_into(cell: &mut AxOutCell, message: String) -> AxWord {
        let (p, n) = leak_bytes(message.into_bytes());
        cell.payload = p;
        cell.extra = n;
        AX_ERR
    }
}

/// Free bytes handed out by a shim.
///
/// Axiom's generated glue calls this immediately after copying, so the
/// window in which Rust memory is reachable from Axiom is one copy long.
///
/// # Safety
/// `ptr`/`len` must be exactly what a shim returned and must not have
/// been freed.
/// Returns `i64` because Axiom's ABI is one word in and one word out;
/// a `void` shim makes the call site read a register the callee never
/// set. Nothing to report, so it reports 0.
#[no_mangle]
pub unsafe extern "C" fn axffi_free_bytes(ptr: *mut u8, len: i64) -> i64 {
    if ptr.is_null() || len <= 0 {
        return 0;
    }
    let s = core::ptr::slice_from_raw_parts_mut(ptr, len as usize);
    drop(alloc::boxed::Box::from_raw(s));
    0
}

/// Free words handed out by a shim (a `Vec<i64>` return).
///
/// # Safety
/// `ptr`/`len` must be exactly what a shim wrote into the out-cell and
/// must not have been freed.
#[no_mangle]
pub unsafe extern "C" fn axffi_free_words(ptr: *mut i64, len: i64) -> i64 {
    if ptr.is_null() || len <= 0 {
        return 0;
    }
    let s = core::ptr::slice_from_raw_parts_mut(ptr, len as usize);
    drop(alloc::boxed::Box::from_raw(s));
    0
}

/// Free a string list handed out by a shim (a `Vec<String>` return):
/// `ptr` holds `2n` words of `(bytesPtr, byteLen)` pairs. Every string
/// is freed as [`axffi_free_bytes`] would free it, then the pairs.
///
/// # Safety
/// `ptr`/`n` must be exactly what a shim wrote into the out-cell and
/// must not have been freed.
#[no_mangle]
pub unsafe extern "C" fn axffi_free_str_list(ptr: *mut i64, n: i64) -> i64 {
    if ptr.is_null() || n <= 0 {
        return 0;
    }
    let pairs = core::slice::from_raw_parts(ptr, n as usize * 2);
    for pair in pairs.chunks_exact(2) {
        axffi_free_bytes(pair[0] as *mut u8, pair[1]);
    }
    axffi_free_words(ptr, n * 2)
}

/// Free a word-list list handed out by a shim (a `Vec<Vec<T>>` return):
/// `ptr` holds `2n` words of `(wordsPtr, len)` pairs. Every inner
/// buffer is freed as [`axffi_free_words`] would free it, then the
/// pairs.
///
/// # Safety
/// `ptr`/`n` must be exactly what a shim wrote into the out-cell and
/// must not have been freed.
#[no_mangle]
pub unsafe extern "C" fn axffi_free_word_lists(ptr: *mut i64, n: i64) -> i64 {
    if ptr.is_null() || n <= 0 {
        return 0;
    }
    let pairs = core::slice::from_raw_parts(ptr, n as usize * 2);
    for pair in pairs.chunks_exact(2) {
        axffi_free_words(pair[0] as *mut i64, pair[1]);
    }
    axffi_free_words(ptr, n * 2)
}

/// The ABI fingerprint this crate was built against.
///
/// Every crate that depends on the facade carries it, and an Axiom
/// program can read it (`stdlib/Ffi.ax` binds it as `ffiAbiVersion`)
/// to refuse a crate built against a different wire representation.
#[no_mangle]
pub extern "C" fn axffi_abi_version() -> i64 {
    ABI_VERSION
}

/// Bump this on ANY change to a wire representation: the word size, the
/// `String` layout, the out-cell shape, or the status encoding.
///
/// History: 1 = the first boundary (out-cell, statuses 0/1); 2 = status
/// 2 means `None`, opaque values carry a drop function
/// (`axffi_<t>_drop_fn`), narrow integers are range-checked. Still 2
/// after the additive shapes of 2026-08-22 - the `__sig_` descriptors,
/// callbacks as closure records, `Vec<i64>`/`Vec<String>` through the
/// cell as `(ptr, len)` / `(pairs, n)`, `&[i64]` over a `Vec` handle,
/// then records as their field words through an N-word cell, `&[&str]`
/// and `Vec<T>`/`&[T]` over every word scalar (each element a word),
/// then `char` and `u64` as words, `Vec<Record>` as `n * ARITY` words,
/// `Vec<Vec<T>>` as `(pairs, n)` of word buffers, `&mut [T]` in place
/// and the nested `Result<Option<T>, E>` / `Option<Result<T, E>>` over
/// the same three statuses - because no representation a version-2
/// crate already uses moved.
pub const ABI_VERSION: i64 = 2;
