//! The Axiom <-> Rust calling contract.
//!
//! This crate is `no_std`. That is not decoration: it is the difference
//! between a program that keeps Axiom's freestanding property and one
//! that does not. Measured on darwin-aarch64, an Axiom executable linked
//! against a `no_std` + `panic = "abort"` staticlib has an *empty*
//! `nm -u`; the same program linked against a `std` staticlib imports 188
//! symbols, 18 of them on `scripts/check-freestanding.sh`'s forbidden
//! list (`malloc`, `free`, `memcpy`, `strlen`, ...). Both link and run;
//! only the first one is still freestanding.
//!
//! # The one-word rule
//!
//! Every Axiom value is exactly one 64-bit word (`docs/memory-model.md`
//! MM-VAL-1, invariant I1). Every Axiom function emits as
//! `define i64 @name(i64, ...)` with no parameter attributes and no
//! calling-convention marker (the `"define i64 @"` header `emitFnDef`
//! writes in `self_host/codegen.ax`). So the
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
// These four have EXTERNAL linkage in every emitted module - grep
// `self_host/codegen.ax` for `define i64 @main`, `define i64
// @axiom_alloc`, `define void @axiom_retain` and `define void
// @axiom_release`. The internal helpers are emitted as
// `define internal` (`__axiom_str_eq`, `__axiom_div_by_zero`,
// `__axiom_arena_mark_fn`, ...) and are deliberately not declared here.
// ---------------------------------------------------------------------
unsafe extern "C" {
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
/// address (the `@strhdr_` constants the emitter writes for string
/// literals). The block's own count and
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

/// A zero-sized field that takes `Send` and `Sync` away.
///
/// Every handle in this module is a machine word, and a word is
/// `Send + Sync` by default — so until 2026-09-03 an `AxStr`, `AxVec`,
/// `AxFn1/2/3` or an owning `AxString` could be moved into
/// `std::thread::spawn` and nothing said otherwise. That contradicts the
/// only rule this crate has: the emitted runtime's `axiom_retain` and
/// `axiom_release` are a plain load-add-store, not an `atomicrmw`, so
/// two threads touching one block's count lose increments and the block
/// is freed under a live reference.
///
/// `docs/ffi.md` has always stated the restriction in prose. This is the
/// same sentence in the type system, which is where a restriction
/// belongs when it can be expressed there. `PhantomData<*const ()>` is
/// the standard spelling: a raw pointer is neither `Send` nor `Sync`,
/// and the field is zero-sized, so `#[repr(transparent)]` still holds
/// and no representation moves.
///
/// It is `pub` because a host writing its own handle type wants the
/// same field for the same reason.
///
/// The guarantee is a test, not a comment. Each of these fails to
/// compile, and `cargo test` fails if any of them starts compiling:
///
/// ```compile_fail
/// fn needs_send<T: Send>(_: T) {}
/// let s = unsafe { axiom_abi::AxStr::from_raw(0) };
/// needs_send(s);
/// ```
///
/// ```compile_fail
/// fn needs_sync<T: Sync>(_: T) {}
/// let s = unsafe { axiom_abi::AxStr::from_raw(0) };
/// needs_sync(s);
/// ```
///
/// ```compile_fail
/// fn needs_send<T: Send>(_: T) {}
/// let v = unsafe { axiom_abi::AxVec::from_raw(0) };
/// needs_send(v);
/// ```
///
/// ```compile_fail
/// use axiom_abi::AxCallback;
/// fn needs_send<T: Send>(_: T) {}
/// let f = unsafe { axiom_abi::AxFn1::from_raw(0) };
/// needs_send(f);
/// ```
///
/// A borrowed view still moves freely within one thread, which is the
/// whole of what a shim needs:
///
/// ```
/// let s = unsafe { axiom_abi::AxStr::from_raw(0) };
/// let moved = s;
/// let _ = moved.as_word();
/// ```
pub type NotThreadSafe = PhantomData<*const ()>;

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
    _thread: NotThreadSafe,
}

impl<'a> AxStr<'a> {
    /// # Safety
    /// `raw` must be a live Axiom `String` value for all of `'a`.
    #[inline]
    pub const unsafe fn from_raw(raw: AxWord) -> Self {
        Self {
            raw,
            _life: PhantomData,
            _thread: PhantomData,
        }
    }

