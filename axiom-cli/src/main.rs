use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use axiom_codegen::LlvmCodeGen;
use axiom_errors::{Diagnostic, DiagnosticFormat, SymbolFact, SymbolKind};
use axiom_ir::generator::IrGen;
use axiom_lexer::Lexer;
use axiom_parser::{DeclOrExpr, Parser};
use axiom_sema::{TypeChecker, TypeId};

mod fmt;

use clap::{Parser as ClapParser, Subcommand};
use colored::Colorize;
use rustyline::error::ReadlineError;
use rustyline::DefaultEditor;

#[derive(ClapParser)]
#[command(name = "axiom")]
#[command(about = "Axiom Compiler - A functional systems programming language")]
#[command(version)]
struct Cli {
    /// How to render diagnostics: `human` (default, Rust-style reports),
    /// `ai` (Axiom's dense AI-optimized notation, see `docs/diagnostics.md`),
    /// or `json` (JSON Lines, one diagnostic object per line).
    #[arg(long, global = true, default_value = "human")]
    diagnostic_format: String,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Compile a source file to an executable
    Build {
        #[arg(long)]
        input: String,
        #[arg(long, default_value = "output")]
        output: String,
        #[arg(long)]
        emit_llvm: bool,
        #[arg(short, long, default_value = "0")]
        opt: u8,
    },
    /// Run a source file directly
    Run { input: String, args: Vec<String> },
    /// Check syntax and types
    Check { input: String },
    /// Emit LLVM IR only
    EmitLlvm {
        input: String,
        #[arg(short, long)]
        output: Option<String>,
    },
    /// Interactive REPL
    Repl {
        #[arg(long)]
        no_banner: bool,
    },
    /// Format a source file
    Fmt {
        /// File to format
        input: String,
        /// Check if file needs formatting (don't modify)
        #[arg(long)]
        check: bool,
    },
    /// Print every top-level symbol Axiom's type checker collected for a
    /// file (functions, foreign bindings, data types, constructors,
    /// structs, unions, and traits) along with its inferred/declared
    /// type. Honors `--diagnostic-format`: `ai` emits one AXSYM line per
    /// symbol (see `docs/diagnostics.md`), `json` emits one JSON object per
    /// line, and `human` (the default) prints an aligned table.
    Symbols {
        input: String,
        /// Also list the dozen always-in-scope built-in operators (`+`,
        /// `==`, `&&`, ...). Omitted by default: they never change, an
        /// agent almost always already knows Axiom's fixed operator set
        /// from the language docs, and printing all of them on *every*
        /// `axiom symbols` call is exactly the kind of restating-what's-
        /// already-known token waste AXSYM exists to avoid (see
        /// `docs/diagnostics.md`).
        #[arg(long)]
        builtins: bool,
    },
    /// Print a full explanation for a diagnostic code, e.g. `axiom explain AX3001`
    Explain {
        /// Diagnostic code, with or without the `AX` prefix (e.g. `AX3001` or `3001`)
        code: Option<String>,
        /// List every known diagnostic code
        #[arg(long)]
        list: bool,
    },
}

fn main() {
    let cli = Cli::parse();
    let format = DiagnosticFormat::parse(&cli.diagnostic_format).unwrap_or_else(|| {
        eprintln!(
            "warning: unknown --diagnostic-format '{}', falling back to 'human' (valid: human, ai, json)",
            cli.diagnostic_format
        );
        DiagnosticFormat::Human
    });

    match cli.command {
        Commands::Build {
            input,
            output,
            emit_llvm,
            opt,
        } => {
            if let Err(e) = build(&input, &output, emit_llvm, opt, format) {
                eprintln!("{}", e);
                std::process::exit(1);
            }
        }
        Commands::Run { input, args } => match run(&input, &args, format) {
            Ok(code) => std::process::exit(code),
            Err(e) => {
                eprintln!("{}", e);
                std::process::exit(1);
            }
        },
        Commands::Check { input } => {
            if let Err(e) = check(&input, format) {
                eprintln!("{}", e);
                std::process::exit(1);
            } else {
                println!("OK");
            }
        }
        Commands::Symbols { input, builtins } => {
            if let Err(e) = symbols(&input, format, builtins) {
                eprintln!("{}", e);
                std::process::exit(1);
            }
        }
        Commands::EmitLlvm { input, output } => {
            if let Err(e) = emit_llvm(&input, output.as_deref(), format) {
                eprintln!("{}", e);
                std::process::exit(1);
            }
        }
        Commands::Repl { no_banner } => {
            repl(no_banner);
        }
        Commands::Fmt { input, check } => {
            if let Err(e) = fmt(&input, check) {
                eprintln!("{}", e);
                std::process::exit(1);
            }
        }
        Commands::Explain { code, list } => {
            explain(code.as_deref(), list);
        }
    }
}

fn explain(code: Option<&str>, list: bool) {
    if list || code.is_none() {
        println!("{}", "Known Axiom diagnostic codes:".bold().bright_cyan());
        for info in axiom_errors::code::ALL {
            println!(
                "  {}  {}  ({})",
                info.code.bright_yellow(),
                info.title,
                info.slug
            );
        }
        if code.is_none() && !list {
            println!("\nUsage: axiom explain <CODE>");
        }
        return;
    }
    let code = code.unwrap();
    match axiom_errors::explain(code) {
        Some(text) => println!("{}", text),
        None => {
            eprintln!("error: unknown diagnostic code '{}'", code);
            eprintln!("run `axiom explain --list` to see all known codes");
            std::process::exit(1);
        }
    }
}

/// Render a batch of diagnostics for one file in the requested format and
/// print to stderr, deduplicating cascades first.
/// Render and print diagnostics that the caller has *already*
/// cascade-deduplicated (or that are known to be a single diagnostic, e.g.
/// a lexer/parser error). Calls the format-specific renderers directly
/// rather than the top-level `axiom_errors::render`, which always dedups
/// internally - callers that already deduped (to compute an accurate "N
/// errors" count) would otherwise pay for a second, redundant pass.
fn print_diagnostics(
    diags: Vec<Diagnostic>,
    filename: &str,
    source: &str,
    format: DiagnosticFormat,
) {
    let rendered = match format {
        DiagnosticFormat::Human => axiom_errors::render_human(&diags, filename, source),
        DiagnosticFormat::Ai => axiom_errors::render_ai(&diags, filename, source),
        DiagnosticFormat::Json => axiom_errors::render_json(&diags, filename, source),
    };
    eprint!("{}", rendered);
}

/// Tracks every source file that ended up contributing declarations to a
/// compilation - the entry file plus every transitively `(import ...)`ed
/// module - indexed by the same `file_id` [`axiom_ast::span::Span`]
/// already carries end to end (the lexer stamps every span it produces
/// with the `file_id` it was constructed with; see `axiom-lexer`). This is
/// what lets [`print_diagnostics_multi`] point a diagnostic produced by
/// type-checking a *merged*, multi-file AST back at the specific file and
/// source text it actually came from, instead of always (incorrectly)
/// rendering it against the entry file's text.
struct FileRegistry {
    /// `(display_path, source)`, indexed by `file_id`.
    files: Vec<(String, String)>,
}

impl FileRegistry {
    fn new() -> Self {
        Self { files: Vec::new() }
    }

    /// Register a file's text and return the `file_id` it was assigned
    /// (always the next sequential id, starting at `0` for the first file
    /// added - callers add the entry file first for exactly this reason).
    fn add(&mut self, path: String, source: String) -> usize {
        let id = self.files.len();
        self.files.push((path, source));
        id
    }

    fn get(&self, file_id: usize) -> (&str, &str) {
        match self.files.get(file_id) {
            Some((path, source)) => (path.as_str(), source.as_str()),
            // Every span in a merged AST was produced by lexing one of
            // this registry's own files, so a truly out-of-range
            // `file_id` should never happen; falling back to the entry
            // file (id `0`) rather than panicking means a diagnostic
            // still renders *somewhere* useful even if that invariant is
            // ever violated by a future bug.
            None => {
                let (path, source) = &self.files[0];
                (path.as_str(), source.as_str())
            }
        }
    }
}

