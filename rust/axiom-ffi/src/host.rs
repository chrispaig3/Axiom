//! The other direction: a Rust program that calls into an Axiom archive.
//!
//! `axiom build --input lib.ax --output libaxiom_hostlib.a --emit-staticlib`
//! emits a module without the `@main` wrapper, assembles and archives
//! it. Every `pub fn` of the entry file is a C symbol under its own
//! name (`addTwo`, `shout`) with Axiom's whole ABI: `i64` in, `i64`
//! out. A Rust binary declares them in an `extern "C"` block, links
//! the archive (`cargo:rustc-link-lib=static=axiom_hostlib` from a
//! `build.rs`) and calls them. The runtime needs no initialisation:
//! the allocator initialises on first use.
//!
//! # Symbols a host relies on
//!
//! | symbol | where it comes from | what for |
//! |---|---|---|
//! | `<name>` | every `pub fn` of the entry file | the functions the host calls |
//! | `Str$strAlloc` | `stdlib/Str.ax`, the module mangle `Mod$name` | building an Axiom `String` for an argument |
//! | `axiom_retain` / `axiom_release` | the emitted runtime | keeping / returning a share |
//!
//! # Strings
//!
//! Rust must never write an Axiom block header (see `axiom-abi`'s
//! module note), so a `String` the host hands to Axiom comes from
//! Axiom's own `strAlloc`: [`AxString::from_str`] calls it for the
//! byte length, then copies the bytes to `strData` (word 1 of the
//! three-word header) - the block is already NUL-terminated and zeroed,
//! so the copy is the whole job. The host owns one share of the result
//! and [`AxString`]'s `Drop` gives it back.
//!
//! A `String` an Axiom function ANSWERS is owned by the caller
//! (MM-LIFE-2c event 2): adopt it with [`AxString::from_owned`] so the
//! share is released, or read it in place with [`read_str`] and leak
//! it. A value passed INTO an Axiom call is borrowed for the call
//! (event 1): the host's share covers it.

use crate::{axiom_release, AxStr, AxStrRepr, AxWord};
use core::str::Utf8Error;

unsafe extern "C" {
    /// `stdlib/Str.ax`: a `String` over fresh zeroed space for `len`
    /// bytes (plus the NUL), held by one share the caller owns.
    #[link_name = "Str$strAlloc"]
    fn str_alloc(len: AxWord) -> AxWord;
}

/// An Axiom `String` a host owns one share of.
#[derive(Debug)]
pub struct AxString {
    word: AxWord,
    /// See [`axiom_abi::NotThreadSafe`]. This one is the OWNING handle,
    /// so the race it prevents is `Drop` calling `axiom_release` from a
    /// thread that did not allocate it.
    _thread: axiom_abi::NotThreadSafe,
}

impl AxString {
    /// A fresh Axiom `String` holding `s`'s bytes: `Str$strAlloc` for
    /// the length, then the bytes copied to word 1 of the header.
    ///
    /// Needs the archive linked: the call resolves against the Axiom
    /// side's own `Str` module.
    ///
    /// Deliberately NOT `std::str::FromStr`: that trait returns
    /// `Result<Self, Self::Err>` and this cannot fail - every `&str` is
    /// a valid Axiom `Str`, since an Axiom `Str` is a byte string with
    /// no encoding requirement. An `Err` type nothing can construct is
    /// worse than an inherent method with the obvious name.
    #[allow(clippy::should_implement_trait)]
    pub fn from_str(s: &str) -> AxString {
        Self::from_bytes(s.as_bytes())
    }

    /// As [`from_str`](Self::from_str), for bytes that need not be UTF-8
    /// (an Axiom `Str` is a byte string).
    pub fn from_bytes(bytes: &[u8]) -> AxString {
        // SAFETY: `Str$strAlloc` is Axiom's own constructor; it answers
        // a header whose word 1 addresses `len + 1` zeroed bytes, so
        // the copy of `len` bytes stays inside the block and leaves the
        // terminator in place.
        let word = unsafe {
            let word = str_alloc(bytes.len() as AxWord);
            let repr = &*(word as *const AxStrRepr);
            core::ptr::copy_nonoverlapping(bytes.as_ptr(), repr.data as *mut u8, bytes.len());
            word
        };
        AxString {
            word,
            _thread: core::marker::PhantomData,
        }
    }

    /// Adopt the share of a `String` an Axiom function answered, so it
    /// is released when this value drops.
    ///
    /// # Safety
    /// `word` must be a live Axiom `String` the caller owns one share
    /// of - the result of an Axiom call, not an argument it borrowed.
    pub unsafe fn from_owned(word: AxWord) -> AxString {
        AxString {
            word,
            _thread: core::marker::PhantomData,
        }
    }

    /// The word to pass to an Axiom function.
    #[inline]
    pub fn as_word(&self) -> AxWord {
        self.word
    }

    /// Give up the share without releasing it: the word is now the
    /// caller's to release (or to hand to an Axiom function that
    /// stores it).
    #[inline]
    pub fn into_word(self) -> AxWord {
        let w = self.word;
        core::mem::forget(self);
        w
    }

    /// The string's bytes, borrowed for as long as this handle lives.
    /// Zero-copy: the pointer is the one Axiom holds, not a duplicate,
    /// and the share this value owns is what keeps it alive.
    #[inline]
    pub fn as_bytes(&self) -> &[u8] {
        // SAFETY: this value holds a share, so the string is live.
        unsafe { AxStr::from_raw(self.word).as_bytes() }
    }

    /// The bytes as `&str`, validated. An Axiom `Str` is a BYTE string
    /// and is not required to be UTF-8, which is why this can fail and
    /// [`as_bytes`](Self::as_bytes) cannot.
    #[inline]
    pub fn as_str(&self) -> Result<&str, Utf8Error> {
        core::str::from_utf8(self.as_bytes())
    }
}

impl Drop for AxString {
    fn drop(&mut self) {
        // SAFETY: the share this value holds, given back exactly once.
        unsafe { axiom_release(self.word) }
    }
}

/// Read an Axiom `String` in place, as `&str`.
///
/// # Safety
/// `word` must be a live Axiom `String` for all of `'a`. The view does
/// not take or release a share.
pub unsafe fn read_str<'a>(word: AxWord) -> Result<&'a str, Utf8Error> {
    // SAFETY: `AxStr::from_raw` needs a live Axiom `String` for all of
    // `'a`, which is exactly what this function's `# Safety` asks the
    // caller for. The view takes no share, so nothing here has to be
    // given back.
    unsafe { AxStr::from_raw(word).as_str() }
}

/// Read an Axiom `String` in place, as bytes.
///
/// # Safety
/// As [`read_str`].
pub unsafe fn read_bytes<'a>(word: AxWord) -> &'a [u8] {
    // SAFETY: as `read_str` - the caller promises a live Axiom `String`
    // for all of `'a`, and this borrows its bytes without taking a
    // share. Only the UTF-8 validation differs.
    unsafe { AxStr::from_raw(word).as_bytes() }
}
