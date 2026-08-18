//! The Axiom <-> Rust calling contract.
//!
//! This crate is `no_std`. That is not decoration: it is the difference
//! between a program that keeps Axiom's freestanding property and one
//! that does not. Measured on darwin-aarch64, an Axiom executable linked
//! against a `no_std` + `panic = "abort"` staticlib has an *empty*
//! `nm -u`; the same program linked against a `std` staticlib imports 188
//! symbols, 14 of them on `scripts/check-freestanding.sh`'s forbidden
//! list (`malloc`, `free`, `memcpy`, `strlen`, ...). Both link and run;
//! only the first one is still freestanding.
//!
//! # The one-word rule
//!
//! Every Axiom value is exactly one 64-bit word (`docs/memory-model.md`
//! MM-VAL-1, invariant I1). Every Axiom function emits as
//! `define i64 @name(i64, ...)` with no parameter attributes and no
//! calling-convention marker (`self_host/codegen.ax:3014-3018`). So the
//! entire ABI is: **i64 in, i64 out, C calling convention**.
//!
//! # What Rust may and may not touch
//!
//! Rust **must never construct an Axiom heap object.** Every block from
//! `axiom_alloc` carries a 16-byte header whose shape word packs a form
//! bit, a payload word count, and one bit per payload word marking which
//! words are references the ARC release walk must follow
//! (MM-LIFE-2d). A Rust-built header with a wrong bitmap does not fail
//! loudly; it makes `axiom_release` walk into Rust memory and free it.
//!
//! Therefore the rule is: **Rust returns raw bytes or an opaque handle;
//! generated Axiom glue does every Axiom-side allocation.** Rust reads
//! Axiom memory through the borrowed views below and writes none of it.

#![no_std]
#![deny(improper_ctypes_definitions)]

use core::marker::PhantomData;
use core::slice;
use core::str;

/// The universal Axiom value. Every argument and every return is one of
/// these, whatever its Axiom type.
pub type AxWord = i64;

/// The status word a fallible shim returns. See [`AxStatus`].
pub type AxStatus = i64;

/// A fallible shim returned normally.
pub const AX_OK: AxStatus = 0;
/// A fallible shim returned an error value through its out-cell.
pub const AX_ERR: AxStatus = 1;
/// A fallible shim caught a panic. The out-cell holds a borrowed message.
pub const AX_PANIC: AxStatus = 2;

// ---------------------------------------------------------------------
// The Axiom runtime symbols Rust is permitted to call.
//
// These four have EXTERNAL linkage in every emitted module
// (`self_host/codegen.ax:2046`, `:2274`, `:2292`, `:1994`); the six
// internal helpers are `define internal` and are deliberately not
// declared here.
// ---------------------------------------------------------------------
extern "C" {
    /// Axiom's bump allocator. Returns a 16-byte-aligned block whose
    /// bytes read as zero (invariants I5, I6).
    ///
    /// Calling this from Rust is sound, but the result is a *raw* block
    /// with no header written by you — see the module note. Prefer
    /// returning [`AxBytes`] and letting Axiom glue allocate.
    pub fn axiom_alloc(size: i64) -> i64;

    /// Take a share of an Axiom heap value. Pairs 1:1 with
    /// [`axiom_release`]. A static's count word is `-1` and both calls
    /// read it as a sentinel and stop, so retaining a literal is free
    /// and safe.
    pub fn axiom_retain(handle: AxWord);

    /// Drop a share taken with [`axiom_retain`].
    pub fn axiom_release(handle: AxWord);
}

// ---------------------------------------------------------------------
// Strings
// ---------------------------------------------------------------------

/// The three words an Axiom `String` value points at.
///
/// Verified against `stdlib/Str.ax:126-141` — `strLen` reads word 0,
/// `strData` word 1, `strOwner` word 2 — and against the emitted header
/// static `{ i64, i64, i64, ptr, i64 }` whose element 2 is the value
/// address (`self_host/codegen.ax:991-1040`). The block's own count and
/// shape words sit at `-16` and `-8` from this address.
#[repr(C)]
#[derive(Debug)]
pub struct AxStrRepr {
    /// Byte length, excluding the NUL terminator.
    pub len: i64,
    /// Pointer to the bytes. Always NUL-terminated (MM-VAL-7), which is
    /// what lets `strCStr` hand them straight to a syscall.
    pub data: *const u8,
    /// The block owning `data`, or 0 for bytes no block owns (a
    /// literal's, a syscall buffer's).
    pub owner: i64,
}

