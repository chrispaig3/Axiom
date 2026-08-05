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

/// Drive the REPL by feeding it `input` on stdin.
///
/// `:quit` is appended so the session always terminates, and stdout is
/// captured whole - the REPL is line-oriented, so the transcript is the
/// only thing there is to assert on.
fn run_repl(input: &str) -> Output {
    use std::io::Write;
    use std::process::Stdio;

    let mut child = Command::new(axiom_bin())
        .arg("repl")
        .current_dir(scratch_dir("repl"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("failed to spawn axiom repl");

    child
        .stdin
        .as_mut()
        .expect("no stdin")
        .write_all(format!("{}\n:quit\n", input).as_bytes())
        .expect("failed to write to repl");

    child.wait_with_output().expect("repl did not exit")
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
        "(pub :: square (-> Int Int))\n(pub fn (square x) (* x x))\n",
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
        "(pub :: broken (-> Int Int))\n(pub fn (broken x) (+ x undefinedThing))\n",
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
        // `Bool` rather than `String` for the mismatched arm: a
        // `String` is a `Str` handle, one machine word, and so is
        // deliberately compatible with `Int`. The subject here is AXDL
        // density, so the fixture only has to be a mismatch that is
        // still a mismatch.
        r#"#| multi-byte: héllo |#
(:: main Int)
(fn main (if true 1 false))
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
        "(pub :: square (-> Int Int))\n(pub fn (square x) (* x x))\n",
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
// `fmt` regenerates source from the syntax tree, so anything that is not
// in the tree, or that the printer spells differently from the parser,
// is lost on the first invocation - silently, in place, with a success
// message. It had six such losses at once. Each test below pins one of
// them by asserting on the *content* of the rewritten file.
//
// That distinction is the point. The two tests that used to live here
// asserted only an exit status, which is why they stayed green while the
// formatter deleted the very thing one of them was named after.
// ---------------------------------------------------------------

/// Format `source` and return the rewritten file.
fn format_to_string(name: &str, source: &str) -> String {
    let dir = scratch_dir(name);
    let path = write_source(&dir, "main.ax", source);
    let out = run_axiom(&["fmt", "main.ax"], &dir);
    assert!(
        out.status.success(),
        "fmt failed on:\n{}\nstdout: {}\nstderr: {}",
        source,
        stdout(&out),
        stderr(&out)
    );
    std::fs::read_to_string(&path).unwrap()
}

#[test]
fn fmt_preserves_comments() {
    let formatted = format_to_string(
        "fmt-comments",
        "; a comment worth keeping\n(:: main Int)\n(fn (main) 0)\n",
    );
    assert!(
        formatted.contains("; a comment worth keeping"),
        "formatting deleted the comment: {}",
        formatted
    );
}

#[test]
fn fmt_preserves_a_trailing_comment_on_its_own_line() {
    // A comment that annotates the line it sits on must not migrate onto
    // a different construct. It used to be emitted after whatever was
    // formatted when it reached the front of the queue, which put an
    // annotation forty lines away from what it annotated.
    let formatted = format_to_string(
        "fmt-trailing",
        "(:: main Int)\n(fn (main) 0)  ; stays here\n(:: other Int)\n(fn (other) 1)\n",
    );
    let line = formatted
        .lines()
        .find(|l| l.contains("; stays here"))
        .unwrap_or_else(|| panic!("comment lost: {}", formatted));
    assert!(
        line.contains("main"),
        "trailing comment migrated off its construct: {}",
        line
    );
}

#[test]
fn fmt_preserves_block_comments() {
    // Block comments were not recorded by the lexer at all, so they were
    // invisible even to the guard that refused to format commented files.
    let formatted = format_to_string(
        "fmt-block-comment",
        "#| a block comment |#\n(:: main Int)\n(fn (main) 0)\n",
    );
    assert!(
        formatted.contains("a block comment"),
        "formatting deleted the block comment: {}",
        formatted
    );
}

#[test]
fn fmt_preserves_axtags() {
    // AXTAGs are real tokens rather than discarded comments, which meant
    // the comment guard never counted them - so they were deleted without
    // even the refusal that protected ordinary comments. They are
    // compiler-checked metadata, so losing one changes what the compiler
    // verifies about the file.
    let formatted = format_to_string("fmt-axtag", "(:: main Int)\n;@axiom:pure\n(fn (main) 0)\n");
    assert!(
        formatted.contains(";@axiom:pure"),
        "formatting deleted the AXTAG: {}",
        formatted
    );
}

#[test]
fn fmt_preserves_imports() {
    // Imports are parsed into `Module::imports`, and the formatter walked
    // only `Module::decls` - so every `(import ...)` line was dropped and
    // the formatted file no longer compiled.
    let formatted = format_to_string("fmt-imports", "(import IO)\n(:: main Int)\n(fn (main) 0)\n");
    assert!(
        formatted.contains("(import IO)"),
        "formatting deleted the import: {}",
        formatted
    );
}

#[test]
fn fmt_preserves_a_dotted_import_path() {
    let formatted = format_to_string(
        "fmt-dotted-import",
        "(import Sys.Platform)\n(:: main Int)\n(fn (main) 0)\n",
    );
    assert!(
        formatted.contains("(import Sys.Platform)"),
        "a dotted module path was split into separate segments: {}",
        formatted
    );
}

#[test]
fn fmt_preserves_pub() {
    // Dropping `pub` does not change how the file parses, so nothing
    // downstream complains - it just removes every name the module
    // exported, and importers fail against names still visibly present.
    let formatted = format_to_string("fmt-pub", "(pub :: main Int)\n(pub fn (main) 0)\n");
    assert_eq!(
        formatted.matches("pub").count(),
        2,
        "formatting dropped a `pub` marker: {}",
        formatted
    );
}

#[test]
fn fmt_preserves_nullary_constructor_patterns() {
    // `((Red) 1)` printed as `(Red 1)` is a *variable* pattern that binds
    // anything, so the first arm matched every value and every later arm
    // became unreachable. The program still compiled and still ran - it
    // just returned the first arm's answer for every input.
    let formatted = format_to_string(
        "fmt-nullary-pattern",
        "(data Color (Red) (Green))\n(:: f (-> Color Int))\n\
         (fn (f c)\n  (match c\n    ((Red) 1)\n    ((Green) 2)))\n",
    );
    assert!(
        formatted.contains("((Red) 1)"),
        "a nullary constructor pattern became a catch-all variable: {}",
        formatted
    );
}

#[test]
fn fmt_preserves_named_constructor_fields() {
    // Printing named fields through `field_types()` erased the names,
    // demoting a struct variant to a positional one - after which every
    // `s.r` and every `(Rect { w, h })` pattern failed to resolve.
    let formatted = format_to_string("fmt-named-fields", "(data Shape (Circle { r : Int }))\n");
    assert!(
        formatted.contains('{') && formatted.contains('r'),
        "named constructor fields were flattened to positional: {}",
        formatted
    );
}

#[test]
fn fmt_preserves_uncurried_signatures() {
    let formatted = format_to_string(
        "fmt-arrow",
        "(:: add (-> Int Int Int))\n(fn (add x y) (+ x y))\n",
    );
    assert!(
        formatted.contains("(-> Int Int Int)"),
        "the signature grew a level of currying: {}",
        formatted
    );
}

#[test]
fn fmt_preserves_string_escapes() {
    // The lexer stores the decoded value, so re-emitting it verbatim
    // turns a source `\\d` into the escape `\d`, which is not one - the
    // formatted file no longer lexes.
    let formatted = format_to_string("fmt-escapes", "(:: s Str)\n(fn (s) \"a\\\\d\\nb\")\n");
    assert!(
        formatted.contains("\\\\d") && formatted.contains("\\n"),
        "string escapes were not re-escaped: {}",
        formatted
    );
}

#[test]
fn fmt_emits_fn_rather_than_define() {
    let formatted = format_to_string("fmt-fn", "(:: main Int)\n(fn   (main)   0)\n");
    assert!(
        formatted.contains("(fn (main)") && !formatted.contains("define"),
        "formatting rewrote `fn` into the legacy `define` spelling: {}",
        formatted
    );
}

#[test]
fn fmt_is_idempotent() {
    let source = "; header\n(import IO)\n\n;@axiom:pure\n(pub :: main Int)\n\
                  (pub fn (main)\n  (let ((x 1))\n    x))\n";
    let once = format_to_string("fmt-idem-1", source);
    let twice = format_to_string("fmt-idem-2", &once);
    assert_eq!(once, twice, "formatting is not a fixed point");
}

// ---------------------------------------------------------------
// §1 prerequisite correctness regression tests
//
// These are the integration gates described in the P1 plan §1:
// each one exercises a correctness fix that, when absent, produces
// silently wrong code rather than a diagnostic. They run the full
// pipeline through to a native process so that silent miscompiles
// become visible as wrong exit codes.
// ---------------------------------------------------------------

/// §1.1: gen_lambda cursor restore — code after a lambda in the same
/// function body must emit into the outer function, not the lambda's
/// entry block. The `let` binding evaluates the lambda (calling
/// gen_lambda), then `(add1 41)` is evaluated — if the cursor is
/// corrupted, the Store/Ret for add1's IR lands in the lambda's blocks.
#[test]
fn lambda_cursor_restore_code_after_lambda_is_correct() {
    let dir = scratch_dir("lambda-cursor");
    write_source(
        &dir,
        "main.ax",
        "(:: add1 (-> Int Int))\n\
         (fn (add1 x) (+ x 1))\n\
         (:: main Int)\n\
         (fn (main)\n  (let ((_ (lambda (x) (+ x 1)))) (add1 41)))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(42), "stderr: {}", stderr(&out));
}

/// §1.3: Cast widening — casting from a narrower type to a wider type
/// must use zext/sext, not trunc.
#[test]
fn cast_widening_preserves_value() {
    let dir = scratch_dir("cast-widen");
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n\
         (fn (main) (cast I64 (cast I8 42)))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(42), "stderr: {}", stderr(&out));
}

/// §1.4: Nested PCon field offset — nested constructor patterns must
/// read fields at byte offset 8, not 1.
#[test]
fn nested_constructor_patterns_read_correct_offsets() {
    let dir = scratch_dir("nested-pcon-offset");
    write_source(
        &dir,
        "main.ax",
        "(data Inner (a) (IA a) (IB a))\n\
         (data Outer (a) (OA a (Inner a)) (OB (Inner a) a))\n\
         (:: main Int)\n\
         (fn (main)\n  (match (OA 1 (IA 2))\n    ((OA x (IA y)) (+ x y))\n    ((OA x (IB y)) (+ x y))\n    ((OB (IA y) x) (+ x y))\n    ((OB (IB y) x) (+ x y))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(3), "stderr: {}", stderr(&out));
}

/// §1.5: Match-failure defensive init — the match result alloca is
/// initialized to zero so a pathological fallthrough returns a
/// deterministic value instead of reading uninitialized memory.
#[test]
fn exhaustive_match_initializes_result_to_zero() {
    let dir = scratch_dir("match-result-init");
    write_source(
        &dir,
        "main.ax",
        "(data Maybe (a) (Nothing) (Just a))\n\
         (:: main Int)\n\
         (fn (main)\n  (match (Just 99) ((Just x) x) ((Nothing) 0)))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(99), "stderr: {}", stderr(&out));
}

/// §1.6: Argument evaluation order — curried application must
/// evaluate arguments left-to-right.
#[test]
fn argument_evaluation_is_left_to_right() {
    let dir = scratch_dir("eval-order");
    write_source(
        &dir,
        "main.ax",
        "(:: add2 (-> Int Int Int))\n\
         (fn (add2 a b) (+ a b))\n\
         (:: id (-> Int Int))\n\
         (fn (id x) x)\n\
         (:: main Int)\n\
         (fn (main) (add2 (id 3) (id 39)))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(42), "stderr: {}", stderr(&out));
}

/// §1.8: Unique alloca names — variable shadowing and match-arm
/// bindings must not collide on alloca names.
#[test]
fn alloca_names_are_unique_under_shadowing() {
    let dir = scratch_dir("alloca-shadow");
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n\
         (fn (main)\n  (let ((x 1)) (let ((x 2)) (+ x x))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(4), "stderr: {}", stderr(&out));
}

/// §1.4b: Nested PCon field offset — alternative exercise with
/// a simpler two-level tree matching.
#[test]
fn nested_constructor_matching_on_list_like_type() {
    let dir = scratch_dir("nested-con-list");
    write_source(
        &dir,
        "main.ax",
        "(data Tree (Leaf Int) (Node (Tree) (Tree)))\n\
         (:: sumTree (-> (Tree) Int))\n\
         (fn (sumTree t)\n  (match t\n    ((Leaf n) n)\n    ((Node l r) (+ (sumTree l) (sumTree r)))))\n\
         (:: main Int)\n\
         (fn (main) (sumTree (Node (Leaf 10) (Node (Leaf 20) (Leaf 12)))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(42), "stderr: {}", stderr(&out));
}

// ---------------------------------------------------------------
// §2.1 B2: Guaranteed tail calls
//
// Axiom has no loop construct; all iteration is recursion. Without
// tail-call optimisation, each recursive call costs a stack frame.
// These tests verify that a self-tail-call in tail position
// compiles to a branch rather than a call, so O(1) stack can
// handle O(N) iterations.
// ---------------------------------------------------------------

/// A tail-recursive sum over 10^6 steps completes without segfault.
#[test]
fn tail_call_summation_1m_iterations() {
    let dir = scratch_dir("tail-sum");
    write_source(
        &dir,
        "main.ax",
        "(:: sumTo (-> Int Int Int))\n\
         (fn (sumTo n acc)\n  (if (<= n 0) acc (sumTo (- n 1) (+ acc n))))\n\
         (:: main Int)\n\
         (fn (main) (sumTo 1000000 0))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert!(
        out.status.success() || out.status.code().is_some(),
        "must not segfault: {}",
        stderr(&out)
    );
}

/// Tail call works through EBegin — the last expression in a
/// sequence block is in tail position.
#[test]
fn tail_call_through_ebegin() {
    let dir = scratch_dir("tail-begin");
    write_source(
        &dir,
        "main.ax",
        "(:: countDown (-> Int Int))\n\
         (fn (countDown n)\n  { (+ 1 2) (if (<= n 0) 0 (countDown (- n 1))) })\n\
         (:: main Int)\n\
         (fn (main) (countDown 1000000))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(0), "stderr: {}", stderr(&out));
}

/// Tail call works through EMatch — each arm body is in tail position.
#[test]
fn tail_call_through_match() {
    let dir = scratch_dir("tail-match");
    write_source(
        &dir,
        "main.ax",
        "(data Tree (Leaf) (Node a))\n\
         (:: walk (-> (Tree) Int))\n\
         (fn (walk t)\n  (match t\n    ((Leaf) 0)\n    ((Node _) (walk (Leaf)))))\n\
         (:: main Int)\n\
         (fn (main) (walk (Node (Leaf))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(0), "stderr: {}", stderr(&out));
}

// ---------------------------------------------------------------
// §2.3 B1: Closures (function values)
//
// Function values (both top-level function references and inline
// lambdas) compile and run through a first-class closure
// representation with CallIndirect.
// ---------------------------------------------------------------

/// apply2 f x = f (f x) — the exit-criterion higher-order probe.
#[test]
fn apply2_composes_a_function_with_itself() {
    let dir = scratch_dir("b1-apply2");
    write_source(
        &dir,
        "main.ax",
        "(:: apply2 (-> (-> Int Int) Int Int))\n\
         (fn (apply2 f x) (f (f x)))\n\
         (:: add1 (-> Int Int))\n\
         (fn (add1 x) (+ x 1))\n\
         (:: main Int)\n\
         (fn (main) (apply2 add1 20))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(22), "stderr: {}", stderr(&out));
}

/// A lambda used as a first-class value: `(apply (lambda (x) (+ x 1)) 41)`.
#[test]
fn lambda_as_value_called_via_apply() {
    let dir = scratch_dir("b1-lambda-val");
    write_source(
        &dir,
        "main.ax",
        "(:: apply (-> (-> Int Int) Int Int))\n\
         (fn (apply f x) (f x))\n\
         (:: main Int)\n\
         (fn (main) (apply (lambda (x) (+ x 1)) 41))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(42), "stderr: {}", stderr(&out));
}

/// A top-level function passed as a value: `(apply add1 41)`.
#[test]
fn function_name_as_value_via_apply() {
    let dir = scratch_dir("b1-fn-val");
    write_source(
        &dir,
        "main.ax",
        "(:: apply (-> (-> Int Int) Int Int))\n\
         (fn (apply f x) (f x))\n\
         (:: add1 (-> Int Int))\n\
         (fn (add1 x) (+ x 1))\n\
         (:: main Int)\n\
         (fn (main) (apply add1 41))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(42), "stderr: {}", stderr(&out));
}

/// Closures capture free variables from the enclosing scope:
/// `(compose f g) = (lambda (x) (f (g x)))` captures `f` and `g`.
#[test]
fn closure_captures_free_variables_via_compose() {
    let dir = scratch_dir("b1-compose");
    write_source(
        &dir,
        "main.ax",
        "(:: compose (-> (-> Int Int) (-> Int Int) (-> Int Int)))\n\
         (fn (compose f g) (lambda (x) (f (g x))))\n\
         (:: add1 (-> Int Int))\n\
         (fn (add1 x) (+ x 1))\n\
         (:: mul2 (-> Int Int))\n\
         (fn (mul2 x) (* x 2))\n\
         (:: apply (-> (-> Int Int) Int Int))\n\
         (fn (apply f x) (f x))\n\
         (:: main Int)\n\
         (fn (main) (apply (compose add1 mul2) 20))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(41), "stderr: {}", stderr(&out));
}

// ---------------------------------------------------------------
// §2.4 ADT struct variants — named constructor fields
//
// Positional constructors remain unchanged; named-field constructors
// use `{ name : type }` syntax in declarations and
// `{ name = pattern }` in pattern matches.
// ---------------------------------------------------------------

/// Declare a named-field data type and match on it exhaustively.
#[test]
fn named_field_constructor_declaration_and_match() {
    let dir = scratch_dir("adt-named");
    write_source(
        &dir,
        "main.ax",
        "(data Person\n  (Person { name : Int age : Int }))\n(:: main Int)\n\
         (fn (main)\n  (match (Person 42 99)\n    ((Person { age = a name = n }) (+ n a))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(141), "stderr: {}", stderr(&out));
}

/// Named-field constructor parse round-trips through fmt.
#[test]
fn named_field_constructor_parse_and_check() {
    let dir = scratch_dir("adt-named-decl");
    write_source(
        &dir,
        "main.ax",
        "(data Shape\n  (Circle { radius : Int })\n  (Rectangle { w : Int h : Int }))\n\
         (:: main Int)\n(fn (main) 42)\n",
    );
    let out = run_axiom(&["check", "main.ax"], &dir);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
}

/// Dot-access on a named-field constructor reads the correct field.
#[test]
fn named_field_dot_access_reads_field_by_name() {
    let dir = scratch_dir("adt-dot-get");
    write_source(
        &dir,
        "main.ax",
        "(data Person (Person { name : Int age : Int }))\n\
         (:: main Int)\n\
         (fn (main)\n  (let ((p (Person 42 99))) (+ (p.name) (p.age))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(141), "stderr: {}", stderr(&out));
}

/// Dot-access ordering is by field declaration, not access order.
#[test]
fn named_field_dot_access_order_is_declaration_order() {
    let dir = scratch_dir("adt-dot-order");
    write_source(
        &dir,
        "main.ax",
        "(data Pair (Pair { second : Int first : Int }))\n\
         (:: main Int)\n\
         (fn (main)\n  (let ((p (Pair 10 20))) (+ (p.first) (p.second))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(30), "stderr: {}", stderr(&out));
}

// ---------------------------------------------------------------
// §4.1 P3: Macros
//
// Basic syntax-rules-style macros with pattern-variable substitution.
// Cross-module macro import works via `(import Pre (when))`.
// ---------------------------------------------------------------

/// `(macro (double x) (+ x x))` — single-parameter macro.
#[test]
fn macro_single_param_expands_and_evaluates() {
    let dir = scratch_dir("macro-single");
    write_source(
        &dir,
        "main.ax",
        "(macro (double x) (+ x x))\n(:: main Int)\n(fn (main) (double 21))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(42), "stderr: {}", stderr(&out));
}

/// `(macro (when test body) (if test body 0))` — multi-param macro.
#[test]
fn macro_multi_param_expands_via_if_with_zero_else() {
    let dir = scratch_dir("macro-multi");
    write_source(
        &dir,
        "main.ax",
        "(macro (when test body) (if test body 0))\n\
         (:: main Int)\n\
         (fn (main) (when (== 1 1) 42))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(42), "stderr: {}", stderr(&out));
}

/// Cross-module import: `(import Pre (when))` works.
#[test]
fn macro_cross_module_import_from_prelude_works() {
    let dir = scratch_dir("macro-import");
    write_source(
        &dir,
        "main.ax",
        "(import Pre (when))\n(:: main Int)\n(fn (main) (when (== 1 1) 42))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(42), "stderr: {}", stderr(&out));
}

// ---------------------------------------------------------------
// REPL evaluation
//
// The REPL could not evaluate anything at all. It wrapped every result
// in a `foreign printf` binding, and since strings became first-class in
// 7b786e1 a `String` is the address of a `{len, bytes}` header rather
// than a `char*` - so the wrapper emitted `i64` where the declaration
// said `ptr` and `llc` rejected every module. It was also the one code
// path in the project that called libc, which the freestanding gate
// forbids everywhere else.
//
// Nothing caught it because the REPL had no test of any kind: it is
// interactive, so it was left to manual use, and `repl` was named in the
// roadmap's own risk table as an ungated surface.
//
// These tests drive it over a pipe, which is all it takes.
// ---------------------------------------------------------------

#[test]
fn repl_evaluates_an_integer_expression() {
    let out = run_repl("(+ 1 2)");
    assert!(
        stdout(&out).contains("result 3"),
        "the REPL could not evaluate `(+ 1 2)`; stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn repl_evaluates_a_boolean_expression() {
    let out = run_repl("(== 1 1)\n(== 1 2)");
    let text = stdout(&out);
    assert!(
        text.contains("result true") && text.contains("result false"),
        "stdout: {}",
        text
    );
}

#[test]
fn repl_prints_a_string_result_as_text() {
    // Formerly printed with `%ld`, which rendered the address of the
    // string header as a decimal number.
    let out = run_repl("\"hello axiom\"");
    assert!(
        stdout(&out).contains("result hello axiom"),
        "stdout: {}",
        stdout(&out)
    );
}

#[test]
fn repl_prints_a_char_result_as_a_character() {
    let out = run_repl("'Z'");
    assert!(
        stdout(&out).contains("result Z"),
        "stdout: {}",
        stdout(&out)
    );
}

#[test]
fn repl_evaluates_a_user_defined_function() {
    let out = run_repl("(:: sq (-> Int Int))\n(fn (sq x) (* x x))\n(sq 12)");
    assert!(
        stdout(&out).contains("result 144"),
        "definitions did not carry into evaluation; stdout: {}",
        stdout(&out)
    );
}

#[test]
fn repl_reports_a_failure_instead_of_printing_nothing() {
    // Every stage used to be wrapped in `if let Ok(..)` with no `else`,
    // so a wrapper that failed to compile produced no output at all -
    // the REPL printed the type and returned to the prompt, which reads
    // as the evaluator having decided the answer was nothing.
    let out = run_repl("(+ 1 undefinedName)");
    let text = stdout(&out);
    assert!(
        text.contains("undefinedName"),
        "the REPL swallowed the failure; stdout: {}",
        text
    );
}

#[test]
fn repl_generated_code_calls_no_libc() {
    // The freestanding invariant `scripts/check-freestanding.sh` enforces
    // for compiled programs applies to the REPL too; it was the one path
    // that broke it.
    let out = run_repl(":llvm (+ 1 2)");
    let text = stdout(&out);
    for name in [
        "@printf(", "@puts(", "@malloc(", "@free(", "@memset(", "@memcpy(",
    ] {
        assert!(
            !text.contains(&format!("call i32 {}", name))
                && !text.contains(&format!("call ptr {}", name))
                && !text.contains(&format!("call void {}", name)),
            "REPL IR calls libc function {}; stdout: {}",
            name,
            text
        );
    }
}

/// A `Char`-typed function emitted `ret i8` from a function LLVM
/// declared to return `i64`, because the character *literal* lowered as
/// `U8` while `Char` maps to `i64` everywhere else. `check` passed and
/// the failure surfaced from `opt`, about generated code, for a program
/// the compiler had just called well-typed.
#[test]
fn char_typed_function_compiles() {
    let dir = scratch_dir("char-return");
    write_source(
        &dir,
        "main.ax",
        "(:: pick (-> Int Char))\n(fn (pick x) 'Z')\n\
         (:: main Int)\n(fn (main) (cast Int (pick 0)))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(90),
        "stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

// ---------------------------------------------------------------
// `explain`
//
// The other surface the roadmap names as ungated. It was in better
// shape than `repl`, but "in better shape" was not something anything
// checked.
// ---------------------------------------------------------------

#[test]
fn explain_knows_every_code_the_compiler_can_emit() {
    // The invariant that matters: a diagnostic a user can hit is a
    // diagnostic they can look up. A new code added to `code.rs` without
    // an explanation is a dead end at exactly the moment someone needs
    // the docs - and `axiom explain AX####` is the workflow the agent
    // skill tells readers to follow.
    let dir = scratch_dir("explain-all");
    let listed = run_axiom(&["explain", "--list"], &dir);
    assert!(listed.status.success(), "stderr: {}", stderr(&listed));

    let codes: Vec<String> = stdout(&listed)
        .split_whitespace()
        .filter(|w| {
            w.starts_with("AX") && w.len() == 6 && w[2..].chars().all(|c| c.is_ascii_digit())
        })
        .map(|w| w.to_string())
        .collect();
    assert!(
        codes.len() >= 20,
        "expected the full code table, got {:?}",
        codes
    );

    for code in &codes {
        let out = run_axiom(&["explain", code], &dir);
        assert!(
            out.status.success(),
            "`axiom explain {}` failed though `--list` advertises it; stderr: {}",
            code,
            stderr(&out)
        );
        assert!(
            stdout(&out).contains(code),
            "`axiom explain {}` did not describe {}; stdout: {}",
            code,
            code,
            stdout(&out)
        );
    }
}

#[test]
fn explain_rejects_an_unknown_code_and_points_at_the_list() {
    let dir = scratch_dir("explain-unknown");
    let out = run_axiom(&["explain", "AX9999"], &dir);
    assert!(!out.status.success(), "an unknown code must not succeed");
    let text = format!("{}{}", stdout(&out), stderr(&out));
    assert!(
        text.contains("--list"),
        "an unknown code should point at the list; got: {}",
        text
    );
}

// ---------------------------------------------------------------
// Floating point
//
// Axiom had a `Float` type name and a lexer that read `1.5`, and
// nothing else: the arithmetic operators were `Int -> Int -> Int`
// builtins, so a float operand was a type error, and a function
// *declared* to return `Float` emitted `ret double` from a function
// LLVM declared to return `i64` - rejected by `opt`, after `check` had
// reported the program well typed.
// ---------------------------------------------------------------

#[test]
fn float_returning_function_compiles_and_computes() {
    let dir = scratch_dir("float-return");
    write_source(
        &dir,
        "main.ax",
        "(:: scale (-> Float Float))\n(fn (scale x) (* x 2.0))\n\
         (:: main Int)\n(fn (main) (__floatToInt (scale 21.0)))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(42),
        "stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn a_binop_over_two_conversions_is_a_float_operation() {
    // `__intToFloat` is a primitive, so no signature ever declares its
    // return type - and the float-ness classifier consulted only
    // declared signatures. `(/ (__intToFloat 1) (__intToFloat 2))` had
    // no float literal, parameter or field anywhere in sight, so it
    // lowered to `sdiv` on the converted values: 1/2 = 0 where 0.5 was
    // meant, silently, in a program the type checker had accepted.
    // Every other float test happens to carry an operand that reveals
    // the float-ness, which is why none of them tripped on it.
    let dir = scratch_dir("float-conv-binop");
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n\
         (fn (main) (__floatToInt (* (/ (__intToFloat 1) (__intToFloat 2)) (__intToFloat 10))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(5),
        "stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn a_shadowing_let_binding_ends_with_its_body() {
    // The alloca map was never restored after a `let` body, so the
    // inner binding's storage leaked outward:
    // `(let ((x 1)) (+ (let ((x 2)) x) x))` read the inner `x` twice
    // and answered 4. No floats, no patterns - plain integer scoping.
    let dir = scratch_dir("let-shadow-scope");
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n(fn (main) (let ((x 1)) (+ (let ((x 2)) x) x)))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(3),
        "stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn an_int_binding_shadowing_a_float_name_is_integer_arithmetic() {
    // Float-ness was keyed by name for the whole function, so an `Int`
    // binding shadowing a `Float` name still lowered `(* x 3)` as
    // `fmul` over the integer's bits. Scoping is now dynamic: bound
    // for the body, unbound after it - in both directions, so the
    // outer float meaning also returns once the shadow ends.
    let dir = scratch_dir("float-shadow-scope");
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n\
         (fn (main) (let ((x 1.5)) (let ((x 20)) (* x 3))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(60),
        "stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
    let dir2 = scratch_dir("float-shadow-restore");
    write_source(
        &dir2,
        "main.ax",
        "(:: main Int)\n\
         (fn (main) (let ((x 2.5)) (+ (let ((x 4)) (* x 10)) (__floatToInt (* x 2.0)))))\n",
    );
    let out2 = run_axiom(&["run", "main.ax"], &dir2);
    assert_eq!(
        out2.status.code(),
        Some(45),
        "stdout: {}\nstderr: {}",
        stdout(&out2),
        stderr(&out2)
    );
}

#[test]
fn float_comparison_yields_bool() {
    let dir = scratch_dir("float-cmp");
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n(fn (main) (if (< (/ 1.0 4.0) 0.3) 42 7))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(42), "stderr: {}", stderr(&out));
}

#[test]
fn mixing_int_and_float_operands_is_rejected() {
    // An implicit widening is how precision is lost with nothing in the
    // source saying so; `(cast Float n)` is the explicit form.
    let dir = scratch_dir("float-mixed");
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n(fn (main) (__floatToInt (+ 1.5 2)))\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success(), "mixing Int and Float must not check");
    assert!(stderr(&out).contains("AX3004"), "stderr: {}", stderr(&out));
}

#[test]
fn float_survives_a_constructor_field() {
    // The pattern binding has to know the field is a float, or the
    // arm's arithmetic lowers to an integer `add` over bit patterns -
    // which compiles, runs, and is wrong.
    let dir = scratch_dir("float-adt");
    write_source(
        &dir,
        "main.ax",
        "(data V2 (Mk Float Float))\n\
         (:: sum (-> V2 Float))\n(fn (sum v) (match v ((Mk x y) (+ x y))))\n\
         (:: main Int)\n(fn (main) (__floatToInt (sum (Mk 20.5 21.5))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(42),
        "stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn partial_application_of_an_operator_still_works() {
    // Only the saturated two-argument form is intercepted by the
    // numeric-builtin rule; `(+ 1)` must keep its ordinary `Int` type.
    let dir = scratch_dir("float-partial");
    write_source(
        &dir,
        "main.ax",
        "(:: twice (-> (-> Int Int) Int Int))\n(fn (twice f x) (f (f x)))\n\
         (:: main Int)\n(fn (main) (twice (lambda (n) (+ n 21)) 0))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(42), "stderr: {}", stderr(&out));
}

#[test]
fn bool_survives_a_constructor_field() {
    // `Bool` is the one Axiom type narrower than a machine word (`i1`),
    // and it was stored into a field without widening - emitting
    // `store i64 true`, a constant whose text LLVM reads as `i1` under a
    // declared `i64`. No `data` constructor or `struct` could hold one.
    let dir = scratch_dir("bool-field");
    write_source(
        &dir,
        "main.ax",
        "(data Flag (Mk Bool))\n\
         (:: main Int)\n(fn (main) (match (Mk true) ((Mk b) (if b 42 7))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(42),
        "stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn bool_survives_a_struct_field() {
    let dir = scratch_dir("bool-struct-field");
    write_source(
        &dir,
        "main.ax",
        "(struct Cfg (on : Bool) (n : Int))\n\
         (:: main Int)\n(fn (main) (let ((c (Cfg true 5))) (if c.on 42 7)))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(42),
        "stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn float_arithmetic_works_inside_a_lambda() {
    // A lambda parameter has no declared type, so it presents as a
    // fresh type variable. Requiring both operands to be *concretely*
    // `Float` made floats unusable in exactly the higher-order code
    // they are most wanted in.
    let dir = scratch_dir("float-lambda");
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n\
         (fn (main) (let ((f (lambda (x) (* x 2.0)))) (__floatToInt (f 21.0))))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(42),
        "stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn fmt_preserves_a_type_alias() {
    // `(type Name = Alias)`: the formatter omitted the `=`, so a
    // formatted alias no longer parsed. No `.ax` file in the repository
    // declares one, so `check-fmt.sh` never exercised it - a gate is
    // only as wide as the corpus it runs on.
    let formatted = format_to_string(
        "fmt-type-alias",
        "(pub type Num = Int)\n(:: main Num)\n(fn (main) 42)\n",
    );
    assert!(
        formatted.contains("(pub type Num = Int)"),
        "the type alias lost its `=`: {}",
        formatted
    );
}

#[test]
fn fmt_preserves_a_macro_declarations_arity() {
    // `parse_macro` wraps two-plus parameters in a synthetic `PTuple`,
    // and the formatter printed that tuple as a single pattern:
    // `(macro (when test body) t)` became `(macro (when (test body)) t)`.
    // The result *reparses* - `(test body)` is a well-formed constructor
    // pattern - so fmt's own verification passed, but the macro's arity
    // collapsed to one, no call site matched any longer, and the name
    // surfaced as an undefined function. Formatting must preserve
    // behaviour, so the pin is behavioural: format, then run.
    let dir = scratch_dir("fmt-macro-arity");
    write_source(
        &dir,
        "main.ax",
        "(macro (when test body) (if test body 0))\n\
         (:: main Int)\n(fn (main) (when (== 1 1) 42))\n",
    );
    let fmt_out = run_axiom(&["fmt", "main.ax"], &dir);
    assert!(
        fmt_out.status.success(),
        "fmt refused the file: {}",
        stderr(&fmt_out)
    );
    let formatted = std::fs::read_to_string(dir.join("main.ax")).unwrap();
    assert!(
        formatted.contains("(when test body)"),
        "the macro head lost its parameter list shape: {}",
        formatted
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(42),
        "formatted macro no longer expands; stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn cond_selects_the_right_clause() {
    // Every stage but the parser and the IR generator already handled
    // `cond`: the token existed, `Expr::ECond` was in the AST, and the
    // type checker and formatter both handled it. The parser had no
    // case, so the word was reserved and unwritable; once it did parse,
    // the IR generator had no arm either, so the whole form evaluated to
    // 0 whichever clause matched.
    let dir = scratch_dir("cond");
    write_source(
        &dir,
        "main.ax",
        "(:: pick (-> Int Int))\n\
         (fn (pick n) (cond ((< n 0) 1) ((== n 0) 2) (else 42)))\n\
         (:: main Int)\n(fn (main) (pick 7))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(42),
        "stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn cond_keeps_a_self_tail_call_a_jump() {
    // `cond` lowers to a chain of `if`, so it inherits `if`'s tail-call
    // detection rather than needing its own. Three million frames is far
    // past what an 8 MiB stack holds, so a regression crashes here
    // rather than merely running slowly.
    let dir = scratch_dir("cond-tail");
    write_source(
        &dir,
        "main.ax",
        "(:: down (-> Int Int Int))\n\
         (fn (down n acc) (cond ((<= n 0) acc) (else (down (- n 1) (+ acc 1)))))\n\
         (:: main Int)\n(fn (main) (- (down 3000000 0) 2999958))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(out.status.code(), Some(42), "stderr: {}", stderr(&out));
}

#[test]
fn same_named_struct_fields_of_different_kinds_do_not_confuse_arithmetic() {
    // Float-ness of a struct field is tracked by field *name*, because
    // `EField` gives the name but not the struct and the type checker is
    // gone by lowering time. Two structs may therefore disagree; the
    // disagreement resolves towards integer, so an `Int` field never
    // gets floating-point arithmetic applied to its bits.
    let dir = scratch_dir("field-name-collision");
    write_source(
        &dir,
        "main.ax",
        "(struct A (v : Float))\n(struct B (v : Int))\n\
         (:: useB (-> B Int))\n(fn (useB b) (+ b.v 1))\n\
         (:: main Int)\n(fn (main) (useB (B 41)))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(42),
        "an Int field was treated as a float; stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn a_warning_does_not_fail_the_build() {
    // `AX3010` renders as `W` and is documented as a warning "so an
    // agent can correct the annotation instead of silently trusting
    // it". Everything the checker produced went into one list, so it
    // aborted compilation and announced "compilation failed due to 1
    // previous error" - of a diagnostic the renderer had just labelled a
    // warning. The severity and the behaviour disagreed.
    let dir = scratch_dir("warning-not-error");
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n;@axiom:effect(io)\n(fn (main) 0)\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(
        out.status.success(),
        "a warning must not fail the build; stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
    // Not failing must not mean not reporting.
    let text = format!("{}{}", stdout(&out), stderr(&out));
    assert!(
        text.contains("AX3010"),
        "the warning was silenced rather than downgraded: {}",
        text
    );
}

#[test]
fn a_warning_is_still_reported_alongside_an_error() {
    // Splitting warnings out of the failure list must not mean a file
    // that has both shows only the error - that would swap one silence
    // for another. The summary line still counts errors only, so a
    // build with one error and one warning does not announce two.
    let dir = scratch_dir("warning-with-error");
    write_source(
        &dir,
        "main.ax",
        "(:: main Int)\n;@axiom:effect(io)\n(fn (main) (+ 1 nope))\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success(), "an error must still fail the build");
    let text = format!("{}{}", stdout(&out), stderr(&out));
    assert!(
        text.contains("AX3010"),
        "the warning was dropped once an error joined it: {}",
        text
    );
    assert!(
        text.contains("AX3001"),
        "the error was not reported: {}",
        text
    );
    assert!(
        text.contains("1 previous error"),
        "the warning was counted as an error: {}",
        text
    );
}

#[test]
fn an_error_still_fails_the_build() {
    let dir = scratch_dir("error-still-fails");
    write_source(&dir, "main.ax", "(:: main Int)\n(fn (main) (+ 1 nope))\n");
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(!out.status.success(), "an error must still fail the build");
    assert!(stderr(&out).contains("AX3001"), "stderr: {}", stderr(&out));
}

#[test]
fn set_writes_a_struct_field() {
    // `Expr::ESetField` was handled by the type checker, the IR
    // generator (resolving the field by name and writing at its offset)
    // and the formatter - but nothing could produce one, so a field
    // could only be written through `memSetWord` with a hand-counted
    // index.
    let dir = scratch_dir("set-field");
    write_source(
        &dir,
        "main.ax",
        "(struct Counter (n : Int) (step : Int))\n\
         (:: main Int)\n\
         (fn (main) (let ((c (Counter 10 5))) { (set c.n 40) (+ c.n c.step) }))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(45),
        "stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn set_writes_a_named_constructor_field() {
    // A `data` block carries a tag word, so the field offset differs
    // from a struct's by one slot.
    let dir = scratch_dir("set-data-field");
    write_source(
        &dir,
        "main.ax",
        "(data Box (Mk { x : Int, y : Int }))\n\
         (:: main Int)\n\
         (fn (main) (let ((b (Mk 1 2))) { (set b.x 40) (+ b.x b.y) }))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(42),
        "stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn set_writes_through_a_nested_field_path() {
    // `(set a.b.c v)` writes `c` on the value at `a.b`, so the base is
    // itself a field access rather than a variable. The reference
    // documents this form, so it is pinned here: the chain is built the
    // same way expression-position access builds it, and nothing in the
    // lowering assumes the base of a store is a bare local.
    let dir = scratch_dir("set-nested-field");
    write_source(
        &dir,
        "main.ax",
        "(struct Inner (v : Int))\n\
         (struct Outer (i : Inner))\n\
         (:: main Int)\n\
         (fn (main) (let ((o (Outer (Inner 1)))) { (set o.i.v 42) o.i.v }))\n",
    );
    let out = run_axiom(&["run", "main.ax"], &dir);
    assert_eq!(
        out.status.code(),
        Some(42),
        "stdout: {}\nstderr: {}",
        stdout(&out),
        stderr(&out)
    );
}

#[test]
fn set_on_a_computed_place_is_still_a_syntax_error() {
    // The target is a name or a field path, never a computed place.
    // Accepting the dotted form must not have widened this: `(set (f x)
    // 1)` should still be rejected by the parser, naming what is wrong,
    // rather than type-checking its way to a confusing report about a
    // non-assignable expression.
    let dir = scratch_dir("set-computed-place");
    write_source(
        &dir,
        "main.ax",
        "(:: f (-> Int Int))\n\
         (fn (f x) x)\n\
         (:: main Int)\n\
         (fn (main) { (set (f 1) 2) 0 })\n",
    );
    let out = run_axiom(&["--diagnostic-format=ai", "check", "main.ax"], &dir);
    assert!(
        !out.status.success(),
        "a computed place must not be assignable; stdout: {}",
        stdout(&out)
    );
    assert!(
        stderr(&out).contains("a `mut` binding, or a field path"),
        "expected the parse error to name what `set` accepts, got: {}",
        stderr(&out)
    );
}