/// Like [`print_diagnostics`], but for a diagnostic list that may span
/// more than one file (i.e. any diagnostic from type-checking a module
/// that pulled in `(import ...)`ed declarations from other files). Each
/// diagnostic is rendered individually against the specific file its own
/// primary span's `file_id` names, via `registry`, instead of one shared
/// filename/source for the whole batch - the single-file renderers in
/// `axiom-errors` are otherwise unchanged and still called exactly once
/// per diagnostic.
///
/// **Known limitation:** this only re-homes a diagnostic by its *primary*
/// span's file. A diagnostic's *secondary* spans (right now, only
/// `SemError::DuplicateDefinition`'s "first defined here") are rendered by
/// `axiom-errors` against that same primary file's source text - correct
/// when both spans are in the same file (the common case: two definitions
/// in one file), but if `helper` is defined once in an imported file and
/// redefined in the file that imports it, the "first defined here" label
/// will be computed against the *wrong* file's source text (whichever
/// file the primary "redefined here" span is in), since `axiom-errors`'s
/// renderers take one shared `(filename, source)` pair per diagnostic, not
/// one per label. Fixing this properly means threading per-label file
/// resolution through `render_human`/`render_ai`/`render_json` themselves;
/// out of scope here since every *other* diagnostic in the compiler only
/// ever has secondary spans in the same file as its primary span.
fn print_diagnostics_multi(
    diags: &[Diagnostic],
    registry: &FileRegistry,
    format: DiagnosticFormat,
) {
    for diag in diags {
        let file_id = diag.primary_span().map(|s| s.file_id).unwrap_or(0);
        let (filename, source) = registry.get(file_id);
        print_diagnostics(vec![diag.clone()], filename, source, format);
    }
}

/// The declared name of a top-level `Decl`, for import name-filtering
/// (`(import Mod (a b))`) and duplicate-definition namespacing - `None`
/// for decls with no single name of their own (`DImport`, `DImpl`).
fn decl_name(decl: &axiom_ast::ast::Decl) -> Option<&str> {
    use axiom_ast::ast::Decl;
    match decl {
        Decl::DData { name, .. }
        | Decl::DStruct { name, .. }
        | Decl::DUnion { name, .. }
        | Decl::DType { name, .. }
        | Decl::DTrait { name, .. }
        | Decl::DSig { name, .. }
        | Decl::DFn { name, .. }
        | Decl::DForeign { name, .. }
        | Decl::DEffect { name, .. } => Some(&name.name),
        Decl::DImpl { .. } | Decl::DImport { .. } => None,
    }
}

/// Turn a dotted module path (`Mod.Sub.Path`, i.e. `(import Mod.Sub.Path
/// ...)`) into the relative file path it names: each segment becomes a
/// directory component and the whole thing gets a `.ax` extension -
/// `Mod.Sub` resolves to `Mod/Sub.ax`. Resolved relative to the
/// *importing* file's own directory (see `resolve_imports_into`), not the
/// entry file's, so `A` importing `B` importing `C` finds `C` next to `B`
/// even if `A` lives somewhere else entirely.
fn module_rel_path(module: &[axiom_ast::span::Ident]) -> PathBuf {
    let mut path = PathBuf::new();
    for segment in module {
        path.push(&segment.name);
    }
    path.set_extension("ax");
    path
}

/// Lex and parse one module file in isolation (no import resolution of
/// its own imports - that's `resolve_imports_into`'s job, so a file's
/// *own* diagnostics are always printed before its imports are even
/// looked at), printing diagnostics against `path`/its own source on
/// failure exactly like the entry file's lex/parse stage does.
fn parse_module_file(
    path: &Path,
    file_id: usize,
    format: DiagnosticFormat,
) -> Result<axiom_ast::Module, String> {
    let display = path.display().to_string();
    let source = fs::read_to_string(path)
        .map_err(|e| format!("cannot read imported module '{}': {}", display, e))?;

    let mut lexer = Lexer::new(&source, file_id);
    let tokens = match lexer.tokenize() {
        Ok(tokens) => tokens,
        Err(e) => {
            print_diagnostics(vec![e.to_diagnostic()], &display, &source, format);
            return Err(format!(
                "failed to parse imported module '{}' due to a lexer error",
                display
            ));
        }
    };

    let mut parser = Parser::new(tokens);
    let module = match parser.parse_module() {
        Ok(module) => module,
        Err(e) => {
            print_diagnostics(vec![e.to_diagnostic()], &display, &source, format);
            return Err(format!(
                "failed to parse imported module '{}' due to a syntax error",
                display
            ));
        }
    };

    Ok(module)
}

/// Recursively resolve `imports` (a module's `Module.imports`, i.e. its
/// own top-level `(import ...)` decls), appending every declaration they
/// bring in to `out`, in import order. `root_dir` is always the *entry*
/// file's directory - fixed for the whole resolution, not recomputed per
/// importing file - so every module path in the program is resolved
/// relative to one consistent project root regardless of how deeply
/// nested the file that wrote a given `(import ...)` is. (An earlier
/// version resolved each file's imports relative to *that file's own*
/// directory, which meant `A` importing `B` importing `C` looked for `C`
/// next to `B` instead of next to `A` - surprising for the overwhelmingly
/// common layout where every module path is meant relative to one project
/// root, so a submodule can import another top-level module by the same
/// path the entry file would use.) `visited` dedups diamond imports (two
/// different files importing the same third file) by canonicalized path,
/// so a shared module's declarations are only merged once no matter how
/// many other modules import it.
fn resolve_imports_into(
    root_dir: &Path,
    imports: &[axiom_ast::ast::Decl],
    format: DiagnosticFormat,
    registry: &mut FileRegistry,
    visited: &mut HashSet<PathBuf>,
    out: &mut Vec<axiom_ast::ast::Decl>,
) -> Result<(), String> {
    use axiom_ast::ast::Decl;

    for import in imports {
        let Decl::DImport { module, names } = import else {
            continue;
        };

        let dotted = module
            .iter()
            .map(|i| i.name.clone())
            .collect::<Vec<_>>()
            .join(".");
        let rel_path = module_rel_path(module);
        let path = root_dir.join(&rel_path);

        if !path.is_file() {
            let diag = Diagnostic::error(
                &axiom_errors::code::MODULE_NOT_FOUND,
                format!("cannot resolve import `{}`", dotted),
            )
            .with_help(format!(
                "expected to find '{}' relative to '{}'",
                rel_path.display(),
                root_dir.display()
            ));
            // No source span exists for an unresolvable import (the
            // problem is that we can't even find the *other* file, not
            // anything about text already in hand) - `check`/`ai`/`json`
            // all still render a codeless-span diagnostic fine (AXDL
            // prints `-` in place of a location, see `docs/diagnostics.md`).
            print_diagnostics(vec![diag], "<import>", "", format);
            return Err(format!(
                "cannot resolve import `{}`: no such file '{}'",
                dotted,
                path.display()
            ));
        }

        let canonical = path.canonicalize().unwrap_or_else(|_| path.clone());
        if !visited.insert(canonical) {
            // Already merged (either directly, or as some other module's
            // own transitive import) - a diamond import, not a cycle
            // error: importing the same module twice (directly or
            // indirectly) is completely ordinary and should just be a
            // no-op the second time.
            continue;
        }

        let file_id = registry.add(path.display().to_string(), String::new());
        let imported_module = parse_module_file(&path, file_id, format)?;
        // Backfill the real source text now that we know it parsed -
        // `parse_module_file` already read it once; re-reading here
        // keeps `parse_module_file` self-contained (it prints its own
        // diagnostics against the file it just read) without needing to
        // thread the source string back out through its `Result`.
        if let Ok(source) = fs::read_to_string(&path) {
            registry.files[file_id].1 = source;
        }

        // Resolve this module's *own* imports (still relative to
        // `root_dir`, not `path`) before appending its decls, so
        // transitive imports always land before the things that depend
        // on them in `out` (cosmetic - `axiom-sema`'s two-pass checker
        // doesn't care about declaration order - but it keeps
        // `--dump`-style output and mental models straightforward).
        resolve_imports_into(
            root_dir,
            &imported_module.imports,
            format,
            registry,
            visited,
            out,
        )?;

        if names.is_empty() {
            out.extend(imported_module.decls);
        } else {
            let wanted: HashSet<&str> = names.iter().map(|i| i.name.as_str()).collect();
            out.extend(
                imported_module
                    .decls
                    .into_iter()
                    .filter(|d| decl_name(d).is_some_and(|n| wanted.contains(n))),
            );
        }
    }

    Ok(())
}