/// A borrowed view of an Axiom `String`.
///
/// The lifetime is the *call*. Axiom's ARC may release the backing block
/// the moment the call returns, and an arena reset may reclaim it
/// wholesale, so a view that outlives the shim is a dangling pointer.
/// The generated shims never let one escape; if you write a shim by
/// hand, this is the invariant to keep.
#[derive(Clone, Copy)]
pub struct AxStr<'a> {
    raw: AxWord,
    _life: PhantomData<&'a [u8]>,
}

impl<'a> AxStr<'a> {
    /// # Safety
    /// `raw` must be a live Axiom `String` value for all of `'a`.
    #[inline]
    pub const unsafe fn from_raw(raw: AxWord) -> Self {
        Self { raw, _life: PhantomData }
    }

    #[inline]
    pub fn as_word(self) -> AxWord {
        self.raw
    }

    #[inline]
    fn repr(self) -> &'a AxStrRepr {
        // SAFETY: the from_raw contract.
        unsafe { &*(self.raw as *const AxStrRepr) }
    }

    #[inline]
    pub fn len(self) -> usize {
        self.repr().len as usize
    }

    #[inline]
    pub fn is_empty(self) -> bool {
        self.repr().len == 0
    }

    /// The bytes, borrowed. Zero-copy: this is the exact pointer Axiom
    /// holds, not a duplicate.
    #[inline]
    pub fn as_bytes(self) -> &'a [u8] {
        let r = self.repr();
        if r.len == 0 || r.data.is_null() {
            return &[];
        }
        // SAFETY: Axiom guarantees `len` readable bytes at `data`.
        unsafe { slice::from_raw_parts(r.data, r.len as usize) }
    }

    /// The bytes as `&str`, validated.
    ///
    /// Axiom's `Str` is a byte string, not a Unicode string: `stdlib`
    /// has a separate `Utf8` module, and nothing in the language forces
    /// a `Str` to hold well-formed UTF-8 (a program can `__store8` any
    /// byte into a buffer it allocated). So this **validates**, and a
    /// shim that wants `&str` must decide what an invalid string means.
    #[inline]
    pub fn as_str(self) -> Result<&'a str, str::Utf8Error> {
        str::from_utf8(self.as_bytes())
    }

    /// The bytes as `&str`, replacing the whole string with `""` if it
    /// is not valid UTF-8. For shims where refusing is not worth a
    /// round trip.
    #[inline]
    pub fn as_str_or_empty(self) -> &'a str {
        self.as_str().unwrap_or("")
    }
}

// ---------------------------------------------------------------------
// Returning bytes to Axiom
// ---------------------------------------------------------------------

/// A byte buffer Rust owns and Axiom is about to copy.
///
/// This is the answer to "how does Rust return a String". It does not
/// build an Axiom `Str` — it hands back a pointer and a length, the
/// generated Axiom glue copies the bytes into a real `strAlloc` block
/// (which gets a correct header, a correct reference bitmap and the NUL
/// terminator MM-FFI-4 requires), and then calls the paired free.
///
/// The cost is one copy. The alternative — Rust allocating through
/// `axiom_alloc` and writing the header itself — saves that copy and
/// costs the ability to ever change the header encoding without
/// silently corrupting every crate compiled against the old one.
#[repr(C)]
pub struct AxBytes {
    pub ptr: *mut u8,
    pub len: i64,
    /// A token the paired free needs to reconstruct the allocation.
    /// For a `Box<[u8]>` this is the capacity.
    pub cap: i64,
}

impl AxBytes {
    pub const EMPTY: AxBytes = AxBytes { ptr: core::ptr::null_mut(), len: 0, cap: 0 };
}

// ---------------------------------------------------------------------
// Opaque handles
// ---------------------------------------------------------------------

