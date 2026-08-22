//! The FFI mode that keeps Axiom freestanding.
//!
//! Measured on darwin-aarch64: an Axiom executable linked against this
//! crate has an **empty** `nm -u`. The same program linked against a
//! `std` crate imports 188 symbols, 18 of them on
//! `scripts/check-freestanding.sh`'s forbidden list. Both work; only
//! this one leaves the freestanding property intact, so
//! `check-ffi.sh` can hold it to the strictest tier.
//!
//! Everything that makes this possible - the global allocator wired to
//! **Axiom's own allocator**, the panic handler, the personality stub
//! and the memory intrinsics the precompiled `alloc` rlib references -
//! comes from `axiom-ffi`'s `nostd-runtime` feature (see
//! `axiom_ffi::nostd_runtime`). This file is only the exported surface.
//! The allocator puts Rust's allocations inside Axiom's arena, where
//! they are counted by the high-water mark and reclaimed by an arena
//! reset along with everything else; `dealloc` is a no-op, which is the
//! one constraint to know about.

#![no_std]

extern crate alloc;

use axiom_ffi::axiom_export;

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