/// Entry point for import resolution: given the already-parsed entry
/// module, merge every transitively `(import ...)`ed file's declarations
/// into it. A no-op (and doesn't touch `registry` beyond the entry file
/// already registered by the caller) when the entry file has no imports.
fn resolve_imports(
    entry_path: &Path,
    module: &mut axiom_ast::Module,
    format: DiagnosticFormat,
    registry: &mut FileRegistry,
) -> Result<(), String> {
    if module.imports.is_empty() {
        return Ok(());
    }

    let base_dir = entry_path
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."));
    let mut visited = HashSet::new();
    if let Ok(canonical) = entry_path.canonicalize() {
        visited.insert(canonical);
    }

    let mut imported_decls = Vec::new();
    resolve_imports_into(
        &base_dir,
        &module.imports,
        format,
        registry,
        &mut visited,
        &mut imported_decls,
    )?;

    // Imported declarations first, then the entry file's own - purely
    // for readability of anything that dumps `module.decls` back out;
    // `axiom-sema`'s two-pass checker (collect every declaration, then
    // check every body) doesn't care about order either way, so this
    // can't change which programs type-check.
    imported_decls.extend(std::mem::take(&mut module.decls));
    module.decls = imported_decls;
    Ok(())
}

/// Run the lexer, parser and type checker on `source`, printing any
/// diagnostics in `format`. Returns the checked AST and type checker on
/// success. This is shared by `build` and `check` so the two commands can
/// never drift apart in how they report errors.
///
/// When `announce` is set, prints a `[stage/5]` progress line immediately
/// before each stage actually runs (not all up front) so a failure in an
/// early stage doesn't misleadingly claim later stages happened too.
///
/// Resolves `(import ...)` declarations (see `resolve_imports`) between
/// parsing and type-checking: every file that ends up contributing
/// declarations (the entry file plus every transitively imported module)
/// is tracked in the returned [`FileRegistry`], so that a type error
/// anywhere in the merged program is still reported against the actual
/// file and source line it came from, not always against `input`, and so
/// that callers needing to attribute their own per-declaration output
/// back to the right file (e.g. `axiom symbols`, see `collect_symbol_facts`)
/// can do the same instead of only `analyze` itself being multi-file-aware.
fn analyze(
    input: &str,
    source: &str,
    format: DiagnosticFormat,
    announce: bool,
) -> Result<(axiom_ast::Module, TypeChecker, FileRegistry), String> {
    let mut registry = FileRegistry::new();
    let entry_file_id = registry.add(input.to_string(), source.to_string());

    if announce {
        println!("[1/5] Lexing...");
    }
    let mut lexer = Lexer::new(source, entry_file_id);
    let tokens = match lexer.tokenize() {
        Ok(tokens) => tokens,
        Err(e) => {
            print_diagnostics(vec![e.to_diagnostic()], input, source, format);
            return Err("compilation failed due to a lexer error".to_string());
        }
    };

    if announce {
        println!("[2/5] Parsing...");
    }
    let mut parser = Parser::new(tokens);
    let mut ast = match parser.parse_module() {
        Ok(ast) => ast,
        Err(e) => {
            print_diagnostics(vec![e.to_diagnostic()], input, source, format);
            return Err("compilation failed due to a syntax error".to_string());
        }
    };

    if !ast.imports.is_empty() {
        if announce {
            println!("[2/5] Resolving imports...");
        }
        resolve_imports(Path::new(input), &mut ast, format, &mut registry)?;
    }

    if announce {
        println!("[3/5] Type checking...");
    }
    let mut type_checker = TypeChecker::new();
    match type_checker.check(&ast) {
        Ok(()) => Ok((ast, type_checker, registry)),
        Err(errors) => {
            let diags: Vec<Diagnostic> = errors.iter().map(|e| e.to_diagnostic()).collect();
            // Cascade-dedup once up front so the count in the summary line
            // matches exactly what gets printed, instead of the old
            // behavior of reporting a raw (and often inflated) error count.
            let diags = axiom_errors::dedup(diags);
            let shown = diags.len();
            print_diagnostics_multi(&diags, &registry, format);
            Err(format!(
                "compilation failed due to {} previous error{}",
                shown,
                if shown == 1 { "" } else { "s" }
            ))
        }
    }
}

fn build(
    input: &str,
    output: &str,
    emit_llvm: bool,
    opt: u8,
    format: DiagnosticFormat,
) -> Result<(), String> {
    let source =
        fs::read_to_string(input).map_err(|e| format!("Failed to read file '{}': {}", input, e))?;

    let (ast, mut type_checker, _registry) = analyze(input, &source, format, true)?;

    println!("[4/5] Generating IR...");
    let mut ir_gen = IrGen::new();
    let ir_module = ir_gen.generate(&ast, &mut type_checker);

    let has_main = ir_module.functions.iter().any(|f| f.name == "main");
    if !has_main {
        let diag = Diagnostic::error(
            &axiom_errors::code::MISSING_MAIN,
            "no `main` function found",
        )
        .with_help("add `(:: main Int)` and `(define main ...)` as the program entry point");
        print_diagnostics(vec![diag], input, &source, format);
        return Err("compilation failed: missing entry point".to_string());
    }

    println!("[5/5] Generating LLVM IR...");
    let mut codegen = LlvmCodeGen::new();
    let llvm_ir = codegen.compile(&ir_module)?;

    let ll_path = format!("{}.ll", output);
    fs::write(&ll_path, &llvm_ir).map_err(|e| format!("Failed to write LLVM IR: {}", e))?;

    if emit_llvm {
        println!("LLVM IR written to {}", ll_path);
    }

    let obj_path = format!("{}.o", output);

    let llc_status = Command::new("llc")
        .arg(&ll_path)
        .arg("-filetype=obj")
        .arg("-o")
        .arg(&obj_path)
        .arg(format!("-O{}", opt.clamp(0, 3)))
        .status()
        .map_err(|e| format!("Failed to run llc: {}", e))?;

    if !llc_status.success() {
        return Err("llc failed".to_string());
    }

    let cc_status = Command::new("cc")
        .arg(&obj_path)
        .arg("-o")
        .arg(output)
        .status()
        .map_err(|e| format!("Failed to run cc: {}", e))?;

    if !cc_status.success() {
        return Err("cc failed".to_string());
    }

    fs::remove_file(&obj_path).ok();

    println!("Build successful: {}", output);
    Ok(())
}