    /// The raw handle, for `axiom_retain` / `axiom_release` and for
    /// handing the same `String` back to Axiom. Borrowing it does not
    /// take a share; see the module note on who owns what.
    #[inline]
    pub fn as_word(self) -> AxWord {
        self.raw
    }

    #[inline]
    fn repr(self) -> &'a AxStrRepr {
        // SAFETY: the from_raw contract.
        unsafe { &*(self.raw as *const AxStrRepr) }
    }

    /// Length in BYTES, excluding the NUL terminator - not a character
    /// count. Axiom stores it in the header, so this is a load rather
    /// than a scan, and a NUL inside the bytes does not shorten it.
    #[inline]
    pub fn len(self) -> usize {
        self.repr().len as usize
    }

    /// Whether the string is zero bytes long. Read from the header's
    /// length, so an empty `String` and a `String` of NULs are told
    /// apart the way Axiom tells them apart.
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
/// (every emitted header is `define i64 @...` and every return is
/// `ret i64`). It cannot use a global
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
        unsafe {
            // SAFETY: this function's `# Safety` puts it on the caller -
            // generated Axiom glue - to pass a cell it allocated for this
            // call: a live arena block, 16-byte aligned (I5), and by C3 the
            // caller's own for the call, so nothing else holds a reference
            // while the shim writes through this `&mut`.
            &mut *(word as *mut AxOutCell)
        }
    }
}

// ---------------------------------------------------------------------
// Records: a struct that crosses AS ITS FIELDS
// ---------------------------------------------------------------------

/// A struct marked `#[axiom_record]`: it crosses the boundary as its
/// fields, one word each in declaration order, never as a pointer.
/// Implemented by the attribute, never by hand.
///
/// Every field is a word scalar, so the record is a fixed number of
/// words: a PARAMETER arrives as `ARITY` shim arguments and is rebuilt
/// with [`from_words`](AxRecord::from_words); a RESULT is written with
/// [`write_words`](AxRecord::write_words) into an out-cell of `ARITY`
/// words the Axiom caller allocated (`ffiCellNewN`). The words use the
/// scalar rules: a narrow integer is range-checked on the way in (out
/// of range aborts, as a scalar argument would), a `bool` is 0/1, an
/// `f64` its bits, an `f32` widened to `f64` bits.
///
/// On the Axiom side the record is a `data` type with one constructor
/// and one positional field per Rust field, which the generated
/// wrapper destructures into the raw call and rebuilds from the cell.
pub trait AxRecord: Sized {
    /// The number of words: one per field.
    const ARITY: usize;

    /// Rebuild the value from `ARITY` words. A narrow field whose word
    /// is out of range aborts with the type and field named.
    fn from_words(words: &[AxWord]) -> Self;

    /// Write the field words into `out[..ARITY]`.
    fn write_words(&self, out: &mut [AxWord]);
}

// ---------------------------------------------------------------------
// Callbacks: an Axiom function value, called from Rust
// ---------------------------------------------------------------------
//
// An Axiom closure is a heap record whose word 0 is the code address
// and whose later words are the captures (`self_host/codegen.ax`,
// "Lambda expressions: capture, lifting, and the record convention").
// The lifted code is an ordinary C function `i64 (i64 %_env, i64 arg)`
// that takes the record itself first - a lifted lambda reads its
// captures from it, the forwarding thunk a bare top-level function
// gets as a value ignores it.
//
// EVERY function value absorbs exactly one argument. The parser builds
// `(lambda (x y) b)` as `(lambda (x) (lambda (y) b))`
// (`self_host/parser.ax`, `curryLam`), so a `(-> Int Int Int)` value
// is a chain: applying the first argument answers the record of the
// next link, and only the last application answers the value. The
// compiler's own `emitApplyChain` does exactly this, one step per
// argument - a flat `f(env, a, b)` call would hand the outer link a
// word it ignores and answer the INNER RECORD'S ADDRESS (measured:
// `fold3` printed `4376821888` before this was written as a chain).
// So [`AxFn2::call`] and [`AxFn3::call`] step through the chain.
//
// Ownership: the record a shim receives is BORROWED for the call
// (MM-LIFE-2c event 1); a shim that keeps one past its return takes a
// share with [`axiom_retain`] and gives it back with
// [`axiom_release`]. Each intermediate link a step answers is a value
// a function RETURNED, hence owned by the caller (event 2): `call`
// releases it once the next step is done.

