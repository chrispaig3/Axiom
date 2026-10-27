//! Deliberately leaky: this crate reaches for `std::env`, which drags
//! `getenv` into the link, and its `axiom-allow.txt` does not list it.
//!
//! `scripts/check-ffi.sh` builds it and REQUIRES the allowlist check to
//! fail. If it ever passes, the gate has stopped checking.

use axiom_ffi::axiom_export;

#[axiom_export]
pub fn home_len() -> i64 {
    // `std::env::var` is the point: it pulls `getenv`, which the
    // manifest beside this file deliberately omits.
    std::env::var("HOME").map(|v| v.len() as i64).unwrap_or(-1)
}