/// Build and run `input`, returning the *program's own* exit code - not
/// just whether it happened to be zero.
///
/// Previously this returned `Result<(), String>` and treated any nonzero
/// exit as a CLI-level failure (`Err(format!("Program exited with
/// status: {status}"))`), which `main` then printed and replaced with a
/// flat `std::process::exit(1)` - so `axiom run prog.ax` could never
/// surface `prog.ax`'s own exit code as `$?` for anything other than `0`,
/// even though returning a meaningful nonzero `Int` from `main` is
/// completely ordinary (every multi-value regression test written for
/// this compiler does exactly that). `Err` is now reserved for genuine
/// CLI-level failures: the build itself failing, the resulting binary
/// failing to spawn at all, or the process being killed by a signal
/// (which has no numeric exit code to propagate).
fn run(input: &str, args: &[String], format: DiagnosticFormat) -> Result<i32, String> {
    let output = "axiom_temp_output";
    build(input, output, false, 0, format)?;

    let mut cmd = Command::new(format!("./{}", output));
    for arg in args {
        cmd.arg(arg);
    }

    let status = cmd
        .status()
        .map_err(|e| format!("Failed to run program: {}", e))?;

    fs::remove_file(output).ok();

    status
        .code()
        .ok_or_else(|| format!("Program terminated by signal: {}", status))
}

fn check(input: &str, format: DiagnosticFormat) -> Result<(), String> {
    let source =
        fs::read_to_string(input).map_err(|e| format!("Failed to read file '{}': {}", input, e))?;

    analyze(input, &source, format, false)?;
    Ok(())
}

/// A struct/union's `repr`/`packed`/`align` attribute, formatted as one
/// `#`-meta value (`packed`, `repr=C`, or `align=16`) - `None` for the
/// default (no attribute) layout. Layout attributes affect a type's ABI,
/// so surfacing them is the difference between an agent knowing a type's
/// exact wire/FFI shape from one AXSYM line versus having to re-read the
/// declaration to find out it even has a non-default layout at all.
fn repr_meta(repr: &Option<axiom_ast::ast::TypeRepr>) -> Option<String> {
    use axiom_ast::ast::TypeRepr;
    match repr {
        None => None,
        Some(TypeRepr::Packed) => Some("packed".to_string()),
        Some(TypeRepr::C) => Some("repr=C".to_string()),
        Some(TypeRepr::Align(n)) => Some(format!("align={}", n)),
    }
}

/// Format a struct/union's fields (or a trait's methods) as
/// `name:Type,name:Type,...` for a `#fields=`/`#methods=` meta value - the
/// actual shapes, not just a count, so an agent can see a type's exact
/// layout (or a trait's exact method set) from the AXSYM line alone.
fn fields_meta(fields: &[(String, TypeId)]) -> String {
    fields
        .iter()
        .map(|(name, ty)| format!("{}:{}", name, ty))
        .collect::<Vec<_>>()
        .join(",")
}

/// Collect every top-level symbol `axiom-sema` recorded for `module` into
/// the notation-agnostic [`SymbolFact`] list that all three renderers
/// share, then print it in `format`. See `axiom_errors::symbols` for the
/// AXSYM grammar and rationale.
///
/// Locations are recovered by name from `module.decls` rather than
/// threaded through `TypeChecker` itself: the checker's `functions` /
/// `data_types` / `structs` / `traits` vectors exist to answer "what is
/// `foo`'s type", not "where is `foo`", so a fact with no matching
/// top-level declaration (Axiom's dozen built-in operators) simply gets
/// `span: None` - the AXSYM renderer prints `-` for those rather than a
/// fabricated location.
fn collect_symbol_facts(
    module: &axiom_ast::Module,
    tc: &TypeChecker,
    include_builtins: bool,
) -> Vec<SymbolFact> {
    use axiom_ast::ast::Decl;
    use std::collections::HashMap;

    let mut fn_spans: HashMap<&str, axiom_ast::span::Span> = HashMap::new();
    let mut type_spans: HashMap<&str, axiom_ast::span::Span> = HashMap::new();
    let mut trait_spans: HashMap<&str, axiom_ast::span::Span> = HashMap::new();
    let mut ctor_spans: HashMap<&str, axiom_ast::span::Span> = HashMap::new();
    let mut struct_reprs: HashMap<&str, &Option<axiom_ast::ast::TypeRepr>> = HashMap::new();

    let mut decl_meta: HashMap<String, (Option<String>, Vec<String>)> = HashMap::new();
    for decl in &module.decls {
        let (name, nid, axtags) = match decl {
            Decl::DSig {
                name, nid, axtags, ..
            } => (name, nid, axtags),
            Decl::DFn {
                name, nid, axtags, ..
            } => (name, nid, axtags),
            Decl::DForeign {
                name, nid, axtags, ..
            } => (name, nid, axtags),
            Decl::DData {
                name, nid, axtags, ..
            } => (name, nid, axtags),
            Decl::DStruct {
                name, nid, axtags, ..
            } => (name, nid, axtags),
            Decl::DUnion {
                name, nid, axtags, ..
            } => (name, nid, axtags),
            Decl::DType {
                name, nid, axtags, ..
            } => (name, nid, axtags),
            Decl::DTrait {
                name, nid, axtags, ..
            } => (name, nid, axtags),
            _ => continue,
        };
        let axtag_meta: Vec<String> = axtags
            .iter()
            .filter_map(|a| match &a.value {
                Some(v) if !v.is_empty() => Some(format!("{}={}", a.key, v)),
                _ => Some(a.key.clone()),
            })
            .collect();
        match decl_meta.entry(name.name.clone()) {
            std::collections::hash_map::Entry::Occupied(mut e) => {
                let old = e.get().clone();
                let new_nid = nid.clone().or(old.0);
                let new_meta = if axtag_meta.is_empty() {
                    old.1
                } else {
                    axtag_meta
                };
                e.insert((new_nid, new_meta));
            }
            std::collections::hash_map::Entry::Vacant(e) => {
                e.insert((nid.clone(), axtag_meta));
            }
        }
    }

    for decl in &module.decls {
        match decl {
            // A `(:: name Type)` signature is the most useful anchor for a
            // function's location (it's usually right above the
            // definition and states the type the fact is about), so it
            // takes priority; `entry` leaves an existing `DFn`/`DForeign`
            // span alone only if the signature is missing.
            Decl::DSig { name, .. } => {
                fn_spans.insert(&name.name, name.span);
            }
            Decl::DFn { name, .. } => {
                fn_spans.entry(&name.name).or_insert(name.span);
            }
            Decl::DForeign { name, .. } => {
                fn_spans.entry(&name.name).or_insert(name.span);
            }
            Decl::DData {
                name, constructors, ..
            } => {
                type_spans.insert(&name.name, name.span);
                // `DataConInfo` (the `TypeChecker`-side record) has no
                // span of its own - only the AST's own `DataCon` does -
                // so constructor locations have to come from here, not
                // from `tc.data_types`, or every constructor would
                // render with no location at all (indistinguishable from
                // an actual builtin in the AXSYM/human output).
                for con in constructors {
                    ctor_spans.insert(&con.name.name, con.name.span);
                }
            }
            Decl::DStruct { name, repr, .. } => {
                type_spans.insert(&name.name, name.span);
                struct_reprs.insert(&name.name, repr);
            }
            Decl::DUnion { name, .. } => {
                type_spans.insert(&name.name, name.span);
            }
            Decl::DType { name, .. } => {
                type_spans.insert(&name.name, name.span);
            }
            Decl::DTrait { name, .. } => {
                trait_spans.insert(&name.name, name.span);
            }
            _ => {}
        }
    }

    let mut facts = Vec::new();

    for f in &tc.functions {
        if f.is_builtin && !include_builtins {
            continue;
        }
        let kind = if f.foreign_symbol.is_some() {
            SymbolKind::Foreign
        } else {
            SymbolKind::Fn
        };
        let mut fact = SymbolFact::new(
            kind,
            &f.name,
            fn_spans.get(f.name.as_str()).copied(),
            f.ty.to_string(),
            decl_meta.get(f.name.as_str()).and_then(|(n, _)| n.clone()),
        );
        if let Some(symbol) = &f.foreign_symbol {
            fact = fact.with_meta(format!("symbol={}", symbol));
        }
        if let Some((_, axtags)) = decl_meta.get(f.name.as_str()) {
            for m in axtags {
                fact = fact.with_meta(m.clone());
            }
        }
        facts.push(fact);
    }

    for d in &tc.data_types {
        let ctor_names: Vec<String> = d.constructors.iter().map(|c| c.name.clone()).collect();
        let mut fact = SymbolFact::new(
            SymbolKind::Data,
            &d.name,
            type_spans.get(d.name.as_str()).copied(),
            format!("data {}", d.name),
            decl_meta.get(d.name.as_str()).and_then(|(n, _)| n.clone()),
        );
        if !ctor_names.is_empty() {
            fact = fact.with_meta(format!("ctors={}", ctor_names.join(",")));
        }
        if let Some((_, axtags)) = decl_meta.get(d.name.as_str()) {
            for m in axtags {
                fact = fact.with_meta(m.clone());
            }
        }
        facts.push(fact);
        for c in &d.constructors {
            facts.push(
                SymbolFact::new(
                    SymbolKind::Ctor,
                    &c.name,
                    ctor_spans.get(c.name.as_str()).copied(),
                    c.ty.to_string(),
                    None,
                )
                .with_meta(format!("of={}", c.data_type)),
            );
        }
    }

    for s in &tc.structs {
        let mut fact = SymbolFact::new(
            SymbolKind::Struct,
            &s.name,
            type_spans.get(s.name.as_str()).copied(),
            format!("struct {}", s.name),
            decl_meta.get(s.name.as_str()).and_then(|(n, _)| n.clone()),
        )
        .with_meta(format!("fields={}", fields_meta(&s.fields)));
        if let Some(repr) = repr_meta(struct_reprs.get(s.name.as_str()).copied().unwrap_or(&None)) {
            fact = fact.with_meta(repr);
        }
        if let Some((_, axtags)) = decl_meta.get(s.name.as_str()) {
            for m in axtags {
                fact = fact.with_meta(m.clone());
            }
        }
        facts.push(fact);
    }

    for u in &tc.unions {
        let mut fact = SymbolFact::new(
            SymbolKind::Union,
            &u.name,
            type_spans.get(u.name.as_str()).copied(),
            format!("union {}", u.name),
            decl_meta.get(u.name.as_str()).and_then(|(n, _)| n.clone()),
        )
        .with_meta(format!("fields={}", fields_meta(&u.fields)));
        if let Some((_, axtags)) = decl_meta.get(u.name.as_str()) {
            for m in axtags {
                fact = fact.with_meta(m.clone());
            }
        }
        facts.push(fact);
    }

    for a in &tc.aliases {
        let mut fact = SymbolFact::new(
            SymbolKind::Alias,
            &a.name,
            type_spans.get(a.name.as_str()).copied(),
            format!("{}", a.target),
            decl_meta.get(a.name.as_str()).and_then(|(n, _)| n.clone()),
        );
        if !a.tyvars.is_empty() {
            fact = fact.with_meta(format!("tyvars={}", a.tyvars.join(",")));
        }
        if let Some((_, axtags)) = decl_meta.get(a.name.as_str()) {
            for m in axtags {
                fact = fact.with_meta(m.clone());
            }
        }
        facts.push(fact);
    }

    for t in &tc.traits {
        let mut fact = SymbolFact::new(
            SymbolKind::Trait,
            &t.name,
            trait_spans.get(t.name.as_str()).copied(),
            format!("trait {}", t.name),
            decl_meta.get(t.name.as_str()).and_then(|(n, _)| n.clone()),
        )
        .with_meta(format!("methods={}", fields_meta(&t.methods)));
        if let Some((_, axtags)) = decl_meta.get(t.name.as_str()) {
            for m in axtags {
                fact = fact.with_meta(m.clone());
            }
        }
        facts.push(fact);
    }

    facts
}

