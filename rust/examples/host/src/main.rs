//! A Rust program calling Axiom: the other direction, worked.
//!
//! `tests/ffi/host/hostlib.ax` declares `addTwo :: (-> Int Int Int)`
//! and `shout :: (-> String String)`, with no `main`. Built with
//! `axiom build --emit-staticlib` it is an archive whose `pub fn`s are
//! C symbols under their own names, and `build.rs` links it.
//!
//! # The symbols this host relies on
//!
//! | symbol | defined by | used for |
//! |---|---|---|
//! | `addTwo` | `hostlib.ax` (`pub fn`, entry file: unmangled) | the Int call |
//! | `shout` | `hostlib.ax` | the String call |
//! | `Str$strAlloc` | `stdlib/Str.ax`, mangled `Module$name` | `AxString::from_str` allocating the argument |
//! | `axiom_release` | the emitted runtime | `AxString`'s drop giving a share back |
//!
//! `axiom_retain` and `axiom_alloc` are in the archive too (every
//! emitted module exports them); this host needs neither, because it
//! keeps nothing past the calls and builds every block through Axiom's
//! own constructors. There is no init call: the allocator initialises
//! on first use.

use axiom_ffi::host::AxString;

extern "C" {
    /// `(pub :: addTwo (-> Int Int Int))`.
    fn addTwo(a: i64, b: i64) -> i64;
    /// `(pub :: shout (-> String String))`: the argument is a String
    /// word (borrowed for the call), the result a String word the caller
    /// owns.
    fn shout(s: i64) -> i64;
}

fn main() {
    // Plain words: the cheapest crossing, no marshalling either way.
    // SAFETY: the archive defines `addTwo` with exactly this signature.
    let sum = unsafe { addTwo(40, 2) };

    // A String argument is built by Axiom's own `strAlloc` (a real
    // block, a real header) and passed borrowed; the answer is a fresh
    // String the host now owns and releases when `reply` drops.
    let hello = AxString::from_str("hello");
    // SAFETY: `hello` is live for the call; `shout` answers an owned
    // String word, adopted exactly once.
    let reply = unsafe { AxString::from_owned(shout(hello.as_word())) };
    let text = reply.as_str().unwrap_or("<not utf-8>");

    println!("host: addTwo={sum} shout={text}");
}
