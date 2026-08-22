//! The generator's output is pinned byte-for-byte.
//!
//! `fixtures/nested` covers every wrapper kind, `mod` recursion, the
//! `pub`-only rule, the attribute keys, a raw shim and a parameter
//! named `cell`; its expected module is checked in. The two example
//! crates are regenerated and compared with their committed modules,
//! which is the same check `scripts/check-ffi.sh` makes, here so
//! `cargo test` notices a stale module without the Axiom toolchain.
//!
//! Set `UPDATE_SNAPSHOTS=1` to rewrite the expected files after an
//! intended change to the generator - and then run `axiom fmt --check`
//! on them, which this test also does when a compiler is reachable
//! (`$AXIOM`, or the repository's `.axiom-bin/axiom`).

use std::path::{Path, PathBuf};
use std::process::Command;

fn manifest_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn fixture(name: &str) -> PathBuf {
    manifest_dir().join("tests/fixtures").join(name)
}

/// Compare `fresh` with the file at `expected`, rewriting it under
/// `UPDATE_SNAPSHOTS=1`.
fn assert_snapshot(fresh: &str, expected: &Path) {
    if std::env::var_os("UPDATE_SNAPSHOTS").is_some() {
        std::fs::write(expected, fresh).unwrap();
        return;
    }
    let committed = std::fs::read_to_string(expected)
        .unwrap_or_else(|e| panic!("{}: {e} (UPDATE_SNAPSHOTS=1 writes it)", expected.display()));
    if committed != fresh {
        let first = committed
            .lines()
            .zip(fresh.lines())
            .position(|(a, b)| a != b)
            .map(|n| n + 1)
            .unwrap_or(committed.lines().count().min(fresh.lines().count()) + 1);
        panic!(
            "{} differs from a fresh generation (first difference at line {first});\n\
             regenerate with UPDATE_SNAPSHOTS=1 cargo test -p axiom-bindgen\n\n---- fresh ----\n{fresh}",
            expected.display()
        );
    }
}

/// The Axiom compiler, if one is reachable (`$AXIOM`, the repository's
/// `.axiom-bin/axiom`, or `axiom` on PATH); the formatter check is
/// skipped otherwise so the test suite does not need the toolchain.
fn axiom() -> Option<PathBuf> {
    if let Some(p) = std::env::var_os("AXIOM") {
        return Some(PathBuf::from(p));
    }
    let repo = manifest_dir().join("../../.axiom-bin/axiom");
    if repo.is_file() {
        return Some(repo);
    }
    let on_path = Command::new("axiom").arg("--version").output().ok()?;
    on_path.status.success().then(|| PathBuf::from("axiom"))
}