/// Human table: same three facts as every other renderer (kind, name,
/// type) plus a `file:line:col` location using the exact same
/// [`SourceMap`](axiom_errors::SourceMap) AXDL and AXSYM both use, rather
/// than a raw, human-meaningless character offset.
///
/// `filename`/`source` are for exactly the one fact being rendered (see
/// `render_symbols_multi` below) - a program with `(import ...)`ed
/// declarations can have facts from several different files in the same
/// `facts` list, so there is no single "the" filename/source for a whole
/// batch of facts the way there was before imports existed.
fn render_symbols_human(f: &SymbolFact, filename: &str, source: &str) -> String {
    let map = axiom_errors::SourceMap::new(source);
    let loc = match f.span {
        Some(span) => {
            let (start, _) = map.span_range(source, span.start, span.end.max(span.start));
            format!("{}:{}:{}", filename, start.0, start.1)
        }
        None => "builtin".to_string(),
    };
    format!(
        "{:<8} {:<20} {:<40} [{}]\n",
        format!("{:?}", f.kind),
        f.name,
        f.ty,
        loc
    )
}

fn render_symbols_json(f: &SymbolFact, filename: &str, source: &str) -> String {
    let map = axiom_errors::SourceMap::new(source);
    let loc = match f.span {
        Some(span) => {
            let (start, end) = map.span_range(source, span.start, span.end.max(span.start));
            format!(
                "\"file\":\"{}\",\"span\":{{\"start\":{{\"line\":{},\"col\":{}}},\"end\":{{\"line\":{},\"col\":{}}}}},",
                axiom_errors::json_escape(filename), start.0, start.1, end.0, end.1
            )
        }
        None => String::new(),
    };
    format!(
        "{{\"kind\":\"{:?}\",\"name\":\"{}\",{}\"type\":\"{}\",{}\"meta\":[{}]}}\n",
        f.kind,
        axiom_errors::json_escape(&f.name),
        loc,
        axiom_errors::json_escape(&f.ty),
        f.nid
            .as_ref()
            .map(|n| format!("\"nid\":\"{}\",", axiom_errors::json_escape(n)))
            .unwrap_or_default(),
        f.meta
            .iter()
            .map(|m| format!("\"{}\"", axiom_errors::json_escape(m)))
            .collect::<Vec<_>>()
            .join(",")
    )
}

/// Render every fact against the specific file its own span's `file_id`
/// names (via `registry`), exactly like [`print_diagnostics_multi`] does
/// for diagnostics - so `axiom symbols` on a program with `(import ...)`s
/// reports each imported declaration's true file and location instead of
/// always attributing every fact to the entry file, regardless of which
/// file actually declared it. Facts with no span (builtin operators) don't
/// reference a filename/source at all, so which file's text they're
/// nominally rendered "against" is irrelevant for them.
fn render_symbols_multi(
    facts: &[SymbolFact],
    registry: &FileRegistry,
    format: DiagnosticFormat,
) -> String {
    let mut out = String::new();
    for f in facts {
        let file_id = f.span.map(|s| s.file_id).unwrap_or(0);
        let (filename, source) = registry.get(file_id);
        out.push_str(&match format {
            DiagnosticFormat::Ai => {
                axiom_errors::render_symbols_ai(std::slice::from_ref(f), filename, source)
            }
            DiagnosticFormat::Json => render_symbols_json(f, filename, source),
            DiagnosticFormat::Human => render_symbols_human(f, filename, source),
        });
    }
    out
}

fn symbols(input: &str, format: DiagnosticFormat, include_builtins: bool) -> Result<(), String> {
    let source =
        fs::read_to_string(input).map_err(|e| format!("Failed to read file '{}': {}", input, e))?;

    let (ast, type_checker, registry) = analyze(input, &source, format, false)?;
    let facts = collect_symbol_facts(&ast, &type_checker, include_builtins);

    print!("{}", render_symbols_multi(&facts, &registry, format));
    Ok(())
}

