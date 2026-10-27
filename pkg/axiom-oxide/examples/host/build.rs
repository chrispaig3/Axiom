//! Link the Axiom archive the host calls into.
//!
//! `$AXIOM_HOST_ARCHIVE_DIR` names a directory holding
//! `libaxiom_hostlib.a`, written by
//!
//! ```sh
//! axiom build --input tests/ffi/host/hostlib.ax \
//!             --output $AXIOM_HOST_ARCHIVE_DIR/libaxiom_hostlib.a --emit-staticlib
//! ```
//!
//! The FFI gate (`scripts/check-ffi.sh`) builds it and sets the
//! variable before `cargo run -p axiom-host`. When the variable is unset
//! or the archive is missing, the crate still COMPILES - this script
//! warns and emits no link line - and the final link fails with
//! `addTwo`, `shout` and `Str$strAlloc` undefined, which is the honest
//! outcome: there is nothing to call.

use std::env;
use std::path::PathBuf;

const ARCHIVE: &str = "libaxiom_hostlib.a";
const VAR: &str = "AXIOM_HOST_ARCHIVE_DIR";

fn main() {
    println!("cargo:rerun-if-env-changed={VAR}");
    let Some(dir) = env::var_os(VAR).map(PathBuf::from) else {
        println!(
            "cargo:warning=axiom-host: ${VAR} is not set; the binary will not link. Build \
             tests/ffi/host/hostlib.ax with `axiom build --emit-staticlib` into a directory \
             and name it in ${VAR}."
        );
        return;
    };
    let archive = dir.join(ARCHIVE);
    println!("cargo:rerun-if-changed={}", archive.display());
    if !archive.is_file() {
        println!(
            "cargo:warning=axiom-host: {} holds no {ARCHIVE}; the binary will not link. Write \
             it with `axiom build --input tests/ffi/host/hostlib.ax --output {} \
             --emit-staticlib`.",
            dir.display(),
            archive.display()
        );
        return;
    }
    println!("cargo:rustc-link-search=native={}", dir.display());
    println!("cargo:rustc-link-lib=static=axiom_hostlib");
}
