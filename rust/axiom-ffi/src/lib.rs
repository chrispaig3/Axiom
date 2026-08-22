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
//! value when its count reaches zero.
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
//! integer out of range, invalid UTF-8 into an infallible `&str`, a
//! closed handle. Axiom has no way to receive an error from an
//! infallible call, so the alternative would be a silent wrong answer.

#![cfg_attr(not(feature = "std"), no_std)]

#[cfg(all(feature = "std", feature = "nostd-runtime"))]
compile_error!(
    "axiom-ffi: the `nostd-runtime` feature replaces std's allocator and panic \
     handler; use it with `default-features = false`"
);

extern crate alloc;

pub use axiom_abi::{
    axiom_alloc, axiom_release, axiom_retain, AxOutCell, AxStatus, AxStr, AxStrRepr, AxWord,
    AX_ERR, AX_NONE, AX_OK,
};
pub use axiom_ffi_macros::{axiom_export, axiom_opaque};

#[cfg(feature = "nostd-runtime")]
pub mod nostd_runtime;

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

/// Implementation details the generated shims call. Not a stable API.
#[doc(hidden)]
pub mod __private {
    use super::{AxOutCell, AxStr, AxWord, AxiomOpaque, AX_ERR};
    use alloc::boxed::Box;
    use alloc::string::String;
    use alloc::vec::Vec;
    use core::fmt::Arguments;

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

    /// Range-check a narrow integer argument. Out of range aborts: an
    /// infallible shim has no channel for an error, and truncation is
    /// the silent-wrong-answer case.
    #[inline]
    pub fn narrow<T: TryFrom<AxWord>>(word: AxWord, func: &str, idx: usize, name: &str) -> T {
        match T::try_from(word) {
            Ok(v) => v,
            Err(_) => abort(format_args!(
                "`{func}`: argument {idx} (`{name}`: {}) is out of range: {word}",
                core::any::type_name::<T>()
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
/// (`axffi_<t>_drop_fn`), narrow integers are range-checked.
pub const ABI_VERSION: i64 = 2;