fn emit_llvm(input: &str, output: Option<&str>, format: DiagnosticFormat) -> Result<(), String> {
    let source =
        fs::read_to_string(input).map_err(|e| format!("Failed to read file '{}': {}", input, e))?;

    // Previously this hand-duplicated `analyze`'s lex/parse/typecheck
    // pipeline with its own bare `format!("{}", e)`/`.join("\n")` error
    // handling instead of going through `Diagnostic`/`print_diagnostics` -
    // meaning `emit-llvm` alone, of every subcommand, never honored
    // `--diagnostic-format`, never got AXDL/JSON output, and (since it
    // never called `analyze`) could never resolve `(import ...)`
    // declarations either. Calling `analyze` fixes all three at once.
    let (ast, mut type_checker, _registry) = analyze(input, &source, format, false)?;

    let mut ir_gen = IrGen::new();
    let ir_module = ir_gen.generate(&ast, &mut type_checker);

    let mut codegen = LlvmCodeGen::new();
    let llvm_ir = codegen.compile(&ir_module)?;

    match output {
        Some(path) => {
            fs::write(path, &llvm_ir).map_err(|e| format!("Failed to write LLVM IR: {}", e))?;
            println!("LLVM IR written to {}", path);
        }
        None => println!("{}", llvm_ir),
    }

    Ok(())
}

fn fmt(input: &str, check: bool) -> Result<(), String> {
    let source =
        fs::read_to_string(input).map_err(|e| format!("Failed to read file '{}': {}", input, e))?;

    let mut lexer = Lexer::new(&source, 0);
    let tokens = lexer
        .tokenize()
        .map_err(|e| format!("Lexer error: {}", e))?;

    let mut parser = Parser::new(tokens);
    let ast = parser
        .parse_module()
        .map_err(|e| format!("Parser error: {}", e))?;

    let formatted = fmt::format_module(&ast);

    if check {
        if source == formatted {
            println!(
                "{} {} is already formatted",
                "OK:".bright_green().bold(),
                input.bright_white()
            );
        } else {
            println!(
                "{} {} needs formatting",
                "Error:".bright_red().bold(),
                input.bright_white()
            );
            std::process::exit(1);
        }
    } else {
        fs::write(input, &formatted)
            .map_err(|e| format!("Failed to write formatted file: {}", e))?;
        println!(
            "{} {} formatted",
            "OK:".bright_green().bold(),
            input.bright_white()
        );
    }

    Ok(())
}

// ============================================================
// REPL Implementation
// ============================================================

struct ReplState {
    type_checker: TypeChecker,
    declarations: String,
    line_count: usize,
    history_file: String,
}

impl ReplState {
    fn new() -> Self {
        let history_file = dirs::config_dir()
            .map(|d| d.join("axiom").join("repl_history"))
            .and_then(|p| p.to_str().map(|s| s.to_string()))
            .unwrap_or_else(|| ".axiom_repl_history".to_string());

        Self {
            type_checker: TypeChecker::new(),
            declarations: String::new(),
            line_count: 0,
            history_file,
        }
    }
}

fn repl(no_banner: bool) {
    if !no_banner {
        print_banner();
    }

    let mut state = ReplState::new();
    let mut rl = DefaultEditor::new().expect("Failed to create REPL editor");

    if rl.load_history(&state.history_file).is_err() {
        // First time, no history file
    }

    loop {
        let prompt = format!(
            "{} {} ",
            "axiom>".bright_blue().bold(),
            state.line_count + 1
        );

        match rl.readline(&prompt) {
            Ok(line) => {
                let line = line.trim().to_string();
                if line.is_empty() || line.starts_with(';') {
                    continue;
                }

                rl.add_history_entry(&line).ok();

                if line.starts_with(':') {
                    handle_command(&line, &mut state);
                } else {
                    process_input(&line, &mut state);
                }

                state.line_count += 1;
            }
            Err(ReadlineError::Interrupted) => {
                println!("\nUse :quit to exit, or :help for commands.");
            }
            Err(ReadlineError::Eof) => {
                println!();
                break;
            }
            Err(err) => {
                eprintln!("Read error: {:?}", err);
                break;
            }
        }
    }

    rl.save_history(&state.history_file).ok();
    println!("{}", "Goodbye!".bright_yellow());
}

fn print_banner() {
    println!(
        "{}",
        "╔═══════════════════════════════════════════════════════════╗".bright_cyan()
    );
    println!(
        "{}",
        "║                                                           ║".bright_cyan()
    );
    println!(
        "{}",
        format!(
            "║   Axiom v{} - Functional Systems Language              ║",
            env!("CARGO_PKG_VERSION")
        )
        .bright_cyan()
    );
    println!(
        "{}",
        "║                                                           ║".bright_cyan()
    );
    println!(
        "{}",
        "║   Type :help for commands, :quit to exit                 ║".bright_cyan()
    );
    println!(
        "{}",
        "║                                                           ║".bright_cyan()
    );
    println!(
        "{}",
        "╚═══════════════════════════════════════════════════════════╝".bright_cyan()
    );
    println!();
}

fn handle_command(line: &str, state: &mut ReplState) {
    let parts: Vec<&str> = line.split_whitespace().collect();
    let cmd = parts.first().unwrap_or(&"");

    match *cmd {
        ":help" | ":h" | "?" => show_help(),
        ":quit" | ":q" | ":exit" => std::process::exit(0),
        ":type" | ":t" => cmd_type(&parts[1..].join(" "), state),
        ":load" | ":l" => cmd_load(&parts[1..].join(" "), state),
        ":reset" | ":r" => cmd_reset(state),
        ":defs" | ":d" => cmd_defs(state),
        ":llvm" => cmd_llvm(&parts[1..].join(" "), state),
        ":time" => cmd_time(&parts[1..].join(" "), state),
        _ => {
            println!(
                "{} Unknown command '{}'. Type :help for available commands.",
                "Error:".bright_red().bold(),
                cmd.bright_yellow()
            );
        }
    }
}

fn show_help() {
    println!();
    println!("{}", "Available Commands:".bold().bright_cyan());
    println!(
        "  {}     Show this help message",
        ":help, :h, ?".bright_green()
    );
    println!("  {}      Exit the REPL", ":quit, :q, :exit".bright_green());
    println!(
        "  {} <expr>  Show the type of an expression",
        ":type, :t".bright_green()
    );
    println!(
        "  {} <file>  Load a file into the REPL",
        ":load, :l".bright_green()
    );
    println!(
        "  {}        Reset the REPL state",
        ":reset, :r".bright_green()
    );
    println!(
        "  {}       Show all definitions in scope",
        ":defs, :d".bright_green()
    );
    println!(
        "  {} <expr>  Show generated LLVM IR",
        ":llvm".bright_green()
    );
    println!(
        "  {} <expr>  Time expression evaluation",
        ":time".bright_green()
    );
    println!();
    println!("{}", "Tips:".bold().bright_cyan());
    println!(
        "  • Define functions: {}",
        "(define (add x y) (+ x y))".bright_white()
    );
    println!(
        "  • Type signatures: {}",
        "(:: add (-> Int Int Int))".bright_white()
    );
    println!(
        "  • Data types: {}",
        "(data Maybe (a) (Nothing) (Just a))".bright_white()
    );
    println!("  • Expressions are evaluated and results shown");
    println!("  • Use ; for line comments");
    println!("  • Use arrow keys for history, Ctrl+C to cancel input");
    println!();
}

fn cmd_type(expr_str: &str, state: &mut ReplState) {
    if expr_str.is_empty() {
        println!("{} Usage: :type <expression>", "Error:".bright_red().bold());
        return;
    }

    let mut lexer = Lexer::new(expr_str, 0);
    let tokens = match lexer.tokenize() {
        Ok(t) => t,
        Err(e) => {
            println!("{} {}", "Lexer error:".bright_red(), e);
            return;
        }
    };

    let mut parser = Parser::new(tokens);
    let expr = match parser.parse_expr() {
        Ok(e) => e,
        Err(e) => {
            println!("{} {}", "Parse error:".bright_red(), e);
            return;
        }
    };

    let mut tc = TypeChecker::new();
    // Re-register all accumulated declarations
    re_register_decls(&state.declarations, &mut tc);

    match tc.check_single_expr(&expr) {
        Ok(ty) => {
            println!(
                "{} : {}",
                expr_str.bright_white(),
                ty.to_string().bright_cyan()
            );
        }
        Err(errors) => {
            for error in &errors {
                println!("{} {}", "Type error:".bright_red(), error);
            }
        }
    }
}

