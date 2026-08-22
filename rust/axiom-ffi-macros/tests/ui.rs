//! The attribute's surface, pinned: every accepted shape compiles (and
//! the shims answer what the protocol says when called directly), and
//! every refused shape fails with the message `tests/ui/fail/*.stderr`
//! records - the one that lists what IS supported.
//!
//! `TRYBUILD=overwrite cargo test -p axiom-ffi-macros` rewrites the
//! `.stderr` files after an intended change to a message.

#[test]
fn ui() {
    let t = trybuild::TestCases::new();
    t.pass("tests/ui/pass/*.rs");
    t.compile_fail("tests/ui/fail/*.rs");
}