/// An Axiom function value of a fixed arity, as a shim receives it.
///
/// Implemented by [`AxFn1`], [`AxFn2`] and [`AxFn3`]; the generated
/// shims construct one through [`AxCallback::from_raw`].
pub trait AxCallback: Copy {
    /// The number of arguments the closure takes.
    const ARITY: usize;

    /// # Safety
    /// `record` must be a live Axiom closure record of this arity for
    /// as long as the value is called.
    unsafe fn from_raw(record: AxWord) -> Self;

    /// The record word, for [`axiom_retain`] / [`axiom_release`].
    fn as_word(self) -> AxWord;
}

/// One link of the chain: load word 0 of `record` and call it with
/// the record as the hidden environment and one argument.
///
/// # Safety
/// `record` must be a live closure record.
#[inline]
unsafe fn apply_one(record: AxWord, arg: AxWord) -> AxWord {
    unsafe {
        // SAFETY: the caller promises a live closure record (this
        // function's `# Safety`), and the module note above fixes its
        // shape: word 0 is the code address of a lifted
        // `i64 (i64 %_env, i64 arg)` the emitter wrote, so the load is
        // in bounds and the transmute names that exact signature - one
        // argument, because the parser curries every lambda.
        let code = *(record as *const AxWord);
        let f: extern "C" fn(AxWord, AxWord) -> AxWord = core::mem::transmute(code as usize);
        f(record, arg)
    }
}

macro_rules! ax_fn {
    ($name:ident, $arity:expr_2021, $doc:expr_2021) => {
        #[doc = $doc]
        ///
        /// `Copy`, one word: the closure record. Valid for the call the
        /// shim received it in; see the module note on keeping one.
        #[repr(transparent)]
        #[derive(Clone, Copy, Debug, PartialEq, Eq)]
        pub struct $name {
            record: AxWord,
            _thread: $crate::NotThreadSafe,
        }

        impl AxCallback for $name {
            const ARITY: usize = $arity;

            #[inline]
            unsafe fn from_raw(record: AxWord) -> Self {
                Self {
                    record,
                    _thread: core::marker::PhantomData,
                }
            }

            #[inline]
            fn as_word(self) -> AxWord {
                self.record
            }
        }

        impl $name {
            /// The record word, for [`axiom_retain`] / [`axiom_release`].
            #[inline]
            pub fn as_word(self) -> AxWord {
                self.record
            }
        }
    };
}

ax_fn!(AxFn1, 1, "An Axiom `(-> Int Int)` value: one argument.");
ax_fn!(
    AxFn2,
    2,
    "An Axiom `(-> Int Int Int)` value: two arguments, applied one at a time."
);
ax_fn!(
    AxFn3,
    3,
    "An Axiom `(-> Int Int Int Int)` value: three arguments, applied one at a time."
);

impl AxFn1 {
    /// Call the Axiom function with `a`.
    #[inline]
    pub fn call(self, a: AxWord) -> AxWord {
        // SAFETY: the `from_raw` contract - a live closure record - is
        // what the generated shim promised when it built this value
        // from an argument word the Axiom caller typed as an arrow.
        unsafe { apply_one(self.record, a) }
    }
}

impl AxFn2 {
    /// Call the Axiom function with `a` and `b`: the first application
    /// answers the inner link, the second the value; the link is then
    /// released.
    #[inline]
    pub fn call(self, a: AxWord, b: AxWord) -> AxWord {
        // SAFETY: as `AxFn1::call`; the link is a fresh record the
        // first step answered, owned here and released after use.
        unsafe {
            let link = apply_one(self.record, a);
            let v = apply_one(link, b);
            axiom_release(link);
            v
        }
    }
}

impl AxFn3 {
    /// Call the Axiom function with `a`, `b` and `c`, one application
    /// per argument; the two intermediate links are released.
    #[inline]
    pub fn call(self, a: AxWord, b: AxWord, c: AxWord) -> AxWord {
        // SAFETY: as `AxFn2::call`, one link deeper.
        unsafe {
            let link1 = apply_one(self.record, a);
            let link2 = apply_one(link1, b);
            let v = apply_one(link2, c);
            axiom_release(link2);
            axiom_release(link1);
            v
        }
    }
}