fn cmd_load(file: &str, state: &mut ReplState) {
    if file.is_empty() {
        println!("{} Usage: :load <filename>", "Error:".bright_red().bold());
        return;
    }

    match fs::read_to_string(file) {
        Ok(source) => {
            let mut lexer = Lexer::new(&source, 0);
            let tokens = match lexer.tokenize() {
                Ok(t) => t,
                Err(e) => {
                    println!("{} {}", "Lexer error:".bright_red(), e);
                    return;
                }
            };

            let mut parser = Parser::new(tokens);
            let ast = match parser.parse_module() {
                Ok(a) => a,
                Err(e) => {
                    println!("{} {}", "Parse error:".bright_red(), e);
                    return;
                }
            };

            let mut tc = TypeChecker::new();
            match tc.check(&ast) {
                Ok(()) => {
                    state.declarations.push_str(&source);
                    state.declarations.push('\n');
                    // Merge the type checker state
                    merge_type_checker(&tc, state);
                    println!(
                        "{} Loaded '{}'",
                        "OK:".bright_green().bold(),
                        file.bright_white()
                    );
                }
                Err(errors) => {
                    for error in &errors {
                        println!("{} {}", "Type error:".bright_red(), error);
                    }
                }
            }
        }
        Err(e) => {
            println!("{} {}", "File error:".bright_red(), e);
        }
    }
}

fn cmd_reset(state: &mut ReplState) {
    state.type_checker = TypeChecker::new();
    state.declarations.clear();
    state.line_count = 0;
    println!("{}", "REPL state reset.".bright_yellow());
}

fn cmd_defs(state: &mut ReplState) {
    println!("{}", "Definitions in scope:".bold().bright_cyan());

    let mut tc = TypeChecker::new();
    re_register_decls(&state.declarations, &mut tc);

    for fn_info in &tc.functions {
        if !fn_info.name.starts_with("__") && !fn_info.name.starts_with("_fn_") {
            println!(
                "  {} : {}",
                fn_info.name.bright_white(),
                fn_info.ty.to_string().bright_cyan()
            );
        }
    }

    for dt in &tc.data_types {
        println!(
            "  data {} with {} constructors",
            dt.name.bright_white(),
            dt.constructors.len()
        );
        for con in &dt.constructors {
            println!(
                "    {} : {}",
                con.name.bright_green(),
                con.ty.to_string().bright_cyan()
            );
        }
    }
}

fn cmd_llvm(expr_str: &str, state: &mut ReplState) {
    if expr_str.is_empty() {
        println!("{} Usage: :llvm <expression>", "Error:".bright_red().bold());
        return;
    }

    let mut lexer = Lexer::new(expr_str, 0);
    let tokens = match lexer.tokenize() {
        Ok(t) => t,
        Err(e) => {
            println!("{} {}", "Lexer error:".bright_red(), e);
            return;
        }
    };

    let mut parser = Parser::new(tokens);
    let result = match parser.parse_decl_or_expr() {
        Ok(r) => Some(r),
        Err(e) => {
            println!("{} {}", "Parse error:".bright_red(), e);
            return;
        }
    };

    match result {
        Some(DeclOrExpr::Decl(_decl)) => {
            let wrapper = format!("{}\n{}", state.declarations, expr_str);
            let mut lexer = Lexer::new(&wrapper, 0);
            if let Ok(tokens) = lexer.tokenize() {
                let mut parser = Parser::new(tokens);
                if let Ok(ast) = parser.parse_module() {
                    let mut tc2 = TypeChecker::new();
                    if tc2.check(&ast).is_ok() {
                        let mut ir_gen = IrGen::new();
                        let ir_module = ir_gen.generate(&ast, &mut tc2);

                        let mut codegen = LlvmCodeGen::new();
                        if let Ok(llvm_ir) = codegen.compile(&ir_module) {
                            println!("{}", "Generated LLVM IR:".bold().bright_cyan());
                            println!("{}", llvm_ir);
                        }
                    }
                }
            }
        }
        Some(DeclOrExpr::Expr(expr)) => {
            let mut tc = TypeChecker::new();
            re_register_decls(&state.declarations, &mut tc);

            if let Ok(ty) = tc.check_single_expr(&expr) {
                let wrapper = format!(
                    "(foreign printf :: (-> String Int Int) = \"printf\")\n(foreign puts :: (-> String Int) = \"puts\")\n{}\n(:: __repl_result (-> Int {}))\n(define (__repl_result _dummy) {})\n(:: main Int)\n(define main {{ (printf \"%ld\\n\" (__repl_result 0)) 0 }})",
                    state.declarations,
                    ty,
                    expr_str,
                );

                let mut lexer = Lexer::new(&wrapper, 0);
                if let Ok(tokens) = lexer.tokenize() {
                    let mut parser = Parser::new(tokens);
                    if let Ok(ast) = parser.parse_module() {
                        let mut tc2 = TypeChecker::new();
                        if tc2.check(&ast).is_ok() {
                            let mut ir_gen = IrGen::new();
                            let ir_module = ir_gen.generate(&ast, &mut tc2);

                            let mut codegen = LlvmCodeGen::new();
                            if let Ok(llvm_ir) = codegen.compile(&ir_module) {
                                println!("{}", "Generated LLVM IR:".bold().bright_cyan());
                                println!("{}", llvm_ir);
                            }
                        }
                    }
                }
            }
        }
        None => {}
    }
}

fn cmd_time(expr_str: &str, state: &mut ReplState) {
    if expr_str.is_empty() {
        println!("{} Usage: :time <expression>", "Error:".bright_red().bold());
        return;
    }

    let mut lexer = Lexer::new(expr_str, 0);
    let tokens = match lexer.tokenize() {
        Ok(t) => t,
        Err(e) => {
            println!("{} {}", "Lexer error:".bright_red(), e);
            return;
        }
    };

    let mut parser = Parser::new(tokens);
    let result = match parser.parse_decl_or_expr() {
        Ok(r) => Some(r),
        Err(e) => {
            println!("{} {}", "Parse error:".bright_red(), e);
            return;
        }
    };

    match result {
        Some(DeclOrExpr::Decl(decl)) => {
            let start = std::time::Instant::now();
            state.type_checker.register_decl(&decl);
            state.declarations.push_str(expr_str);
            state.declarations.push('\n');
            let duration = start.elapsed();
            println!("{} {:?}", "Time:".bright_yellow(), duration);
            if let axiom_ast::ast::Decl::DFn { name, .. } = &decl {
                println!(
                    "{} {} defined",
                    "OK:".bright_green().bold(),
                    name.name.bright_white()
                );
            } else {
                println!("{}", "OK".bright_green().bold());
            }
        }
        Some(DeclOrExpr::Expr(expr)) => {
            let mut tc = TypeChecker::new();
            re_register_decls(&state.declarations, &mut tc);

            match tc.check_single_expr(&expr) {
                Ok(ty) => {
                    println!(
                        "{} : {}",
                        "type".bright_yellow(),
                        ty.to_string().bright_cyan()
                    );

                    let wrapper = generate_repl_wrapper(&state.declarations, expr_str, &ty);

                    let mut lexer = Lexer::new(&wrapper, 0);
                    if let Ok(tokens) = lexer.tokenize() {
                        let mut parser = Parser::new(tokens);
                        if let Ok(ast) = parser.parse_module() {
                            let mut tc2 = TypeChecker::new();
                            if tc2.check(&ast).is_ok() {
                                let mut ir_gen = IrGen::new();
                                let ir_module = ir_gen.generate(&ast, &mut tc2);

                                let mut codegen = LlvmCodeGen::new();
                                if let Ok(llvm_ir) = codegen.compile(&ir_module) {
                                    let start = std::time::Instant::now();
                                    let result = compile_and_run_repl(&llvm_ir);
                                    let duration = start.elapsed();

                                    if let Some(value) = result {
                                        println!(
                                            "{} {}",
                                            "result".bright_green(),
                                            value.bright_white()
                                        );
                                    }
                                    println!("{} {:?}", "Time:".bright_yellow(), duration);
                                }
                            }
                        }
                    }
                }
                Err(errors) => {
                    for error in &errors {
                        println!("{} {}", "Type error:".bright_red(), error);
                    }
                }
            }
        }
        None => {}
    }
}

