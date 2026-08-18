//! The FFI mode that keeps Axiom freestanding.
//!
//! Measured on darwin-aarch64: an Axiom executable linked against this
//! crate has an **empty** `nm -u`. The same program linked against a
//! `std` crate imports 188 symbols, 14 of them on
//! `scripts/check-freestanding.sh`'s forbidden list. Both work; only
//! this one leaves the freestanding property intact, so
//! `check-ffi.sh` can hold it to the strictest tier.
//!
//! The trick is that Rust's `alloc` is wired to **Axiom's own
//! allocator**. That is not merely a way to avoid `malloc`: it puts
//! Rust's allocations inside Axiom's arena, where they are counted by
//! the high-water mark and reclaimed by an arena reset along with
//! everything else. `MM-FFI-3` says memory that did not come from
//! `axiom_alloc` is outside the arena; this makes that clause vacuous
//! for a no_std crate, which is the strongest position available.

#![no_std]

extern crate alloc;

use axiom_ffi::axiom_export;
use core::alloc::{GlobalAlloc, Layout};

/// Forward Rust's allocations to Axiom's bump allocator.
///
/// `dealloc` is deliberately a no-op. Axiom's allocator has no
/// per-block free — reclamation is by arena reset (`MM-ALLOC-13`), and
/// `axiom_release` is ARC bookkeeping over blocks with Axiom headers,
/// which a Rust allocation does not have. So Rust memory here lives
/// until the enclosing arena is reset.
///
/// That is a real constraint, stated rather than hidden: a no_std shim
/// that allocates in an unbounded loop grows the arena. For a shim that
/// computes and returns, which is the shape the FFI is for, it is
/// exactly right and costs nothing.
struct AxiomAlloc;

unsafe impl GlobalAlloc for AxiomAlloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        // Every axiom_alloc block is 16-byte aligned (invariant I5) and
        // reads as zero (I6). A stricter alignment request cannot be
        // served, so refuse rather than return a misaligned block.
        if layout.align() > 16 {
            return core::ptr::null_mut();
        }
        axiom_ffi::axiom_alloc(layout.size() as i64) as *mut u8
    }

    unsafe fn dealloc(&self, _ptr: *mut u8, _layout: Layout) {}
}

#[global_allocator]
static ALLOC: AxiomAlloc = AxiomAlloc;

/// The personality routine the precompiled `alloc` rlib references.
///
/// Found by linking: even with `panic = "abort"` in the profile, the
/// `alloc` crate shipped in the Rust sysroot was itself built with
/// unwinding, so its object files carry a reference to
/// `rust_eh_personality`. `panic = "abort"` governs *our* crates, not
/// the precompiled sysroot.
///
/// Two ways out. This stub, which is stable and costs one empty
/// function — sound precisely because nothing can unwind: Axiom emits
/// no `invoke` and no landing pad, and every shim is `extern "C"`,
/// which aborts on unwind. Or `-Z build-std=core,alloc` with
/// `panic_abort`, which rebuilds the sysroot and removes the reference
/// entirely but needs nightly. The gate takes the stable route.
#[no_mangle]
pub extern "C" fn rust_eh_personality() {}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    // Axiom has no unwinding and no landing pads; its emitter never
    // writes an `invoke`. A panic that reaches here cannot be reported
    // through the boundary, so it terminates. `panic = "abort"` in the
    // workspace profile means this is rarely reached.
    loop {
        core::hint::spin_loop();
    }
}

// ---------------------------------------------------------------------
// The exported surface. Same attribute, same generated shim shapes.
// ---------------------------------------------------------------------

/// FNV-1a. A real hash, no dependencies, and a fair stand-in for what
/// binding a `no_std` crate like `sha2` looks like.
#[axiom_export]
pub fn fnv1a(data: &[u8]) -> i64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in data {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100_0000_01b3);
    }
    (h & 0x7fff_ffff_ffff_ffff) as i64
}

/// Allocating in `core` + `alloc`, through Axiom's arena.
#[axiom_export]
pub fn repeat_byte(b: i64, n: i64) -> alloc::vec::Vec<u8> {
    let n = n.clamp(0, 1 << 20) as usize;
    alloc::vec![b as u8; n]
}

/// Diagnostic probes: what does Rust actually see for an Axiom String?
#[axiom_export]
pub fn probe_len(data: &[u8]) -> i64 {
    data.len() as i64
}

#[axiom_export]
pub fn probe_first(data: &[u8]) -> i64 {
    if data.is_empty() { -1 } else { data[0] as i64 }
}

// ---------------------------------------------------------------------
// The memory intrinsics `alloc` needs.
//
// Measured: a core-only `no_std` staticlib links into an Axiom
// executable with an EMPTY `nm -u`. Adding `extern crate alloc` pulls in
// seven undefined symbols - `memcpy`, `memset`, `memmove`, `memcmp`,
// `bzero`, `strlen` and `_Unwind_Resume` - because the precompiled
// sysroot `alloc` rlib calls the C memory intrinsics that LLVM assumes
// exist on every target.
//
// Axiom cannot import them: `check-freestanding.sh` forbids exactly
// these names, and rightly, since the whole claim is that generated code
// links no C library. So the crate DEFINES them. They are a dozen lines
// of byte loops, they keep `nm -u` empty, and they are the same thing
// `compiler_builtins`' `mem` feature would supply if the sysroot were
// rebuilt with `-Z build-std` (which needs nightly, so the gate does not
// depend on it).
//
// `#[no_mangle]` here is safe precisely because this crate is `no_std`:
// nothing else in the link is defining them.
// ---------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn memcpy(dst: *mut u8, src: *const u8, n: usize) -> *mut u8 {
    let mut i = 0;
    while i < n {
        *dst.add(i) = *src.add(i);
        i += 1;
    }
    dst
}

#[no_mangle]
pub unsafe extern "C" fn memmove(dst: *mut u8, src: *const u8, n: usize) -> *mut u8 {
    if (dst as usize) < (src as usize) {
        return memcpy(dst, src, n);
    }
    let mut i = n;
    while i > 0 {
        i -= 1;
        *dst.add(i) = *src.add(i);
    }
    dst
}

#[no_mangle]
pub unsafe extern "C" fn memset(dst: *mut u8, c: i32, n: usize) -> *mut u8 {
    let mut i = 0;
    while i < n {
        *dst.add(i) = c as u8;
        i += 1;
    }
    dst
}

#[no_mangle]
pub unsafe extern "C" fn memcmp(a: *const u8, b: *const u8, n: usize) -> i32 {
    let mut i = 0;
    while i < n {
        let (x, y) = (*a.add(i), *b.add(i));
        if x != y {
            return x as i32 - y as i32;
        }
        i += 1;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn bzero(dst: *mut u8, n: usize) {
    memset(dst, 0, n);
}

#[no_mangle]
pub unsafe extern "C" fn strlen(s: *const u8) -> usize {
    let mut n = 0;
    while *s.add(n) != 0 {
        n += 1;
    }
    n
}

/// Unreachable: nothing unwinds. See `rust_eh_personality`.
#[no_mangle]
pub extern "C" fn _Unwind_Resume() -> ! {
    loop {
        core::hint::spin_loop();
    }
}
