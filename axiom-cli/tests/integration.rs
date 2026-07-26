//! End-to-end tests against the real `axiom` binary: write a `.ax` file to
//! a scratch directory, run a subcommand against it, and assert on exit
//! code / stdout / stderr. These are the only tests in the whole
//! workspace that exercise the *full* pipeline through to a native
//! executable and back (lexer -> parser -> sema -> IR -> LLVM -> `llc` ->
//! `cc` -> a real process exit code), which is exactly the level every
//! other crate's unit tests intentionally stop short of.
//!
//! Requires `llc` and `cc` on `PATH` (same requirement `axiom build`
//! itself has) - if either is missing, `run`/`build` tests will fail with
//! a clear `AX4003` toolchain error rather than something confusing.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn axiom_bin() -> &'static str {
    env!("CARGO_BIN_EXE_axiom")
}

/// A scratch directory under the system temp dir, unique to one test
/// (`std::process::id()` + the test's own chosen name), so tests can run
/// concurrently (the default for `cargo test`) without racing on the same
/// `.ax` file or output binary. Deliberately *not* under this crate's own
/// `target/` (even though that's `.gitignore`d too): a nested
/// `axiom-cli/target/` is a second, separate Cargo target directory from
/// the workspace's real one at the repo root, not a subdirectory of it,
/// and there's no reason for these tests to create one.
fn scratch_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir()
        .join("axiom-integration-tests")
        .join(format!("{}-{}", name, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn write_source(dir: &Path, filename: &str, source: &str) -> PathBuf {
    let path = dir.join(filename);
    std::fs::write(&path, source).unwrap();
    path
}

fn run_axiom(args: &[&str], dir: &Path) -> Output {
    Command::new(axiom_bin())
        .args(args)
        .current_dir(dir)
        .output()
        .expect("failed to spawn axiom binary")
}

fn stdout(out: &Output) -> String {
    String::from_utf8_lossy(&out.stdout).into_owned()
}

fn stderr(out: &Output) -> String {
    String::from_utf8_lossy(&out.stderr).into_owned()
}

#[test]
fn check_accepts_a_well_typed_program() {
    let dir = scratch_dir("check-ok");
    write_source(&dir, "main.ax", "(:: main Int)\n(fn main (+ 1 2))\n");
    let out = run_axiom(&["check", "main.ax"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    assert!(stdout(&out).contains("OK"));
}

#[test]
fn check_rejects_an_undefined_variable_with_the_right_code() {
    let dir = scratch_dir("check-undefined-var");
    write_source(&dir, "main.ax", "(:: main Int)\n(fn main (+ 1 doesNotExist))\n");
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    assert!(stderr(&out).contains("AX3001"), "stderr: {}", stderr(&out));
}

/// End-to-end regression test for the ADT/pattern-matching work: a
/// recursive `data List` built and summed via real heap-boxed
/// constructors and real branching `case` codegen, not just type-checked.
#[test]
fn run_executes_recursive_adt_pattern_matching_correctly() {
    let dir = scratch_dir("run-list-sum");
    write_source(
        &dir,
        "main.ax",
        "(data List (a)\n  (Nil)\n  (Cons a (List a)))\n\
         (:: sum (-> (List Int) Int))\n\
         (fn (sum lst)\n  (case lst\n    ((Nil) 0)\n    ((Cons h t) (+ h (sum t)))))\n\
         (:: main Int)\n\
         (fn main (sum (Cons 1 (Cons 2 (Cons 3 (Nil))))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(6), "stderr: {}", stderr(&out));
}

/// Same idea for `Maybe`, specifically exercising a *nullary* constructor
/// (`Nothing`) alongside a constructor with a field (`Just x`), since the
/// two are boxed identically but constructed/matched slightly differently
/// in the generator.
#[test]
fn run_executes_maybe_pattern_matching_correctly() {
    let dir = scratch_dir("run-maybe");
    write_source(
        &dir,
        "main.ax",
        "(data Maybe (a)\n  (Nothing)\n  (Just a))\n\
         (:: fromMaybe (-> Int (Maybe Int) Int))\n\
         (fn (fromMaybe default val)\n  (case val\n    ((Nothing) default)\n    ((Just x) x)))\n\
         (:: main Int)\n\
         (fn main (+ (fromMaybe 100 (Nothing)) (fromMaybe 100 (Just 42))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(142), "stderr: {}", stderr(&out));
}

#[test]
fn non_exhaustive_case_is_rejected_before_codegen() {
    let dir = scratch_dir("check-non-exhaustive");
    write_source(
        &dir,
        "main.ax",
        "(data Maybe (a)\n  (Nothing)\n  (Just a))\n\
         (:: main Int)\n\
         (fn main (case (Just 1) ((Just x) x)))\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    assert!(stderr(&out).contains("AX3005"), "stderr: {}", stderr(&out));
}

/// End-to-end regression test for the module-import system: a real
/// two-file program, resolved, merged, and actually executed.
#[test]
fn run_resolves_and_executes_a_multi_file_import() {
    let dir = scratch_dir("run-imports");
    std::fs::create_dir_all(dir.join("Math")).unwrap();
    write_source(
        &dir,
        "Math/Ops.ax",
        "(:: square (-> Int Int))\n(fn (square x) (* x x))\n",
    );
    write_source(
        &dir,
        "main.ax",
        "(import Math.Ops (square))\n(:: main Int)\n(fn main (square 5))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(25), "stderr: {}", stderr(&out));
}

/// An import naming a file that doesn't exist is a clean `AX5001`
/// diagnostic, not a panic or an opaque I/O error.
#[test]
fn missing_import_is_a_clean_diagnostic_not_a_panic() {
    let dir = scratch_dir("check-missing-import");
    write_source(&dir, "main.ax", "(import Nope.Nowhere)\n(:: main Int)\n(fn main 0)\n");
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    assert!(stderr(&out).contains("AX5001"), "stderr: {}", stderr(&out));
}

/// A diagnostic that originates in an *imported* file must be attributed
/// to that file's own path, not the entry file's - the whole point of
/// `FileRegistry`.
#[test]
fn diagnostic_in_an_imported_file_is_attributed_to_that_file() {
    let dir = scratch_dir("check-cross-file-diag");
    write_source(&dir, "Broken.ax", "(:: broken (-> Int Int))\n(fn (broken x) (+ x undefinedThing))\n");
    write_source(&dir, "main.ax", "(import Broken)\n(:: main Int)\n(fn main (broken 1))\n");
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    let err = stderr(&out);
    assert!(err.contains("Broken.ax"), "stderr should mention Broken.ax: {}", err);
    assert!(!err.contains("main.ax:"), "stderr should not attribute the error to main.ax: {}", err);
}

/// AXSYM output for a simple program: spot-check the grammar rather than
/// the full line (exact column numbers are covered well enough by the
/// unit-level `SymbolFact` rendering, if any existed at that layer - this
/// is about the CLI wiring actually producing sane end-to-end output).
#[test]
fn symbols_command_lists_declared_functions_and_omits_builtins_by_default() {
    let dir = scratch_dir("symbols-basic");
    write_source(&dir, "main.ax", "(:: add (-> Int Int Int))\n(fn (add x y) (+ x y))\n(:: main Int)\n(fn main 0)\n");

    let out = run_axiom(&["--diagnostic-format=ai", "symbols", "main.ax"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    let text = stdout(&out);
    assert!(text.lines().any(|l| l.starts_with("F add ")), "missing `add`: {}", text);
    assert!(!text.lines().any(|l| l.starts_with("F + ")), "builtins should be omitted by default: {}", text);

    let out_with_builtins = run_axiom(&["--diagnostic-format=ai", "symbols", "main.ax", "--builtins"], &dir);
    assert!(out_with_builtins.status.success());
    assert!(stdout(&out_with_builtins).lines().any(|l| l.starts_with("F + ")));
}

#[test]
fn fmt_check_flags_an_unformatted_file() {
    let dir = scratch_dir("fmt-check");
    // Deliberately inconsistent whitespace.
    write_source(&dir, "main.ax", "(::   main Int)\n(fn main    0)\n");
    let out = run_axiom(&["fmt", "main.ax", "--check"], &dir);
    assert!(!out.status.success());
}

#[test]
fn explain_prints_details_for_a_known_code() {
    let out = Command::new(axiom_bin()).args(["explain", "AX3005"]).output().unwrap();
    assert!(out.status.success());
    assert!(stdout(&out).contains("non-exhaustive"));
}

#[test]
fn explain_reports_an_unknown_code_as_an_error_not_a_panic() {
    let out = Command::new(axiom_bin()).args(["explain", "AX9999"]).output().unwrap();
    assert!(!out.status.success());
}