fn process_input(input: &str, state: &mut ReplState) {
    let mut lexer = Lexer::new(input, 0);
    let tokens = match lexer.tokenize() {
        Ok(t) => t,
        Err(e) => {
            println!("{} {}", "Lexer error:".bright_red(), e);
            return;
        }
    };

    let mut parser = Parser::new(tokens);
    let result = match parser.parse_decl_or_expr() {
        Ok(r) => Some(r),
        Err(e) => {
            println!("{} {}", "Parse error:".bright_red(), e);
            return;
        }
    };

    match result {
        Some(DeclOrExpr::Decl(decl)) => {
            let mut tc = TypeChecker::new();
            re_register_decls(&state.declarations, &mut tc);

            state.type_checker.register_decl(&decl);
            state.declarations.push_str(input);
            state.declarations.push('\n');

            if let axiom_ast::ast::Decl::DFn { name, .. } = &decl {
                println!(
                    "{} {} defined",
                    "OK:".bright_green().bold(),
                    name.name.bright_white()
                );
            } else if let axiom_ast::ast::Decl::DData { name, .. } = &decl {
                println!(
                    "{} data {} defined",
                    "OK:".bright_green().bold(),
                    name.name.bright_white()
                );
            } else if let axiom_ast::ast::Decl::DSig { name, .. } = &decl {
                println!(
                    "{} {} defined",
                    "OK:".bright_green().bold(),
                    name.name.bright_white()
                );
            } else {
                println!("{}", "OK".bright_green().bold());
            }
        }
        Some(DeclOrExpr::Expr(expr)) => {
            let mut tc = TypeChecker::new();
            re_register_decls(&state.declarations, &mut tc);

            match tc.check_single_expr(&expr) {
                Ok(ty) => {
                    println!(
                        "{} : {}",
                        "type".bright_yellow(),
                        ty.to_string().bright_cyan()
                    );

                    let wrapper = generate_repl_wrapper(&state.declarations, input, &ty);

                    let mut lexer = Lexer::new(&wrapper, 0);
                    if let Ok(tokens) = lexer.tokenize() {
                        let mut parser = Parser::new(tokens);
                        if let Ok(ast) = parser.parse_module() {
                            let mut tc2 = TypeChecker::new();
                            if tc2.check(&ast).is_ok() {
                                let mut ir_gen = IrGen::new();
                                let ir_module = ir_gen.generate(&ast, &mut tc2);

                                let mut codegen = LlvmCodeGen::new();
                                if let Ok(llvm_ir) = codegen.compile(&ir_module) {
                                    let result = compile_and_run_repl(&llvm_ir);
                                    if let Some(value) = result {
                                        println!(
                                            "{} {}",
                                            "result".bright_green(),
                                            value.bright_white()
                                        );
                                    }
                                }
                            }
                        }
                    }
                }
                Err(errors) => {
                    for error in &errors {
                        println!("{} {}", "Type error:".bright_red(), error);
                    }
                }
            }
        }
        None => {}
    }
}

fn generate_repl_wrapper(declarations: &str, input: &str, ty: &axiom_sema::TypeId) -> String {
    let type_str = format!("{}", ty);
    match type_str.as_str() {
        "Int" | "I64" | "U64" | "Isize" | "Usize" => {
            format!(
                "(foreign printf :: (-> String Int Int) = \"printf\")\n(foreign puts :: (-> String Int) = \"puts\")\n{}\n(:: __repl_result (-> Int Int))\n(define (__repl_result _dummy) {})\n(:: main Int)\n(define main {{ (printf \"%ld\\n\" (__repl_result 0)) 0 }})",
                declarations,
                input,
            )
        }
        "Bool" => {
            let wrapped_input = format!("(if {} 1 0)", input);
            format!(
                "(foreign printf :: (-> String Int Int) = \"printf\")\n(foreign puts :: (-> String Int) = \"puts\")\n{}\n(:: __repl_result (-> Int Int))\n(define (__repl_result _dummy) {})\n(:: main Int)\n(define main {{ (if (== (__repl_result 0) 0) {{ (puts \"false\") 0 }} {{ (puts \"true\") 0 }}) 0 }})",
                declarations,
                wrapped_input,
            )
        }
        "Char" => {
            format!(
                "(foreign printf :: (-> String Int Int) = \"printf\")\n(foreign puts :: (-> String Int) = \"puts\")\n{}\n(:: __repl_result (-> Int Int))\n(define (__repl_result _dummy) {})\n(:: main Int)\n(define main {{ (printf \"%c\\n\" (__repl_result 0)) 0 }})",
                declarations,
                input,
            )
        }
        _ => {
            format!(
                "(foreign printf :: (-> String Int Int) = \"printf\")\n(foreign puts :: (-> String Int) = \"puts\")\n{}\n(:: __repl_result (-> Int Int))\n(define (__repl_result _dummy) {})\n(:: main Int)\n(define main {{ (printf \"%ld\\n\" (__repl_result 0)) 0 }})",
                declarations,
                input,
            )
        }
    }
}

fn compile_and_run_repl(llvm_ir: &str) -> Option<String> {
    let temp_ll = "axiom_repl_temp.ll";
    let temp_out = "axiom_repl_temp";

    if fs::write(temp_ll, llvm_ir).is_err() {
        return None;
    }

    let obj_path = format!("{}.o", temp_out);
    if !Command::new("llc")
        .arg(temp_ll)
        .arg("-filetype=obj")
        .arg("-o")
        .arg(&obj_path)
        .status()
        .is_ok_and(|s| s.success())
    {
        fs::remove_file(temp_ll).ok();
        return None;
    }

    if !Command::new("cc")
        .arg(&obj_path)
        .arg("-o")
        .arg(temp_out)
        .status()
        .is_ok_and(|s| s.success())
    {
        fs::remove_file(&obj_path).ok();
        fs::remove_file(temp_ll).ok();
        return None;
    }

    let output = Command::new(format!("./{}", temp_out)).output();

    fs::remove_file(&obj_path).ok();
    fs::remove_file(temp_ll).ok();
    fs::remove_file(temp_out).ok();

    if let Ok(out) = output {
        let stdout = String::from_utf8_lossy(&out.stdout);
        let trimmed = stdout.trim().to_string();
        if !trimmed.is_empty() {
            return Some(trimmed);
        }
        if let Some(code) = out.status.code() {
            return Some(format!("{}", code));
        }
    }

    None
}

fn re_register_decls(source: &str, tc: &mut TypeChecker) {
    if source.is_empty() {
        return;
    }

    let mut lexer = Lexer::new(source, 0);
    if let Ok(tokens) = lexer.tokenize() {
        let mut parser = Parser::new(tokens);
        if let Ok(ast) = parser.parse_module() {
            let mut fresh_tc = TypeChecker::new();
            if fresh_tc.check(&ast).is_ok() {
                *tc = fresh_tc;
            } else {
                for decl in &ast.decls {
                    tc.register_decl(decl);
                }
            }
        }
    }
}

fn merge_type_checker(_source_tc: &TypeChecker, state: &mut ReplState) {
    // Simple approach: re-parse all declarations
    state.type_checker = TypeChecker::new();
    re_register_decls(&state.declarations, &mut state.type_checker);
}