fn assert_fmt_clean(text: &str, name: &str) {
    let Some(axiom) = axiom() else { return };
    let dir = std::env::temp_dir().join(format!("axiom-bindgen-fmt-{}-{name}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join(format!("{name}.ax"));
    std::fs::write(&file, text).unwrap();
    let out = Command::new(&axiom).arg("fmt").arg("--check").arg(&file).output().unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert!(
        out.status.success(),
        "`axiom fmt --check` rejects the generated {name}.ax:\n{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn nested_fixture_matches_snapshot() {
    let fresh = axiom_bindgen::generate(&fixture("nested/src"), "axiom_nested").unwrap();
    assert_snapshot(&fresh, &fixture("nested/expected/Nested.ax"));
    assert_fmt_clean(&fresh, "Nested");
}

#[test]
fn nested_fixture_shape() {
    let fresh = axiom_bindgen::generate(&fixture("nested/src"), "axiom_nested").unwrap();
    // Recursion into `mod`: both nested exports are bound.
    assert!(fresh.contains("(nestedAdd :: (-> Int Int Int) (symbol \"axffi_nested_add\"))"));
    assert!(fresh.contains("(deepest :: (-> Bool Bool) (symbol \"axffi_deepest\"))"));
    // Only `pub` functions are exported.
    assert!(!fresh.contains("hidden"));
    // The symbol override and the raw shim.
    assert!(fresh.contains("(symbol \"custom_symbol\")"));
    assert!(fresh.contains("(peek :: (-> Foreign Int Int) (symbol \"axffi_peek\"))"));
    // A parameter named `cell` is not shadowed: the wrapper's own locals
    // are `__`-prefixed and the call passes the parameter first.
    assert!(fresh.contains("(pub fn (echo cell)"));
    assert!(fresh.contains("(__st (echoRaw cell __c))"));
    // One data type per opaque type, with the overridden stem.
    assert!(fresh.contains("(pub data Thing\n  (Thing Handle))"));
    assert!(fresh.contains("(widgetDropFn :: Int (symbol \"axffi_widget_v2_drop_fn\"))"));
    // Option and Result wrappers.
    assert!(fresh.contains("(pub :: check (-> Bool (Option Bool)))"));
    assert!(fresh.contains("(pub :: thingTry (-> Int (Result Thing String)))"));
    assert!(fresh.contains("(Ok (Thing (ffiHandleNew __p thingDropFn)))"));
    // Everything shared comes from Ffi.ax: no module-local helper.
    assert!(!fresh.contains("ffiSliceToStr"));
    assert!(!fresh.contains("axffi_free_bytes"));
    assert!(fresh.starts_with("; GENERATED by axiom-bindgen from the `axiom_nested` crate. Do not edit.\n(import Ffi)\n"));
}

#[test]
fn example_modules_are_fresh() {
    let examples = manifest_dir().join("../examples");
    for (crate_dir, lib, module) in [
        ("demo", "axiom_demo", "Demo"),
        ("nostd", "axiom_nostd", "Hash"),
    ] {
        let fresh = axiom_bindgen::generate(&examples.join(crate_dir).join("src"), lib).unwrap();
        assert_snapshot(&fresh, &examples.join(crate_dir).join("axiom").join(format!("{module}.ax")));
        assert_fmt_clean(&fresh, module);
    }
}

#[test]
fn camel_case_collision_is_an_error() {
    let err = axiom_bindgen::generate(&fixture("collision/src"), "axiom_collision").unwrap_err();
    assert!(err.0.contains("`fooBar` is generated twice"), "{err}");
    assert!(err.0.contains("`foo_bar`") && err.0.contains("`fooBar`"), "{err}");
}

#[test]
fn unmarked_opaque_is_an_error() {
    let err = axiom_bindgen::generate(&fixture("unmarked/src"), "axiom_unmarked").unwrap_err();
    assert!(err.0.contains("`Plain` crosses the boundary as an opaque handle"), "{err}");
    assert!(err.0.contains("#[axiom_opaque]"), "{err}");
}

#[test]
fn cli_help_check_and_module() {
    let bin = env!("CARGO_BIN_EXE_axiom-bindgen");
    let help = Command::new(bin).arg("--help").output().unwrap();
    assert!(help.status.success());
    assert!(String::from_utf8_lossy(&help.stdout).contains("--check <file>"));

    let unknown = Command::new(bin).arg("--bogus").output().unwrap();
    assert_eq!(unknown.status.code(), Some(2));

    let src = fixture("nested/src");
    let expected = fixture("nested/expected/Nested.ax");
    let ok = Command::new(bin)
        .args(["--src", src.to_str().unwrap(), "--lib", "axiom_nested", "--module", "Nested"])
        .arg("--check")
        .arg(&expected)
        .output()
        .unwrap();
    assert_eq!(ok.status.code(), Some(0), "{}", String::from_utf8_lossy(&ok.stderr));

    // A differing file: exit 1 and the first differing line named.
    let differs = Command::new(bin)
        .args(["--src", src.to_str().unwrap(), "--lib", "axiom_other"])
        .arg("--check")
        .arg(&expected)
        .output()
        .unwrap();
    assert_eq!(differs.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&differs.stderr).contains("line 1:"));

    // `--module` must agree with the file name.
    let mismatch = Command::new(bin)
        .args(["--src", src.to_str().unwrap(), "--lib", "axiom_nested", "--module", "Other"])
        .arg("--check")
        .arg(&expected)
        .output()
        .unwrap();
    assert_eq!(mismatch.status.code(), Some(2));

    // `-o <dir>` with `--module` writes `<dir>/<Module>.ax`.
    let dir = std::env::temp_dir().join(format!("axiom-bindgen-out-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let wrote = Command::new(bin)
        .args(["--src", src.to_str().unwrap(), "--lib", "axiom_nested", "--module", "Nested"])
        .arg("-o")
        .arg(&dir)
        .output()
        .unwrap();
    assert!(wrote.status.success());
    let written = std::fs::read_to_string(dir.join("Nested.ax")).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(written, std::fs::read_to_string(&expected).unwrap());
}
