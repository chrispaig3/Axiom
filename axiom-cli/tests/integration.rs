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
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n(fn main (+ 1 doesNotExist))\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    assert!(stderr(&out).contains("AX3001"), "stderr: {}", stderr(&out));
}

/// End-to-end regression test for the ADT/pattern-matching work: a
/// recursive `data List` built and summed via real heap-boxed
/// constructors and real branching `match` codegen, not just type-checked.
#[test]
fn run_executes_recursive_adt_pattern_matching_correctly() {
    let dir = scratch_dir("run-list-sum");
    write_source(
        &dir,
        "main.ax",
        "(data List (a)\n  (Nil)\n  (Cons a (List a)))\n\
         (:: sum (-> (List Int) Int))\n\
          (fn (sum lst)\n  (match lst\n    ((Nil) 0)\n    ((Cons h t) (+ h (sum t)))))\n\
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
          (fn (fromMaybe default val)\n  (match val\n    ((Nothing) default)\n    ((Just x) x)))\n\
         (:: main Int)\n\
         (fn main (+ (fromMaybe 100 (Nothing)) (fromMaybe 100 (Just 42))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(142), "stderr: {}", stderr(&out));
}

#[test]
fn non_exhaustive_match_is_rejected_before_codegen() {
    let dir = scratch_dir("check-non-exhaustive");
    write_source(
        &dir,
        "main.ax",
        "(data Maybe (a)\n  (Nothing)\n  (Just a))\n\
         (:: main Int)\n\
          (fn main (match (Just 1) ((Just x) x)))\n",
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
    write_source(
        &dir,
        "main.ax",
        "(import Nope.Nowhere)\n(:: main Int)\n(fn main 0)\n",
    );
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
    write_source(
        &dir,
        "Broken.ax",
        "(:: broken (-> Int Int))\n(fn (broken x) (+ x undefinedThing))\n",
    );
    write_source(
        &dir,
        "main.ax",
        "(import Broken)\n(:: main Int)\n(fn main (broken 1))\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    let err = stderr(&out);
    assert!(
        err.contains("Broken.ax"),
        "stderr should mention Broken.ax: {}",
        err
    );
    assert!(
        !err.contains("main.ax:"),
        "stderr should not attribute the error to main.ax: {}",
        err
    );
}

/// AXSYM output for a simple program: spot-check the grammar rather than
/// the full line (exact column numbers are covered well enough by the
/// unit-level `SymbolFact` rendering, if any existed at that layer - this
/// is about the CLI wiring actually producing sane end-to-end output).
#[test]
fn symbols_command_lists_declared_functions_and_omits_builtins_by_default() {
    let dir = scratch_dir("symbols-basic");
    write_source(
        &dir,
        "main.ax",
        "(:: add (-> Int Int Int))\n(fn (add x y) (+ x y))\n(:: main Int)\n(fn main 0)\n",
    );

    let out = run_axiom(&["--diagnostic-format=ai", "symbols", "main.ax"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    let text = stdout(&out);
    assert!(
        text.lines().any(|l| l.starts_with("F add ")),
        "missing `add`: {}",
        text
    );
    assert!(
        !text.lines().any(|l| l.starts_with("F + ")),
        "builtins should be omitted by default: {}",
        text
    );

    let out_with_builtins = run_axiom(
        &["--diagnostic-format=ai", "symbols", "main.ax", "--builtins"],
        &dir,
    );
    assert!(out_with_builtins.status.success());
    assert!(stdout(&out_with_builtins)
        .lines()
        .any(|l| l.starts_with("F + ")));
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
    let out = Command::new(axiom_bin())
        .args(["explain", "AX3005"])
        .output()
        .unwrap();
    assert!(out.status.success());
    assert!(stdout(&out).contains("non-exhaustive"));
}

#[test]
fn explain_reports_an_unknown_code_as_an_error_not_a_panic() {
    let out = Command::new(axiom_bin())
        .args(["explain", "AX9999"])
        .output()
        .unwrap();
    assert!(!out.status.success());
}

/// AXDL spot-check: duplicate definition produces a secondary span (`^`)
/// in the single-line AI output.
#[test]
fn axdl_duplicate_definition_has_secondary_span() {
    let dir = scratch_dir("axdl-duplicate");
    write_source(
        &dir,
        "main.ax",
        "(:: helper (-> Int Int))\n(fn (helper x) x)\n(:: helper (-> Int Int))\n(fn (helper x) (+ x 1))\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    let err = stderr(&out);
    let line = err.lines().find(|l| l.contains("AX3006")).unwrap();
    assert!(line.starts_with("E AX3006 "), "line: {}", line);
    assert!(line.contains(" ^"), "secondary span missing: {}", line);
}

/// AXDL spot-check: non-exhaustive match includes a help suggestion.
#[test]
fn axdl_non_exhaustive_has_help() {
    let dir = scratch_dir("axdl-nonexhaustive");
    write_source(
        &dir,
        "main.ax",
        "(data Bool (True) (False))\n(:: main Int)\n(fn main (match true ((True) 1)))\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    let err = stderr(&out);
    let line = err.lines().find(|l| l.contains("AX3005")).unwrap();
    assert!(line.contains(" ?\""), "help prefix missing: {}", line);
}

/// AXDL spot-check: a type mismatch is rendered in one line with no extra
/// newlines.
#[test]
fn axdl_type_mismatch_is_dense_single_line() {
    let dir = scratch_dir("axdl-typemismatch");
    write_source(
        &dir,
        "main.ax",
        r#"#| multi-byte: héllo |#
(:: main Int)
(fn main (if true 1 "no"))
"#,
    );
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    let err = stderr(&out);
    let lines: Vec<&str> = err.lines().collect();
    let first = lines.iter().find(|l| l.starts_with('E')).unwrap();
    assert!(first.contains("AX3004"), "line: {}", first);
    assert!(first.contains(" type-mismatch "), "line: {}", first);
}

/// AXDL spot-check: JSON Lines output contains char_start/char_end (character
/// offsets, not byte offsets) and is one object per line.
#[test]
fn axdl_json_format_is_valid_json_lines() {
    let dir = scratch_dir("axdl-json");
    write_source(
        &dir,
        "main.ax",
        r#"#| héllo |#
(:: main Int)
(fn main (+ 1 u))
"#,
    );
    let out = run_axiom(&["--diagnostic-format=json", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    let err = stderr(&out);
    let lines: Vec<&str> = err.lines().collect();
    assert!(!lines.is_empty());
    let line = lines[0];
    // Validate JSON-like structure via string checks.
    assert!(line.contains("\"code\":\"AX3001\""));
    assert!(line.contains("\"severity\":\"error\""));
    assert!(line.contains("\"char_start\":"));
    assert!(line.contains("\"char_end\":"));
}

/// AXSYM spot-check: a program that declares every visible symbol kind should
/// produce one line per kind.
#[test]
fn axsym_reports_all_declaration_kinds() {
    let dir = scratch_dir("axsym-all-kinds");
    write_source(
        &dir,
        "main.ax",
        r#"(foreign printf :: (-> String Int) = "printf")
(data Maybe (a) (Nothing) (Just a))
(struct Point (x : Int) (y : Int))
(type StringList () = [String])
(trait (Eq a))
"#,
    );
    let out = run_axiom(&["--diagnostic-format=ai", "symbols", "main.ax"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    let text = stdout(&out);
    assert!(text.lines().any(|l| l.starts_with("X printf ")));
    assert!(text.lines().any(|l| l.starts_with("D Maybe ")));
    assert!(text.lines().any(|l| l.starts_with("C Nothing ")));
    assert!(text.lines().any(|l| l.starts_with("C Just ")));
    assert!(text.lines().any(|l| l.starts_with("S Point ")));
    assert!(text.lines().any(|l| l.starts_with("A StringList ")));
    assert!(text.lines().any(|l| l.starts_with("T Eq ")));
}

/// AXSYM spot-check: struct field shapes and layout attributes appear as
/// `#fields=` and `#repr=C`/`#packed`/`#align=N` metadata.
#[test]
fn axsym_struct_metadata_includes_fields_and_repr() {
    let dir = scratch_dir("axsym-struct-meta");
    write_source(
        &dir,
        "main.ax",
        "(struct Point packed (x : Int) (y : Int))\n(:: main Int)\n(fn main 0)\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "symbols", "main.ax"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    let text = stdout(&out);
    assert!(text.contains("#fields=x:Int,y:Int"), "text: {}", text);
    assert!(text.contains("#packed"), "text: {}", text);
}

/// AXSYM spot-check: data type constructors list under `#ctors=`.
#[test]
fn axsym_data_type_ctors_metadata() {
    let dir = scratch_dir("axsym-ctors");
    write_source(
        &dir,
        "main.ax",
        "(data Ordering (LT) (EQ) (GT))\n(:: main Int)\n(fn main 0)\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "symbols", "main.ax"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    let text = stdout(&out);
    assert!(text.contains("D Ordering "));
    assert!(text.contains("#ctors=LT,EQ,GT"), "text: {}", text);
}

/// AXSYM spot-check: type alias `#tyvars` is present when there are params and
/// absent when there are none.
#[test]
fn axsym_type_alias_tyvars_metadata() {
    let dir = scratch_dir("axsym-tyvars");
    write_source(
        &dir,
        "main.ax",
        "(type StringList () = [String])\n(type Pair (a b) = (a b))\n(:: main Int)\n(fn main 0)\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "symbols", "main.ax"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    let text = stdout(&out);
    assert!(text.contains("A StringList "), "text: {}", text);
    assert!(text.contains("A Pair "), "text: {}", text);
    assert!(text.contains("#tyvars=a,b"), "text: {}", text);
    assert!(
        !text
            .lines()
            .any(|l| l.starts_with("A StringList") && l.contains("#tyvars")),
        "StringList should not have #tyvars: {}",
        text
    );
}

/// AXSYM spot-check: JSON Lines output is valid JSON per symbol.
#[test]
fn axsym_json_format_is_one_object_per_line() {
    let dir = scratch_dir("axsym-json");
    write_source(
        &dir,
        "main.ax",
        "(data Maybe (a) (Nothing) (Just a))\n(:: main Int)\n(fn main 0)\n",
    );
    let out = run_axiom(&["--diagnostic-format=json", "symbols", "main.ax"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    for line in stdout(&out).lines() {
        if line.trim().is_empty() {
            continue;
        }
        assert!(line.starts_with('{'), "not JSON: {}", line);
        assert!(line.contains("\"kind\""), "missing kind: {}", line);
        assert!(line.contains("\"name\""), "missing name: {}", line);
        assert!(line.contains("\"type\""), "missing type: {}", line);
    }
}

/// AXSYM spot-check: multi-file attribution shows the true declaring file.
#[test]
fn axsym_multi_file_attribution() {
    let dir = scratch_dir("axsym-multifile");
    std::fs::create_dir_all(dir.join("Math")).unwrap();
    write_source(
        &dir,
        "Math/Ops.ax",
        "(:: square (-> Int Int))\n(fn (square x) (* x x))\n",
    );
    write_source(
        &dir,
        "main.ax",
        "(import Math.Ops)\n(:: main Int)\n(fn main (square 5))\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "symbols", "main.ax"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    let text = stdout(&out);
    assert!(
        text.lines().any(|l| l.starts_with("F square Math/Ops.ax:")),
        "square should be attributed to Math/Ops.ax: {}",
        text
    );
    assert!(
        text.lines().any(|l| l.starts_with("F main main.ax:")),
        "main should be attributed to main.ax: {}",
        text
    );
}

/// AXSYM spot-check: `--builtins` lists the fixed operator set in all formats.
#[test]
fn axsym_builtins_appear_when_requested() {
    let dir = scratch_dir("axsym-builtins");
    write_source(&dir, "main.ax", "(:: main Int)\n(fn main 0)\n");
    let out = run_axiom(
        &["--diagnostic-format=ai", "symbols", "main.ax", "--builtins"],
        &dir,
    );
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    let text = stdout(&out);
    assert!(text.lines().any(|l| l.starts_with("F + ")));
    assert!(text.lines().any(|l| l.starts_with("F == ")));
}

/// AXSYM spot-check: human format prints an aligned table with file locations.
#[test]
fn axsym_human_format_is_an_aligned_table() {
    let dir = scratch_dir("axsym-human");
    write_source(
        &dir,
        "main.ax",
        "(:: add (-> Int Int Int))\n(fn (add x y) (+ x y))\n",
    );
    let out = run_axiom(&["symbols", "main.ax"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    let text = stdout(&out);
    assert!(text.contains("Fn"), "missing kind column: {}", text);
    assert!(text.contains("add"), "missing name column: {}", text);
    assert!(text.contains("main.ax:1:5"), "missing location: {}", text);
}

/// AXDL spot-check: machine-applicable suggestion (`~>`) appears in AI output
/// for an undefined variable with a "did you mean" suggestion.
#[test]
fn axdl_undefined_variable_includes_machine_applicable_fix() {
    let dir = scratch_dir("axdl-suggestion");
    write_source(
        &dir,
        "main.ax",
        "(:: helper (-> Int Int))\n(fn (helper x) x)\n(:: main Int)\n(fn main (helpr 5))\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    let err = stderr(&out);
    let line = err.lines().find(|l| l.contains("AX3001")).unwrap();
    assert!(line.contains("~>"), "machine fix missing: {}", line);
    assert!(line.contains("helper"), "suggestion missing: {}", line);
}

/// Option type: exhaustive match over Some/None works correctly.
#[test]
fn run_option_pattern_matching_works() {
    let dir = scratch_dir("run-option");
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n(fn main (match (Some 42) ((Some x) x) ((None) 0)))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(42), "stderr: {}", stderr(&out));
}

/// Option type: non-exhaustive match is rejected with a helpful diagnostic.
#[test]
fn non_exhaustive_option_match_is_rejected() {
    let dir = scratch_dir("check-option-nonexhaustive");
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n(fn main (match (Some 1) ((Some x) x)))\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    let err = stderr(&out);
    assert!(
        err.contains("AX3005"),
        "missing non-exhaustive code: {}",
        err
    );
}

// ---------------------------------------------------------------
// Removed constructs
//
// `union` and `region` are gone from the grammar but still reserved
// in the lexer, so that source written against an older Axiom gets an
// explanation instead of a misleading downstream error. These tests pin
// that behaviour: the interesting assertion is not that the program is
// rejected - it would be rejected either way - but that it is rejected
// with `AX2004` naming the construct, rather than `AX3001` naming a
// symbol the author never wrote.
// ---------------------------------------------------------------

#[test]
fn union_declaration_reports_its_removal() {
    let dir = scratch_dir("removed-union-decl");
    write_source(
        &dir,
        "main.ax",
        "(union Value (asInt : Int) (asFloat : F64))\n(:: main Int)\n(fn main 0)\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    let err = stderr(&out);
    assert!(err.contains("AX2004"), "stderr: {}", err);
    assert!(err.contains("removed-construct"), "stderr: {}", err);
    // The report must point at the replacement, since that is the only
    // part a reader can act on.
    assert!(err.contains("data"), "stderr: {}", err);
}

#[test]
fn region_expression_reports_its_removal() {
    let dir = scratch_dir("removed-region-expr");
    write_source(&dir, "main.ax", "(:: main Int)\n(fn main (region r 0))\n");
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success());
    let err = stderr(&out);
    assert!(err.contains("AX2004"), "stderr: {}", err);
    assert!(err.contains("region"), "stderr: {}", err);
}

#[test]
fn explain_documents_the_removed_construct_code() {
    let dir = scratch_dir("removed-explain");
    let out = run_axiom(&["explain", "AX2004"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    let text = stdout(&out);
    assert!(text.contains("union"), "stdout: {}", text);
    assert!(text.contains("region"), "stdout: {}", text);
}

// ---------------------------------------------------------------
// Intermediate file hygiene
//
// `build` writes an `.ll`, an optional `.opt.ll`, and an `.o` on the way
// to an executable. Only the `.o` used to be cleaned up, so `axiom run`
// left an `axiom_temp_output.ll` in whatever directory it was invoked
// from - it deleted the executable it made but had nothing to delete the
// IR with. These tests pin the whole set, because the leak was invisible
// in every existing test: they all run in scratch directories nobody
// looks at afterwards.
// ---------------------------------------------------------------

/// Names of every entry in `dir`, sorted, for comparing against an
/// expected set. Sorted so the assertion does not depend on readdir order.
fn dir_entries(dir: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(dir)
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    names
}

#[test]
fn run_leaves_no_intermediate_files_behind() {
    let dir = scratch_dir("hygiene-run");
    write_source(&dir, "main.ax", "(:: main Int)\n(fn (main) 0)\n");
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    assert_eq!(
        dir_entries(&dir),
        vec!["main.ax".to_string()],
        "`run` should leave only the source it was given"
    );
}

#[test]
fn build_leaves_only_the_executable() {
    let dir = scratch_dir("hygiene-build");
    write_source(&dir, "main.ax", "(:: main Int)\n(fn (main) 0)\n");
    let out = run_axiom(&["build", "--input", "main.ax", "--output", "prog"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    assert_eq!(
        dir_entries(&dir),
        vec!["main.ax".to_string(), "prog".to_string()],
    );
}

#[test]
fn build_at_higher_opt_does_not_leak_the_optimised_ir() {
    // `run_llvm_opt` returns a different path at `--opt 1` and above, so
    // this level leaks a file the default level does not. Skipped rather
    // than failed when `opt` is absent, since the compiler treats a
    // missing `opt` as a warning and proceeds without it - in which case
    // there is no `.opt.ll` to leak and nothing to assert.
    let dir = scratch_dir("hygiene-opt");
    write_source(&dir, "main.ax", "(:: main Int)\n(fn (main) 0)\n");
    let out = run_axiom(
        &[
            "build", "--input", "main.ax", "--output", "prog", "--opt", "2",
        ],
        &dir,
    );
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    assert_eq!(
        dir_entries(&dir),
        vec!["main.ax".to_string(), "prog".to_string()],
    );
}

#[test]
fn build_with_emit_llvm_keeps_the_ir() {
    // The complement of the tests above: `--emit-llvm` is the way to ask
    // for the IR, and it has to actually produce a file. Before the
    // cleanup change the flag only controlled whether a line was printed,
    // so this asserts the flag now means something.
    let dir = scratch_dir("hygiene-emit");
    write_source(&dir, "main.ax", "(:: main Int)\n(fn (main) 0)\n");
    let out = run_axiom(
        &[
            "build",
            "--input",
            "main.ax",
            "--output",
            "prog",
            "--emit-llvm",
        ],
        &dir,
    );
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    assert_eq!(
        dir_entries(&dir),
        vec![
            "main.ax".to_string(),
            "prog".to_string(),
            "prog.ll".to_string(),
        ],
    );
}

// ---------------------------------------------------------------
// Formatter data loss
//
// `fmt` regenerates source from the syntax tree, and comments never reach
// the tree - the lexer discards them so no later stage has to skip them.
// Formatting a commented file therefore used to delete every comment in
// it, in place, with a success message. These tests pin the refusal.
// ---------------------------------------------------------------

#[test]
fn fmt_refuses_to_rewrite_a_file_with_comments() {
    let dir = scratch_dir("fmt-comments");
    let source = "; a comment worth keeping\n(:: main Int)\n(fn (main) 0)\n";
    let path = write_source(&dir, "main.ax", source);

    let out = run_axiom(&["fmt", "main.ax"], &dir);
    assert!(
        !out.status.success(),
        "fmt should refuse; stdout: {}",
        stdout(&out)
    );

    // The refusal is only worth anything if the file really is untouched.
    assert_eq!(
        std::fs::read_to_string(&path).unwrap(),
        source,
        "fmt must not modify a file it cannot round-trip"
    );
}

#[test]
fn fmt_still_formats_a_file_without_comments() {
    // The guard must not disable the formatter outright, or it would be a
    // regression dressed up as a fix.
    let dir = scratch_dir("fmt-no-comments");
    let path = write_source(&dir, "main.ax", "(:: main Int)\n(fn   (main)   0)\n");

    let out = run_axiom(&["fmt", "main.ax"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));

    let formatted = std::fs::read_to_string(&path).unwrap();
    assert!(
        formatted.contains("main"),
        "formatted output lost the program: {}",
        formatted
    );
}

#[test]
fn fmt_counts_axtags_as_preserved() {
    // AXTAGs look like comments but are real tokens and do survive
    // formatting, so they must not trigger the refusal - otherwise every
    // file carrying agent metadata becomes unformattable.
    let dir = scratch_dir("fmt-axtag");
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n;@axiom:pure\n(fn (main) 0)\n",
    );
    let out = run_axiom(&["fmt", "main.ax"], &dir);
    assert!(
        out.status.success(),
        "an AXTAG is not a discarded comment; stderr: {}",
        stderr(&out)
    );
}
