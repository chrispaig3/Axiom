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

/// A fallible shim returned normally: the out-cell holds the payload.
pub const AX_OK: AxStatus = 0;
/// A fallible shim returned an error: the out-cell holds the message's
/// `(ptr, len)`, to be copied and then freed with `axffi_free_bytes`.
pub const AX_ERR: AxStatus = 1;
/// An `Option`-returning shim answered `None`. The out-cell is untouched.
///
/// There is no panic status: the workspace builds with `panic = "abort"`
/// and every shim is `extern "C"`, which aborts on unwind anyway, so a
/// Rust panic ends the process rather than crossing the boundary.
pub const AX_NONE: AxStatus = 2;

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
    /// returning owned bytes and letting Axiom glue allocate.
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
//
// This is the answer to "how does Rust return a String". A shim does
// not build an Axiom `Str` - it writes a pointer and a length into the
// caller's [`AxOutCell`], the generated Axiom glue copies the bytes into
// a real `strAlloc` block (which gets a correct header, a correct
// reference bitmap and the NUL terminator MM-FFI-4 requires), and then
// calls `axffi_free_bytes(ptr, len)`, defined once by the `axiom-ffi`
// facade, to release the Rust side.
//
// The cost is one copy. The alternative - Rust allocating through
// `axiom_alloc` and writing the header itself - saves that copy and
// costs the ability to ever change the header encoding without silently
// corrupting every crate compiled against the old one.

// ---------------------------------------------------------------------
// Opaque handles
// ---------------------------------------------------------------------
//
// A Rust value Axiom holds as one opaque word is a `Box<T>` turned into
// its address by the generated shim. This crate defines nothing for it
// because every operation on one needs an allocator: boxing, borrowing
// behind a null check, and the destructor. Those live in the `axiom-ffi`
// facade (`__private::leak_opaque`, `borrow`, `drop_opaque`) and are
// reached only through `#[axiom_export]` and `#[axiom_opaque]`.
//
// The protocol the two sides agree on:
//
// - the word is a raw `*mut T` from `Box::into_raw`, or 0;
// - `#[axiom_opaque]` on `T` generates `axffi_<t>_drop(word) -> i64`
//   (null-checked `Box::from_raw`) and `axffi_<t>_drop_fn() -> i64`,
//   which answers the address of the former;
// - Axiom's generated module wraps the word in a `Handle` block holding
//   `{dropFn, ptr}`; the runtime calls `dropFn(ptr)` when the handle's
//   count reaches 0 (or on an explicit close), and a closed handle
//   reads back as 0, which a shim's borrow refuses with an abort rather
//   than dereferencing.
//
// The word must get Axiom's `Foreign`/`Handle` types and not `Int`:
// MM-FFI-5 requires foreign memory be a distinct type, and the
// operational reason is that its ARC bitmap bit must stay CLEAR. A
// foreign pointer whose bit is set is walked by `axiom_release`, which
// then reads a Rust allocation as an Axiom block header.

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
    /// On `AX_OK`, the success value (or a byte pointer for a `String`
    /// payload). On `AX_ERR`, the message's byte pointer.
    pub payload: AxWord,
    /// The byte length when `payload` is a byte pointer; otherwise 0.
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
