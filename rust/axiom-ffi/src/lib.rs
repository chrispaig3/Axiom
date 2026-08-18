//! Write Rust that Axiom can call.
//!
//! ```ignore
//! use axiom_ffi::axiom_export;
//!
//! #[axiom_export]
//! pub fn sha256_hex(input: &str) -> String {
//!     use sha2::{Digest, Sha256};
//!     let d = Sha256::digest(input.as_bytes());
//!     d.iter().map(|b| format!("{b:02x}")).collect()
//! }
//! ```
//!
//! That generates `axffi_sha256_hex`, which `axiom-bindgen` turns into
//! the Axiom declaration
//!
//! ```text
//! (extern (sha256Hex (input : String)) String
//!   #:symbol "axffi_sha256_hex"
//!   #:lib    "demo")
//! ```
//!
//! # The two build modes, measured
//!
//! | mode | `nm -u` on the linked Axiom executable | freestanding |
//! |---|---|---|
//! | `no_std` + `panic = "abort"` | **empty** | preserved |
//! | `std` | 188 symbols, 14 forbidden | relaxed, gated by allowlist |
//!
//! Both link and both run. The difference is only whether
//! `scripts/check-freestanding.sh`'s blanket ban still applies or the
//! MM-FFI-5 allowlist gate takes over.
//!
//! # Panics
//!
//! `extern "C"` aborts on unwind (Rust 1.81+), and Axiom has no
//! unwinding at all — its emitter never writes an `invoke` or a
//! `landingpad`. So a panic that reaches the boundary aborts the
//! process. Set `panic = "abort"` to make that explicit and to drop the
//! landing pads from the archive. If you want a panic to become an
//! Axiom-visible error instead, return `Result` and catch inside your
//! own function; the generated shim turns `Err` into a status word.

#![cfg_attr(not(feature = "std"), no_std)]

extern crate alloc;

pub use axiom_abi::{
    axiom_alloc, axiom_release, axiom_retain, AxBytes, AxOpaque, AxOutCell, AxStatus, AxStr,
    AxStrRepr, AxWord, AX_ERR, AX_OK, AX_PANIC,
};
pub use axiom_ffi_macros::axiom_export;

/// Implementation details the generated shims call. Not a stable API.
#[doc(hidden)]
pub mod __private {
    use alloc::boxed::Box;
    use alloc::vec::Vec;

    /// Hand owned bytes to Axiom as a `(ptr, len)` pair.
    ///
    /// Axiom's generated glue copies them into a real `strAlloc` block
    /// and then calls [`axffi_free_bytes`]. Rust keeps ownership until
    /// that free, which is why this leaks deliberately rather than
    /// returning a borrow of a temporary.
    pub fn leak_bytes(v: Vec<u8>) -> (i64, i64) {
        let boxed: Box<[u8]> = v.into_boxed_slice();
        let len = boxed.len() as i64;
        let p = Box::into_raw(boxed) as *mut u8;
        (p as i64, len)
    }

    /// Move a Rust value onto the heap and hand Axiom the word.
    pub fn leak_opaque<T>(v: T) -> i64 {
        Box::into_raw(Box::new(v)) as i64
    }

    /// Render an error into owned bytes for the out-cell.
    pub fn error_bytes<E: core::fmt::Display>(e: &E) -> (i64, i64) {
        #[cfg(feature = "std")]
        {
            leak_bytes(std::format!("{e}").into_bytes())
        }
        #[cfg(not(feature = "std"))]
        {
            use alloc::string::ToString;
            leak_bytes(e.to_string().into_bytes())
        }
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
/// Both sides embed it and the link-time gate compares them. It is what
/// turns "the Rust crate was rebuilt with a different type mapping" from
/// a silent memory-corruption bug into a refused build.
#[no_mangle]
pub extern "C" fn axffi_abi_version() -> i64 {
    ABI_VERSION
}

/// Bump this on ANY change to a wire representation: the word size, the
/// `String` layout, the out-cell shape, or the status encoding.
pub const ABI_VERSION: i64 = 1;
