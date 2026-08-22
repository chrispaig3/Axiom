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
    // Callbacks carry their arrow type on the raw item and the wrapper,
    // and pass straight through.
    assert!(fresh.contains("(mapTwice :: (-> (-> Int Int) Int Int) (symbol \"axffi_map_twice\"))"));
    assert!(fresh.contains(
        "(combineRaw :: (-> (-> Int Int Int) (-> Int Int Int Int) Int Int Int) (symbol \"axffi_combine\"))"
    ));
    assert!(fresh.contains("(pub :: combine (-> (-> Int Int Int) (-> Int Int Int Int) Int (Option Int)))"));
    assert!(fresh.contains("(__st (combineRaw f g seed __c))"));
    // A `Vec<i64>` / `Vec<String>` return is an `Int` handle built by
    // Ffi.ax and freed on the Rust side; a `&[i64]` parameter is `Int`.
    assert!(fresh.contains("(pub :: evens (-> Int Int))"));
    assert!(fresh.contains("(__v (ffiWordsToVec __p __n))"));
    assert!(fresh.contains("(ffiFreeWords __p __n)"));
    assert!(fresh.contains("(pub :: pieces (-> String Int))"));
    assert!(fresh.contains("(__v (ffiStrsToVec __p __n))"));
    assert!(fresh.contains("(ffiFreeStrList __p __n)"));
    assert!(fresh.contains("(total :: (-> Int Int) (symbol \"axffi_total\"))"));
    assert!(fresh.contains("(pub :: tryEvens (-> Int (Result Int String)))"));
    assert!(fresh.contains("(pub :: maybePieces (-> String (Option Int)))"));
    // A record is a `data` with one positional field per Rust field,
    // declared beside the opaque types; a record parameter is
    // destructured into one raw argument per field (the raw item
    // lists the field types flattened), a record result is rebuilt
    // from an `ffiCellNewN ARITY` cell with each word read as its
    // field's type.
    assert!(fresh.contains("(pub data Pixel\n  (Pixel Int Float Bool))"));
    assert!(fresh.contains("(pixelBrightnessRaw :: (-> Int Float Bool Float Float) (symbol \"axffi_pixel_brightness\"))"));
    assert!(fresh.contains("(pub :: pixelBrightness (-> Pixel Float Float))"));
    assert!(fresh.contains("((Pixel __f0 __f1 __f2)\n      (let ((__r (pixelBrightnessRaw __f0 __f1 __f2 gain)))"));
    assert!(fresh.contains("(pixelOffRaw :: (-> Int Int) (symbol \"axffi_pixel_off\"))"));
    assert!(fresh.contains("(pub :: pixelOff Pixel)"));
    assert!(fresh.contains(
        "(__c (ffiCellNewN 3))\n    (__st (pixelOffRaw __c))\n    (__w0 (ffiCellWord __c 0))\n    \
         (__w1 (cast Float (ffiCellWord __c 1)))\n    (__w2 (cast Bool (ffiCellWord __c 2)))\n    \
         (__r (Pixel __w0 __w1 __w2))"
    ));
    // Two records and a handle in one call: fields numbered across the
    // signature, the raw item flattened, the Option rebuilt from the cell.
    assert!(fresh.contains("(pixelMixRaw :: (-> Int Float Bool Int Float Bool Foreign Int Int) (symbol \"axffi_pixel_mix\"))"));
    assert!(fresh.contains("(pub :: pixelMix (-> Pixel Pixel Thing (Option Pixel)))"));
    assert!(fresh.contains("((Pixel __f3 __f4 __f5)"));
    assert!(fresh.contains("(Some __r)"));
    assert!(fresh.contains("(pub :: pixelParse (-> String (Result Pixel String)))"));
    assert!(fresh.contains("(Ok __r)"));
    // Slices over the other scalars and `&[&str]` are `Int`; a
    // `Vec<bool>` result is the unchanged words path; the element
    // note names each.
    assert!(fresh.contains("(mean :: (-> Int Int Float) (symbol \"axffi_mean\"))"));
    assert!(fresh.contains("(concatRaw :: (-> Int Int Int) (symbol \"axffi_concat\"))"));
    assert!(fresh.contains("(pub :: parity (-> Int Int))"));
    assert!(fresh.contains(";   `mean` reads `xs` as a Vec of Float bits (f64);"));
    assert!(fresh.contains(";   `mean` reads `weights` as a Vec of u16 (each word range-checked);"));
    assert!(fresh.contains(";   `parity` answers a Vec of Bool (0/1);"));
    assert!(fresh.contains(";   `concat` reads `parts` as a Vec of String;"));
    // `char` is `Char` on the raw item, `u64` is `Int`; a `Char`
    // payload and field are cast from the word.
    assert!(fresh.contains("(nextChar :: (-> Char Char) (symbol \"axffi_next_char\"))"));
    assert!(fresh.contains("(wrapU64 :: (-> Int Int) (symbol \"axffi_wrap_u64\"))"));
    assert!(fresh.contains("(pub :: charsOf (-> String Int))"));
    assert!(fresh.contains(";   `charsOf` answers a Vec of Char (code points);"));
    assert!(fresh.contains(";   `fromChars` reads `cs` as a Vec of Char (code points);"));
    assert!(fresh.contains("(pub :: maybeChar (-> Char (Option Char)))"));
    assert!(fresh.contains("(__ch (cast Char __p))"));
    assert!(fresh.contains("(Some __ch)"));
    assert!(fresh.contains("(pub data Glyph\n  (Glyph Char Int))"));
    assert!(fresh.contains("(__w0 (cast Char (ffiCellWord __c 0)))\n    (__w1 (ffiCellWord __c 1))\n    (__r (Glyph __w0 __w1))"));
    // Records in Vecs: the module's own loops, the flattened argument,
    // the rebuild over `vecWithCapacity`, the `n * ARITY` free.
    assert!(fresh.contains("(import Vec)"));
    assert!(fresh.contains("(:: __pixelFromWords (-> Int Int Int Int Int))"));
    assert!(fresh.contains(
        "(fn (__pixelFromWords __v __p __n __i)\n  (if (>= __i __n)\n    __v\n    (let (\n      \
         (__w0 (ffiWordAt __p (* __i 3)))\n      (__w1 (cast Float (ffiWordAt __p (+ (* __i 3) 1))))\n      \
         (__w2 (cast Bool (ffiWordAt __p (+ (* __i 3) 2))))\n    )\n      {\n        \
         (vecPush __v (Pixel __w0 __w1 __w2))\n        (__pixelFromWords __v __p __n (+ __i 1))"
    ));
    assert!(fresh.contains("(:: __pixelToWords (-> Int Int Int Int))"));
    assert!(fresh.contains(
        "(fn (__pixelToWords __ps __w __i)\n  (if (>= __i (vecLen __ps))\n    __w\n    \
         (match (vecGet __ps __i)\n      ((Pixel __f0 __f1 __f2)\n        {\n          \
         (vecPush __w __f0)\n          (vecPush __w __f1)\n          (vecPush __w __f2)\n          \
         (__pixelToWords __ps __w (+ __i 1))"
    ));
    assert!(fresh.contains("(pixelsDimRaw :: (-> Int Int Int Int) (symbol \"axffi_pixels_dim\"))"));
    assert!(fresh.contains("(pub :: pixelsDim (-> Int Int Int))"));
    assert!(fresh.contains("(__a0 (__pixelToWords ps (vecWithCapacity (* (vecLen ps) 3)) 0))"));
    assert!(fresh.contains("(__st (pixelsDimRaw __a0 by __c))"));
    assert!(fresh.contains("(__v (__pixelFromWords (vecWithCapacity __n) __p __n 0))"));
    assert!(fresh.contains("(ffiFreeWords __p (* __n 3))"));
    assert!(fresh.contains("(pub :: pixelsTry (-> Int (Result Int String)))"));
    assert!(fresh.contains("(pub :: glyphsMaybe (-> Int (Option Int)))"));
    assert!(fresh.contains("(__glyphFromWords (vecWithCapacity __n) __p __n 0)"));
    assert!(!fresh.contains("__glyphToWords"));
    assert!(fresh.contains(";   `pixelsDim` reads `ps` as a Vec of Pixel (flattened to 3 words per element for the call);"));
    assert!(fresh.contains(";   `pixelsDim` answers a Vec of Pixel;"));
    // Nested Vecs and the mutable slice.
    assert!(fresh.contains("(pub :: grid (-> Int Int))"));
    assert!(fresh.contains("(__v (ffiWordListsToVec __p __n))"));
    assert!(fresh.contains("(ffiFreeWordLists __p __n)"));
    assert!(fresh.contains("(sumRows :: (-> Int Int) (symbol \"axffi_sum_rows\"))"));
    assert!(fresh.contains(";   `sumRows` reads `rows` as a Vec of Vecs of Int;"));
    assert!(fresh.contains(";   `tryGridF64` answers a Vec of Vecs of Float bits (f64);"));
    assert!(fresh.contains("(doubleInPlace :: (-> Int Int) (symbol \"axffi_double_in_place\"))"));
    assert!(fresh.contains(";   `doubleInPlace` writes `xs` in place, a Vec of Int;"));
    // Nested fallible results: the constructors nest, status 2 is the
    // middle branch.
    assert!(fresh.contains("(pub :: maybeParse (-> String (Result (Option Int) String)))"));
    assert!(fresh.contains("(Ok (Some __p))"));
    assert!(fresh.contains("(if (== __st 2)\n        {\n          (ffiCellFree __c)\n          (Ok None)\n        }"));
    assert!(fresh.contains("(pub :: lookup (-> Int (Option (Result Thing String))))"));
    assert!(fresh.contains("(Some (Ok (Thing (ffiHandleNew __p thingDropFn))))"));
    assert!(fresh.contains("(Some (Err __m))"));
    assert!(fresh.contains("(pub :: maybePixelTry (-> Int (Result (Option Pixel) String)))"));
    assert!(fresh.contains("(Ok (Some __r))"));
    assert!(fresh.contains("(pub :: piecesLookup (-> String (Option (Result Int String))))"));
    assert!(fresh.contains("(Some (Ok __v))"));
    // Everything shared comes from Ffi.ax: the record loops are the
    // only module-local declarations, and they are private.
    assert!(!fresh.contains("ffiSliceToStr"));
    assert!(!fresh.contains("axffi_free_bytes"));
    assert!(!fresh.contains("(pub :: __"));
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
fn unrecorded_by_value_is_an_error() {
    let err = axiom_bindgen::generate(&fixture("unrecorded/src"), "axiom_unrecorded").unwrap_err();
    assert!(err.0.contains("`Plain` crosses as a record but no `#[axiom_record]` declaration"), "{err}");
    assert!(err.0.contains("`plain_n`"), "{err}");
}

#[test]
fn unrecorded_in_vec_is_an_error() {
    let err = axiom_bindgen::generate(&fixture("unrecorded_vec/src"), "axiom_unrecorded").unwrap_err();
    assert!(err.0.contains("`Plain` crosses as a record but no `#[axiom_record]` declaration"), "{err}");
    assert!(err.0.contains("`plains`"), "{err}");
}

#[test]
fn vec_of_opaque_is_an_error() {
    let err = axiom_bindgen::generate(&fixture("vec_opaque/src"), "axiom_vec_opaque").unwrap_err();
    assert!(err.0.contains("a `Vec` of handles does not cross"), "{err}");
    assert!(err.0.contains("`things`"), "{err}");
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