/// A Rust value Axiom holds as one opaque word.
///
/// This is the mechanism that makes ecosystem leverage practical: a
/// `reqwest::Client`, a `sha2::Sha256`, a `serde_json::Value` never has
/// to be describable in Axiom's type system. Axiom holds the word,
/// passes it back, and calls a registered destructor when done.
///
/// The word is a raw pointer, which is why it must get Axiom's opaque
/// foreign type and not `Int`: MM-FFI-5 requires foreign memory be a
/// distinct type, and the operational reason is that its ARC bitmap bit
/// must stay CLEAR. A foreign pointer whose bit is set is walked by
/// `axiom_release`, which then reads a Rust allocation as an Axiom
/// block header.
pub struct AxOpaque<T>(PhantomData<T>);

impl<T> AxOpaque<T> {
    /// Move `value` onto the Rust heap and hand Axiom the word.
    ///
    /// Requires an allocator, so a `no_std` crate needs
    /// `extern crate alloc` and a global allocator. The `axiom-ffi`
    /// facade provides one that forwards to `axiom_alloc`.
    #[inline]
    pub fn into_word(value: alloc_shim::Boxed<T>) -> AxWord {
        alloc_shim::into_raw(value) as AxWord
    }

    /// Borrow the value for the duration of a call.
    ///
    /// # Safety
    /// `word` must have come from [`Self::into_word`] and must not have
    /// been freed.
    #[inline]
    pub unsafe fn borrow<'a>(word: AxWord) -> &'a T {
        &*(word as *const T)
    }

    /// Borrow mutably.
    ///
    /// # Safety
    /// As [`Self::borrow`], and no other borrow may be live. Axiom has
    /// no threads (MM-PAR-1), so the only way to alias is to pass the
    /// same handle twice in one call — which the generated glue refuses.
    #[inline]
    pub unsafe fn borrow_mut<'a>(word: AxWord) -> &'a mut T {
        &mut *(word as *mut T)
    }

    /// Free the value. This is what a registered destructor calls.
    ///
    /// # Safety
    /// `word` must have come from [`Self::into_word`] and must not have
    /// been freed already. Axiom is ARC with no finalizers, so this runs
    /// when the program says so, not when the last reference dies.
    #[inline]
    pub unsafe fn drop_word(word: AxWord) {
        alloc_shim::drop_raw::<T>(word as *mut T);
    }
}

/// Indirection so this crate stays `no_std` while still describing the
/// boxed-value protocol. The `axiom-ffi` facade wires these to `alloc`.
pub mod alloc_shim {
    /// The boxed form. `axiom-ffi` sets this to `alloc::boxed::Box`.
    pub type Boxed<T> = *mut T;

    #[inline]
    pub fn into_raw<T>(b: Boxed<T>) -> *mut T {
        b
    }

    /// # Safety
    /// `p` must be a live pointer from a matching allocation.
    #[inline]
    pub unsafe fn drop_raw<T>(p: *mut T) {
        core::ptr::drop_in_place(p);
    }
}

// ---------------------------------------------------------------------
// The out-cell used by fallible shims
// ---------------------------------------------------------------------

/// The two-word scratch cell an Axiom caller allocates for a fallible
/// call.
///
/// A fallible shim cannot return two words: Axiom emits `ret i64` for
/// every function and has no syntax or codegen path for a wider return
/// (`self_host/codegen.ax:3014`, `:3128-3131`). It cannot use a global
/// last-error slot either without making every call site order-dependent.
/// So the caller passes a cell, the shim writes the payload into it, and
/// the status word is the return.
///
/// The cell is allocated by generated **Axiom** glue, so it is a proper
/// arena block with a correct header.
#[repr(C)]
pub struct AxOutCell {
    /// On `AX_OK`, the success value. On `AX_ERR`/`AX_PANIC`, an
    /// [`AxBytes`] pointer describing the message.
    pub payload: AxWord,
    /// Reserved; carries the `AxBytes` length for message payloads.
    pub extra: AxWord,
}

impl AxOutCell {
    /// # Safety
    /// `word` must be an address Axiom glue allocated for this call.
    #[inline]
    pub unsafe fn from_word<'a>(word: AxWord) -> &'a mut AxOutCell {
        &mut *(word as *mut AxOutCell)
    }
}