// ---------------------------------------------------------------------
// Vectors
// ---------------------------------------------------------------------

/// The three words an Axiom `Vec` handle points at.
///
/// Verified against `stdlib/Vec.ax`'s module note: word 0 the length,
/// word 1 the capacity, word 2 the address of `cap` words of element
/// storage. Elements are machine words - an `Int` each when the Axiom
/// side built the vector from integers, which is the only shape a
/// `&[i64]` parameter promises.
#[repr(C)]
#[derive(Debug)]
pub struct AxVecRepr {
    /// Live elements.
    pub len: i64,
    /// Elements the data block can hold.
    pub cap: i64,
    /// The element storage: `cap` words, `len` of them live.
    pub data: *const i64,
}

/// A borrowed view of an Axiom `Vec` of words.
///
/// The lifetime is the call, as for [`AxStr`]: the vector's header is
/// stable (only its data block moves, on growth), but the Axiom caller
/// owns it and may grow or release it the moment the shim returns.
#[derive(Clone, Copy)]
pub struct AxVec<'a> {
    raw: AxWord,
    _life: PhantomData<&'a [i64]>,
    _thread: NotThreadSafe,
}

impl<'a> AxVec<'a> {
    /// # Safety
    /// `raw` must be a live Axiom `Vec` handle for all of `'a`.
    #[inline]
    pub const unsafe fn from_raw(raw: AxWord) -> Self {
        Self {
            raw,
            _life: PhantomData,
            _thread: PhantomData,
        }
    }

    /// The raw handle, for `axiom_retain` / `axiom_release` and for
    /// handing the same `Vec` back to Axiom. Borrowing it takes no
    /// share.
    #[inline]
    pub fn as_word(self) -> AxWord {
        self.raw
    }

    #[inline]
    fn repr(self) -> &'a AxVecRepr {
        // SAFETY: the from_raw contract.
        unsafe { &*(self.raw as *const AxVecRepr) }
    }

    /// Live elements, not capacity. Clamped at 0: the header's `len` is
    /// a signed word and a negative one would otherwise become an
    /// enormous `usize` and a slice length no allocation can satisfy.
    #[inline]
    pub fn len(self) -> usize {
        self.repr().len.max(0) as usize
    }

    /// Whether the vector has no live elements. A vector with capacity
    /// and nothing in it is empty; the data block's size is not the
    /// question.
    #[inline]
    pub fn is_empty(self) -> bool {
        self.len() == 0
    }

    /// The live words, borrowed. Zero-copy: this is the data block Axiom
    /// holds, not a duplicate.
    #[inline]
    pub fn as_slice(self) -> &'a [i64] {
        let r = self.repr();
        if r.len <= 0 || r.data.is_null() {
            return &[];
        }
        // SAFETY: Axiom guarantees `len` readable words at `data`.
        unsafe { slice::from_raw_parts(r.data, r.len as usize) }
    }

    /// The live words, borrowed mutably: what a `&mut [i64]` parameter
    /// writes through. Still the data block Axiom holds, so a write is
    /// visible to the Axiom caller the moment the shim returns - that
    /// is the point. The vector's length and capacity are not touched.
    ///
    /// # Safety
    /// No other view of the vector's words may be live. A shim runs on
    /// the thread that called into it and touches no Axiom value from
    /// any other - that is what [`NotThreadSafe`] enforces - so the only
    /// way to alias is to pass the same `Vec` twice in one call.
    #[inline]
    pub unsafe fn as_mut_slice(self) -> &'a mut [i64] {
        unsafe {
            // SAFETY: this block rests on two promises: the `from_raw`
            // contract (a live `Vec` handle for all of `'a`) and this
            // function's own `# Safety` (no other view of the words is
            // live); the raw construction below is annotated separately.
            let r = self.repr();
            if r.len <= 0 || r.data.is_null() {
                return &mut [];
            }
            // SAFETY: the data block is `cap` words of Axiom heap memory
            // the caller owns, `len` of them live; the from_raw contract
            // plus this function's own makes the exclusive borrow sound.
            slice::from_raw_parts_mut(r.data as *mut i64, r.len as usize)
        }
    }
}
