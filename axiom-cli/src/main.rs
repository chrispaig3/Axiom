use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use axiom_codegen::{LlvmCodeGen, Target};
use axiom_errors::{Diagnostic, DiagnosticFormat, SymbolFact, SymbolKind};
use axiom_ir::generator::IrGen;
use axiom_lexer::Lexer;
use axiom_ast::ast::Visibility;
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

    /// Which platform to generate code for: `darwin-aarch64`,
    /// `darwin-x86_64`, `linux-aarch64`, or `linux-x86_64`.
    /// Defaults to the host. Also selects platform-specific
    /// standard-library modules (`Foo.<os>.ax` in preference to
    /// `Foo.ax`), so cross-compiling picks up the right syscall
    /// numbers without any conditional compilation in the language.
    #[arg(long, global = true)]
    target: Option<String>,

    /// Manage memory with a tracing collector instead of the default
    /// bump allocator, so peak memory tracks live data rather than
    /// total allocation. Costs a mark-sweep pause whenever the current
    /// mapping fills; worth it for a long-running or allocation-heavy
    /// program, pointless for one that exits in milliseconds.
    #[arg(long, global = true)]
    gc: bool,

    #[command(subcommand)]
    command: Commands,
}

/// The target for this compiler run.
///
/// Set exactly once, from `--target` (or the host default) before any
/// compilation starts, and read from the several places that build a
/// code generator or resolve a module path. A process-wide value
/// rather than a parameter threaded through every function because
/// `axiom` is a single-shot process: one invocation compiles for one
/// target, and the REPL's several independent codegen sites would
/// otherwise each need the same value plumbed through unrelated
/// signatures.
static TARGET: std::sync::OnceLock<Target> = std::sync::OnceLock::new();

fn target() -> Target {
    *TARGET.get_or_init(Target::host)
}

/// Whether this run manages memory with the collector. Set once from
/// `--gc`, for the same reason `TARGET` is.
static GC: std::sync::OnceLock<bool> = std::sync::OnceLock::new();

fn gc_enabled() -> bool {
    *GC.get_or_init(|| false)
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
        #[arg(short, long, default_value = "1")]
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

/// Run the compiler on a thread with an explicitly sized stack.
///
/// Every stage from the parser on walks the syntax tree recursively, so
/// stack depth tracks nesting depth in the source. `MAX_NESTING_DEPTH`
/// bounds that depth; this bounds the stack it is allowed to consume, so
/// the bound is a property of the compiler rather than of whatever
/// `ulimit -s` the caller happened to have. Without it, the depth that
/// reports a diagnostic on one host aborts on `SIGSEGV` on another.
fn main() {
    let worker = std::thread::Builder::new()
        .name("axiom".into())
        .stack_size(axiom_parser::Parser::STACK_SIZE)
        .spawn(drive)
        .expect("failed to spawn compiler thread");
    // Propagate a panic in the worker as a non-zero exit rather than
    // unwinding into a zero status: `spawn` moves the failure out of the
    // process's exit path, and a compiler that reports success after
    // panicking is worse than one that crashes.
    match worker.join() {
        Ok(()) => {}
        Err(_) => std::process::exit(101),
    }
}

fn drive() {
    let cli = Cli::parse();
    let format = DiagnosticFormat::parse(&cli.diagnostic_format).unwrap_or_else(|| {
        eprintln!(
            "warning: unknown --diagnostic-format '{}', falling back to 'human' (valid: human, ai, json)",
            cli.diagnostic_format
        );
        DiagnosticFormat::Human
    });

    // An unknown `--target` is a hard error, not a warning that falls
    // back to the host: silently generating host code for a
    // cross-compile request would produce a binary that looks correct
    // and cannot run.
    let _ = GC.set(cli.gc);

    if let Some(name) = &cli.target {
        match Target::parse(name) {
            Some(t) => {
                let _ = TARGET.set(t);
            }
            None => {
                eprintln!(
                    "error: unknown --target '{}' (valid: {})",
                    name,
                    Target::all()
                        .iter()
                        .map(|t| t.name())
                        .collect::<Vec<_>>()
                        .join(", ")
                );
                std::process::exit(2);
            }
        }
    }

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
        | Decl::DType { name, .. }
        | Decl::DTrait { name, .. }
        | Decl::DSig { name, .. }
        | Decl::DFn { name, .. }
        | Decl::DForeign { name, .. }
        | Decl::DEffect { name, .. }
        | Decl::DMacro { name, .. } => Some(&name.name),
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

/// The relative file names `Mod.Sub` may live in, most specific first.
///
/// Beyond the plain `Mod/Sub.ax`, a module may be provided in a
/// *platform-specific* file - `Mod/Sub.linux-x86_64.ax`, or
/// `Mod/Sub.linux.ax` for a whole OS - and the most specific one that
/// exists wins. This is how the standard library supplies syscall
/// numbers (which differ per OS, and are BSD-class-encoded on Darwin)
/// without conditional compilation in the language and without a
/// syscall table baked into the compiler: `stdlib/Sys/Platform.linux.ax`
/// and `stdlib/Sys/Platform.darwin.ax` are two ordinary Axiom files,
/// and `(import Sys.Platform)` picks the right one for `--target`.
fn module_rel_path_candidates(module: &[axiom_ast::span::Ident], target: Target) -> Vec<PathBuf> {
    let base = module_rel_path(module);
    let stem = base.with_extension("");
    let (os, arch) = match target {
        Target::DarwinAarch64 => ("darwin", "aarch64"),
        Target::DarwinX86_64 => ("darwin", "x86_64"),
        Target::LinuxAarch64 => ("linux", "aarch64"),
        Target::LinuxX86_64 => ("linux", "x86_64"),
    };
    vec![
        stem.with_extension(format!("{}-{}.ax", os, arch)),
        stem.with_extension(format!("{}.ax", os)),
        base,
    ]
}

/// Every directory a module path is looked up in, in order.
///
/// The entry file's own directory always comes first, so a project can
/// shadow a standard-library module with its own file of the same name.
/// After that come `AXIOM_PATH` entries (colon-separated, for vendored
/// or generated code), then the standard library itself.
///
/// The standard library is located by `AXIOM_STDLIB` if set, and
/// otherwise relative to the compiler binary: `<exe>/../stdlib` for an
/// installed layout (`bin/axiom` next to `stdlib/`) and
/// `<exe>/../../stdlib` for a Cargo build tree (`target/release/axiom`
/// with `stdlib/` at the repository root). Both are probed because a
/// developer running `cargo run` and a user running an installed
/// compiler must both find the same standard library without extra
/// configuration.
fn module_search_dirs(entry_dir: &Path) -> Vec<PathBuf> {
    let mut dirs = vec![entry_dir.to_path_buf()];

    if let Ok(extra) = std::env::var("AXIOM_PATH") {
        for part in extra.split(':').filter(|p| !p.is_empty()) {
            dirs.push(PathBuf::from(part));
        }
    }

    if let Ok(stdlib) = std::env::var("AXIOM_STDLIB") {
        if !stdlib.is_empty() {
            dirs.push(PathBuf::from(stdlib));
        }
    } else if let Ok(exe) = std::env::current_exe() {
        if let Some(bin_dir) = exe.parent() {
            dirs.push(bin_dir.join("../stdlib"));
            dirs.push(bin_dir.join("../../stdlib"));
        }
    }

    dirs
}

/// Resolve a dotted module path to a file, or `None` if no candidate
/// exists in any search directory.
///
/// Returns the matching path together with the *relative* candidate
/// names that were tried, so an unresolved import can report what it
/// looked for rather than just that it failed.
fn resolve_module_path(
    module: &[axiom_ast::span::Ident],
    entry_dir: &Path,
    target: Target,
) -> Result<PathBuf, (Vec<PathBuf>, Vec<PathBuf>)> {
    let candidates = module_rel_path_candidates(module, target);
    let dirs = module_search_dirs(entry_dir);
    for dir in &dirs {
        for rel in &candidates {
            let path = dir.join(rel);
            if path.is_file() {
                return Ok(path);
            }
        }
    }
    Err((candidates, dirs))
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
        let path = match resolve_module_path(module, root_dir, target()) {
            Ok(path) => path,
            Err((candidates, dirs)) => {
                let diag = Diagnostic::error(
                    &axiom_errors::code::MODULE_NOT_FOUND,
                    format!("cannot resolve import `{}`", dotted),
                )
                .with_help(format!(
                    "looked for {} in {}",
                    candidates
                        .iter()
                        .map(|c| format!("'{}'", c.display()))
                        .collect::<Vec<_>>()
                        .join(" or "),
                    dirs.iter()
                        .map(|d| format!("'{}'", d.display()))
                        .collect::<Vec<_>>()
                        .join(", ")
                ));
                // No source span exists for an unresolvable import (the
                // problem is that we can't even find the *other* file,
                // not anything about text already in hand) -
                // `check`/`ai`/`json` all still render a codeless-span
                // diagnostic fine (AXDL prints `-` in place of a
                // location, see `docs/diagnostics.md`).
                print_diagnostics(vec![diag], "<import>", "", format);
                return Err(format!("cannot resolve import `{}`", dotted));
            }
        };

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
            let module_path = dotted.clone();
            for mut decl in imported_module.decls {
                // Only import public declarations
                if !matches!(
                    &decl,
                    Decl::DFn { vis: Visibility::Pub, .. }
                        | Decl::DData { vis: Visibility::Pub, .. }
                        | Decl::DStruct { vis: Visibility::Pub, .. }
                        | Decl::DType { vis: Visibility::Pub, .. }
                        | Decl::DTrait { vis: Visibility::Pub, .. }
                        | Decl::DImpl { vis: Visibility::Pub, .. }
                        | Decl::DSig { vis: Visibility::Pub, .. }
                        | Decl::DMacro { vis: Visibility::Pub, .. }
                        | Decl::DForeign { vis: Visibility::Pub, .. }
                        | Decl::DEffect { vis: Visibility::Pub, .. }
                        | Decl::DImport { .. }
                ) {
                    continue;
                }
                match &mut decl {
                    Decl::DData { module_path: m, .. }
                    | Decl::DStruct { module_path: m, .. }
                    | Decl::DType { module_path: m, .. }
                    | Decl::DTrait { module_path: m, .. }
                    | Decl::DImpl { module_path: m, .. }
                    | Decl::DSig { module_path: m, .. }
                    | Decl::DFn { module_path: m, .. }
                    | Decl::DMacro { module_path: m, .. }
                    | Decl::DForeign { module_path: m, .. }
                    | Decl::DEffect { module_path: m, .. } => {
                        *m = Some(module_path.clone());
                    }
                    _ => {}
                }
                out.push(decl);
            }
        } else {
            let wanted: HashSet<&str> = names.iter().map(|i| i.name.as_str()).collect();
            let module_path = dotted.clone();
            for mut decl in imported_module
                .decls
                .into_iter()
                .filter(|d| decl_name(d).is_some_and(|n| wanted.contains(n)))
            {
                match &mut decl {
                    Decl::DData { module_path: m, .. }
                    | Decl::DStruct { module_path: m, .. }
                    | Decl::DType { module_path: m, .. }
                    | Decl::DTrait { module_path: m, .. }
                    | Decl::DImpl { module_path: m, .. }
                    | Decl::DSig { module_path: m, .. }
                    | Decl::DFn { module_path: m, .. }
                    | Decl::DMacro { module_path: m, .. }
                    | Decl::DForeign { module_path: m, .. }
                    | Decl::DEffect { module_path: m, .. } => {
                        *m = Some(module_path.clone());
                    }
                    _ => {}
                }
                out.push(decl);
            }
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

    expand_macros(&mut ast);

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

/// Arguments that pin `llc`'s relocation model to position-independent
/// code.
///
/// These are not optional, and the reason is worth recording because the
/// bug they fix is invisible on macOS and invisible at `-O2`.
///
/// `llc`'s default relocation model for ELF targets is `static`. Every
/// mainstream Linux distribution, meanwhile, links PIE by default. A
/// static-model object that takes the address of a global emits
/// `R_X86_64_32S` - an absolute 32-bit relocation - which the linker
/// rejects with "relocation R_X86_64_32S against `.bss' can not be used
/// when making a PIE object". Axiom always has such a global: the
/// bump allocator's `@__axiom_bump` cursor.
///
/// Two things conspired to hide this. At `-O2` the x86 backend happens
/// to pick PC-relative addressing anyway, so only `-O0` builds fail -
/// and `axiom run` is exactly the `-O0` path. And Darwin is
/// position-independent unconditionally, so a macOS developer never
/// reproduces it. The result was a compiler that could not build an
/// allocating program on Linux x86-64 at `-O0` while every local check
/// passed.
///
/// Passing the model explicitly rather than emitting a `PIC Level`
/// module flag is deliberate: `llc` ignores that flag. It was measured -
/// an otherwise identical module with `!"PIC Level", i32 2` still
/// assembles to `R_X86_64_32S`. Only the command-line option works, so
/// every `llc` invocation in the project must carry it, including the
/// ones in `scripts/`.
const LLC_RELOCATION_ARGS: &[&str] = &["-relocation-model=pic"];

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
    let mut codegen = LlvmCodeGen::for_target(target()).with_gc(gc_enabled());
    let llvm_ir = codegen.compile(&ir_module)?;

    let ll_path = format!("{}.ll", output);
    fs::write(&ll_path, &llvm_ir).map_err(|e| format!("Failed to write LLVM IR: {}", e))?;

    if emit_llvm {
        println!("LLVM IR written to {}", ll_path);
    }

    let obj_path = format!("{}.o", output);
    let opt_ll_path = run_llvm_opt(&ll_path, opt)?;

    // Intermediates to delete on the way out, whether or not the build
    // succeeded.
    //
    // Previously only the object file was cleaned up and the `.ll` was
    // left behind unconditionally, which made `axiom run` drop an
    // `axiom_temp_output.ll` into whatever directory it was invoked from -
    // it deletes the executable it created but had nothing to delete the
    // IR with. It also made `--emit-llvm` almost meaningless, since the
    // flag only controlled whether a line was printed; the file appeared
    // either way.
    //
    // `run_llvm_opt` returns a *different* path at `--opt 1` and above
    // (`<output>.opt.ll`), so both have to be tracked or the higher
    // optimisation levels leak a file the default level does not.
    let mut intermediates = vec![obj_path.clone()];
    if opt_ll_path != ll_path {
        intermediates.push(opt_ll_path.clone());
    }
    if !emit_llvm {
        intermediates.push(ll_path.clone());
    }

    let result = assemble_and_link(&opt_ll_path, &obj_path, output, opt);

    for path in &intermediates {
        fs::remove_file(path).ok();
    }

    result?;

    println!("Build successful: {}", output);
    Ok(())
}

/// Assemble `ll_path` to an object and link it into `output`.
///
/// Split out of `build` so that the intermediate files `build` created are
/// cleaned up on *every* path out, including the two failure paths. Inlined,
/// an `llc` or `cc` failure returned early and left the `.ll` and possibly
/// the `.o` behind - which is the case where the leftovers are most annoying,
/// because a failed build is exactly when someone reruns the command.
fn assemble_and_link(ll_path: &str, obj_path: &str, output: &str, opt: u8) -> Result<(), String> {
    let llc_status = Command::new("llc")
        .arg(ll_path)
        .arg("-filetype=obj")
        .arg("-o")
        .arg(obj_path)
        .arg(format!("-O{}", opt.clamp(0, 3)))
        .args(LLC_RELOCATION_ARGS)
        .status()
        .map_err(|e| format!("Failed to run llc: {}", e))?;

    if !llc_status.success() {
        return Err("llc failed".to_string());
    }

    let cc_status = Command::new("cc")
        .arg(obj_path)
        .arg("-o")
        .arg(output)
        .status()
        .map_err(|e| format!("Failed to run cc: {}", e))?;

    if !cc_status.success() {
        return Err("cc failed".to_string());
    }

    Ok(())
}

/// Run LLVM's optimiser over the emitted IR, returning the path to
/// optimise (unchanged at `-O0`, or a new `.opt.ll` otherwise).
///
/// `llc`'s own `-O` flag only tunes instruction selection; it does not
/// run the mid-level passes. That distinction is not cosmetic for
/// Axiom, because Axiom has no loop construct: iteration is written as
/// recursion, and it is `opt`'s scalar-promotion-plus-tail-call passes
/// that turn a self-tail-recursive function into a loop. Without them,
/// a recursive loop consumes one stack frame per iteration and dies at
/// a few hundred thousand iterations - which a compiler scanning a
/// large source file reaches easily.
///
/// A missing `opt` is a warning, not an error: the compiler still
/// produces a working binary through `llc` alone, just one that cannot
/// iterate deeply. Failing the build would make `opt` a hard
/// dependency of every Axiom installation for a benefit that only some
/// programs need.
fn run_llvm_opt(ll_path: &str, opt: u8) -> Result<String, String> {
    if opt == 0 {
        return Ok(ll_path.to_string());
    }

    let opt_path = format!("{}.opt.ll", ll_path.trim_end_matches(".ll"));
    let status = Command::new("opt")
        .arg(format!("-O{}", opt.clamp(1, 3)))
        .arg(ll_path)
        .arg("-S")
        .arg("-o")
        .arg(&opt_path)
        .status();

    match status {
        Ok(s) if s.success() => Ok(opt_path),
        Ok(_) => Err("opt failed".to_string()),
        Err(_) => {
            eprintln!(
                "warning: `opt` not found on PATH; building without mid-level optimisation \
                 (deeply recursive code may exhaust the stack)"
            );
            Ok(ll_path.to_string())
        }
    }
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
            .map(|a| match &a.value {
                Some(v) if !v.is_empty() => format!("{}={}", a.key, v),
                _ => a.key.clone(),
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

    let mut codegen = LlvmCodeGen::for_target(target()).with_gc(gc_enabled());
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

    // Refuse rather than destroy.
    //
    // `format_module` regenerates source from the AST, and comments never
    // reach the AST - the lexer drops them so no later stage has to skip
    // them. The result was that `axiom fmt` deleted every comment in the
    // file it formatted, silently and in place. Every file in `stdlib/`
    // would have lost its documentation to a single invocation, and
    // nothing would have reported it: `fmt` is the one part of the CLI
    // with no CI gate, precisely because its output does not currently
    // round-trip.
    //
    // Detecting the condition is exact rather than heuristic: the lexer
    // now records the span of each comment it discarded, so this is a
    // count of what would actually be lost, not a guess from scanning for
    // `;` outside of string literals.
    //
    // The real fix is trivia preservation - attaching comments to the
    // syntax they precede and re-emitting them - which is also what an LSP
    // needs before it can rewrite source. Until then, failing loudly is
    // the only behaviour that does not lose a user's work.
    let discarded = lexer.comment_spans().len();
    if discarded > 0 {
        return Err(format!(
            "{} contains {} comment{} that the formatter cannot preserve, so it \
             refuses to rewrite the file.\n\
             \n\
             `fmt` regenerates source from the syntax tree, and comments are not \
             part of the tree. Formatting would delete them.\n\
             \n\
             Comment-preserving formatting needs trivia support in the lexer and \
             parser; see docs/v1-roadmap.md.",
            input,
            discarded,
            if discarded == 1 { "" } else { "s" },
        ));
    }

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

                        let mut codegen = LlvmCodeGen::for_target(target()).with_gc(gc_enabled());
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

                            let mut codegen = LlvmCodeGen::for_target(target()).with_gc(gc_enabled());
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

                                let mut codegen = LlvmCodeGen::for_target(target()).with_gc(gc_enabled());
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

                                let mut codegen = LlvmCodeGen::for_target(target()).with_gc(gc_enabled());
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

mod expander {
    use axiom_ast::ast::*;
    use axiom_ast::span::Span;
    use axiom_ast::Module;
    use std::collections::HashMap;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static EXPANSION_SCOPE: AtomicUsize = AtomicUsize::new(1);
    static GENSYM_COUNTER: AtomicUsize = AtomicUsize::new(0);

    const TEMPLATE_MARKER: usize = usize::MAX;

    fn mark_template_idents(expr: &mut Expr) {
        match expr {
            Expr::EVar(ident) => {
                ident.scope = TEMPLATE_MARKER;
            }
            Expr::EWhile(cond, body) => {
                mark_template_idents(cond);
                mark_template_idents(body);
            }
            // The assignment target is a binding occurrence's *use*, so
            // it is marked like any other identifier - otherwise a
            // macro-introduced `set` would fail to find the `mut` local
            // the same macro introduced.
            Expr::EAssign(target, value) => {
                target.scope = TEMPLATE_MARKER;
                mark_template_idents(value);
            }
            Expr::EApp(func, arg) => {
                mark_template_idents(func);
                mark_template_idents(arg);
            }
            Expr::EIf(cond, t, e) => {
                mark_template_idents(cond);
                mark_template_idents(t);
                mark_template_idents(e);
            }
            Expr::EBegin(exprs) => {
                for e in exprs {
                    mark_template_idents(e);
                }
            }
            Expr::ELet(bindings, body) => {
                for b in bindings.iter_mut() {
                    mark_template_idents(&mut b.init);
                    mark_template_pattern(&mut b.pat);
                }
                mark_template_idents(body);
            }
            Expr::ELam(params, body) => {
                for p in params.iter_mut() {
                    mark_template_pattern(p);
                }
                mark_template_idents(body);
            }
            Expr::EMatch(target, arms) => {
                mark_template_idents(target);
                for (pat, body) in arms.iter_mut() {
                    mark_template_pattern(pat);
                    mark_template_idents(body);
                }
            }
            Expr::EInfix(left, _, right) => {
                mark_template_idents(left);
                mark_template_idents(right);
            }
            Expr::ECast(inner, _)
            | Expr::EConsume(inner)
            | Expr::EGrouped(inner)
            | Expr::EField(inner, _) => {
                mark_template_idents(inner);
            }
            Expr::ETuple(elems) | Expr::EList(elems) => {
                for e in elems {
                    mark_template_idents(e);
                }
            }
            Expr::ESetField(base, _, value) | Expr::EHandle(base, _, value) => {
                mark_template_idents(base);
                mark_template_idents(value);
            }
            Expr::EAlloc(_, Some(init), _) => {
                mark_template_idents(init);
            }
            Expr::ETypeSig(inner, _) | Expr::ESplice(inner) => {
                mark_template_idents(inner);
            }
            Expr::EStructCon(_, args) => {
                for a in args {
                    mark_template_idents(a);
                }
            }
            Expr::ECond(branches, else_expr) => {
                for (c, b) in branches {
                    mark_template_idents(c);
                    mark_template_idents(b);
                }
                if let Some(e) = else_expr {
                    mark_template_idents(e);
                }
            }
            Expr::EQualified(_, _)
            | Expr::ELit(..)
            | Expr::ESizeof(..)
            | Expr::EAlignof(..)
            | Expr::EError(..)
            | Expr::EAlloc(..)
            | Expr::EQuasiquote(..)
            | Expr::EUnquote(..) => {}
        }
    }

    fn mark_template_pattern(pat: &mut Pattern) {
        match pat {
            Pattern::PVar(ident) => {
                ident.scope = TEMPLATE_MARKER;
            }
            Pattern::PTuple(pats) | Pattern::PList(pats) => {
                for p in pats {
                    mark_template_pattern(p);
                }
            }
            Pattern::PCon(_, args) => {
                for a in args {
                    mark_template_pattern(a);
                }
            }
            Pattern::PConNamed(_, named) => {
                for (_, p) in named {
                    mark_template_pattern(p);
                }
            }
            Pattern::PWildcard | Pattern::PLit(_) => {}
        }
    }

    pub fn expand_macros(module: &mut Module) {
        let mut macros: HashMap<String, (Pattern, Expr)> = HashMap::new();
        let mut remaining_decls: Vec<Decl> = Vec::new();

        for decl in module.decls.drain(..) {
            if let Decl::DMacro {
                name, params, body, ..
            } = decl
            {
                macros.insert(name.name.clone(), (params, body));
            } else {
                remaining_decls.push(decl);
            }
        }
        module.decls = remaining_decls;

        for decl in &mut module.decls {
            if let Decl::DFn { body, .. } = decl {
                expand_expr(body, &macros);
            }
        }
    }

    fn expand_expr(expr: &mut Expr, macros: &HashMap<String, (Pattern, Expr)>) {
        let name = extract_macro_call_name(expr);
        if let Some(name) = name {
            if let Some((params, body)) = macros.get(&name) {
                let args = collect_args(expr);
                if let Ok(substitutions) = match_pattern(params, &args) {
                    let scope = EXPANSION_SCOPE.fetch_add(1, Ordering::Relaxed);
                    let mut template = body.clone();
                    mark_template_idents(&mut template);
                    let mut expanded = substitute(&substitutions, &template);
                    gensym_and_scope(&mut expanded, scope);
                    *expr = expanded;
                    expand_expr(expr, macros);
                    return;
                }
            }
        }

        match expr {
            Expr::EApp(func, arg) => {
                expand_expr(func, macros);
                expand_expr(arg, macros);
            }
            Expr::EIf(cond, then_expr, else_expr) => {
                expand_expr(cond, macros);
                expand_expr(then_expr, macros);
                expand_expr(else_expr, macros);
            }
            Expr::ELet(bindings, body) => {
                for b in bindings.iter_mut() {
                    expand_expr(&mut b.init, macros);
                }
                expand_expr(body, macros);
            }
            Expr::EBegin(exprs) => {
                for e in exprs.iter_mut() {
                    expand_expr(e, macros);
                }
            }
            Expr::EMatch(target, arms) => {
                expand_expr(target, macros);
                for (_, body) in arms.iter_mut() {
                    expand_expr(body, macros);
                }
            }
            Expr::EInfix(left, _, right) => {
                expand_expr(left, macros);
                expand_expr(right, macros);
            }
            Expr::ECast(inner, _)
            | Expr::EConsume(inner)
            | Expr::EGrouped(inner)
            | Expr::EField(inner, _) => {
                expand_expr(inner, macros);
            }
            Expr::ETuple(elems) | Expr::EList(elems) => {
                for e in elems {
                    expand_expr(e, macros);
                }
            }
            Expr::ESetField(base, _, value) | Expr::EHandle(base, _, value) => {
                expand_expr(base, macros);
                expand_expr(value, macros);
            }
            Expr::ELam(_, inner) => expand_expr(inner, macros),
            Expr::EAlloc(_, Some(init), _) => {
                expand_expr(init, macros);
            }
            Expr::EAlloc(..) => {}
            _ => {}
        }
    }

    fn extract_macro_call_name(expr: &Expr) -> Option<String> {
        let mut current = expr;
        while let Expr::EApp(func, _) = current {
            current = func;
        }
        if let Expr::EVar(ident) | Expr::EQualified(_, ident) = current {
            return Some(ident.name.clone());
        }
        None
    }

    fn collect_args(expr: &Expr) -> Vec<Expr> {
        let mut args = Vec::new();
        let mut current = expr;
        while let Expr::EApp(func, arg) = current {
            args.push((**arg).clone());
            current = func;
        }
        args.reverse();
        args
    }

    fn match_pattern(pattern: &Pattern, args: &[Expr]) -> Result<HashMap<String, Expr>, ()> {
        let mut bindings: HashMap<String, Expr> = HashMap::new();
        match pattern {
            Pattern::PVar(ident) => {
                if args.is_empty() {
                    bindings.insert(
                        ident.name.clone(),
                        Expr::ELit(Literal::LInt(0), Span::dummy()),
                    );
                } else if args.len() == 1 {
                    bindings.insert(ident.name.clone(), args[0].clone());
                } else {
                    bindings.insert(ident.name.clone(), Expr::EBegin(args.to_vec()));
                }
            }
            Pattern::PTuple(pats) => {
                for (i, pat) in pats.iter().enumerate() {
                    if i < args.len() {
                        let sub = match_pattern(pat, &args[i..i + 1])?;
                        bindings.extend(sub);
                    }
                }
            }
            _ => return Err(()),
        }
        Ok(bindings)
    }

    fn substitute(bindings: &HashMap<String, Expr>, template: &Expr) -> Expr {
        match template {
            Expr::EVar(ident) => bindings
                .get(&ident.name)
                .cloned()
                .unwrap_or(template.clone()),
            Expr::EWhile(cond, body) => Expr::EWhile(
                Box::new(substitute(bindings, cond)),
                Box::new(substitute(bindings, body)),
            ),
            // Only the value is substituted. Replacing the target would
            // mean rewriting `(set x e)` into `(set <expr> e)`, which
            // has no meaning: `set` names a slot, not a value.
            Expr::EAssign(target, value) => {
                Expr::EAssign(target.clone(), Box::new(substitute(bindings, value)))
            }
            Expr::EApp(func, arg) => Expr::EApp(
                Box::new(substitute(bindings, func)),
                Box::new(substitute(bindings, arg)),
            ),
            Expr::EIf(cond, t, e) => Expr::EIf(
                Box::new(substitute(bindings, cond)),
                Box::new(substitute(bindings, t)),
                Box::new(substitute(bindings, e)),
            ),
            Expr::EBegin(exprs) => {
                Expr::EBegin(exprs.iter().map(|e| substitute(bindings, e)).collect())
            }
            Expr::EInfix(left, op, right) => Expr::EInfix(
                Box::new(substitute(bindings, left)),
                op.clone(),
                Box::new(substitute(bindings, right)),
            ),
            Expr::ELet(bindings_in, body) => {
                let new_bindings: Vec<LetBinding> = bindings_in
                    .iter()
                    .map(|b| LetBinding {
                        pat: b.pat.clone(),
                        init: substitute(bindings, &b.init),
                        mutable: b.mutable,
                    })
                    .collect();
                Expr::ELet(new_bindings, Box::new(substitute(bindings, body)))
            }
            Expr::ELam(params, inner) => {
                Expr::ELam(params.clone(), Box::new(substitute(bindings, inner)))
            }
            Expr::EMatch(target, arms) => {
                let new_arms: Vec<(Pattern, Expr)> = arms
                    .iter()
                    .map(|(pat, body)| (pat.clone(), substitute(bindings, body)))
                    .collect();
                Expr::EMatch(Box::new(substitute(bindings, target)), new_arms)
            }
            Expr::ECast(inner, t) => Expr::ECast(Box::new(substitute(bindings, inner)), t.clone()),
            Expr::EConsume(inner) => Expr::EConsume(Box::new(substitute(bindings, inner))),
            Expr::EGrouped(inner) => Expr::EGrouped(Box::new(substitute(bindings, inner))),
            Expr::EField(inner, f) => {
                Expr::EField(Box::new(substitute(bindings, inner)), f.clone())
            }
            Expr::ETuple(elems) => {
                Expr::ETuple(elems.iter().map(|e| substitute(bindings, e)).collect())
            }
            Expr::EList(elems) => {
                Expr::EList(elems.iter().map(|e| substitute(bindings, e)).collect())
            }
            Expr::ESetField(inner, f, val) => Expr::ESetField(
                Box::new(substitute(bindings, inner)),
                f.clone(),
                Box::new(substitute(bindings, val)),
            ),
            Expr::EHandle(inner, effs, handler) => Expr::EHandle(
                Box::new(substitute(bindings, inner)),
                effs.clone(),
                Box::new(substitute(bindings, handler)),
            ),
            Expr::EAlloc(t, Some(init), s) => {
                Expr::EAlloc(t.clone(), Some(Box::new(substitute(bindings, init))), *s)
            }
            Expr::EAlloc(..) => template.clone(),
            Expr::ETypeSig(inner, t) => {
                Expr::ETypeSig(Box::new(substitute(bindings, inner)), t.clone())
            }
            Expr::EStructCon(ident, args) => Expr::EStructCon(
                ident.clone(),
                args.iter().map(|a| substitute(bindings, a)).collect(),
            ),
            Expr::EQualified(_, _) => template.clone(),
            Expr::EQuasiquote(inner) => substitute(bindings, inner),
            Expr::EUnquote(inner) => substitute(bindings, inner),
            Expr::ESplice(inner) => Expr::ESplice(Box::new(substitute(bindings, inner))),
            Expr::ECond(branches, else_expr) => {
                let new_branches: Vec<(Expr, Expr)> = branches
                    .iter()
                    .map(|(c, b)| (substitute(bindings, c), substitute(bindings, b)))
                    .collect();
                let new_else = else_expr
                    .as_ref()
                    .map(|e| Box::new(substitute(bindings, e)));
                Expr::ECond(new_branches, new_else)
            }
            Expr::ESizeof(..) | Expr::EAlignof(..) | Expr::EError(..) | Expr::ELit(..) => {
                template.clone()
            }
        }
    }

    fn gensym_and_scope(expr: &mut Expr, scope: usize) {
        let mut renames: HashMap<String, String> = HashMap::new();
        collect_gensym_renames(expr, &mut renames);
        apply_gensym_renames(expr, &renames, scope);
    }

    fn collect_gensym_renames(expr: &mut Expr, renames: &mut HashMap<String, String>) {
        match expr {
            Expr::ELet(bindings, body) => {
                for b in bindings.iter_mut() {
                    collect_gensym_renames(&mut b.init, renames);
                    collect_pattern_renames(&mut b.pat, renames);
                }
                collect_gensym_renames(body, renames);
            }
            Expr::ELam(params, body) => {
                for pat in params.iter_mut() {
                    collect_pattern_renames(pat, renames);
                }
                collect_gensym_renames(body, renames);
            }
            Expr::EMatch(target, arms) => {
                collect_gensym_renames(target, renames);
                for (pat, body) in arms.iter_mut() {
                    collect_pattern_renames(pat, renames);
                    collect_gensym_renames(body, renames);
                }
            }
            Expr::EApp(func, arg) => {
                collect_gensym_renames(func, renames);
                collect_gensym_renames(arg, renames);
            }
            Expr::EIf(cond, t, e) => {
                collect_gensym_renames(cond, renames);
                collect_gensym_renames(t, renames);
                collect_gensym_renames(e, renames);
            }
            Expr::EBegin(exprs) => {
                for e in exprs {
                    collect_gensym_renames(e, renames);
                }
            }
            Expr::EInfix(left, _, right) => {
                collect_gensym_renames(left, renames);
                collect_gensym_renames(right, renames);
            }
            Expr::ECast(inner, _)
            | Expr::EConsume(inner)
            | Expr::EGrouped(inner)
            | Expr::EField(inner, _) => {
                collect_gensym_renames(inner, renames);
            }
            Expr::ETuple(elems) | Expr::EList(elems) => {
                for e in elems {
                    collect_gensym_renames(e, renames);
                }
            }
            Expr::ESetField(base, _, value) | Expr::EHandle(base, _, value) => {
                collect_gensym_renames(base, renames);
                collect_gensym_renames(value, renames);
            }
            Expr::EAlloc(_, Some(init), _) => {
                collect_gensym_renames(init, renames);
            }
            Expr::ETypeSig(inner, _) | Expr::ESplice(inner) => {
                collect_gensym_renames(inner, renames);
            }
            Expr::EStructCon(_, args) => {
                for a in args {
                    collect_gensym_renames(a, renames);
                }
            }
            Expr::ECond(branches, else_expr) => {
                for (c, b) in branches {
                    collect_gensym_renames(c, renames);
                    collect_gensym_renames(b, renames);
                }
                if let Some(e) = else_expr {
                    collect_gensym_renames(e, renames);
                }
            }
            _ => {}
        }
    }

    fn collect_pattern_renames(pat: &mut Pattern, renames: &mut HashMap<String, String>) {
        match pat {
            Pattern::PVar(ident) => {
                if !renames.contains_key(&ident.name) {
                    let n = GENSYM_COUNTER.fetch_add(1, Ordering::Relaxed);
                    renames.insert(ident.name.clone(), format!("__gensym_{}", n));
                }
            }
            Pattern::PTuple(pats) | Pattern::PList(pats) => {
                for p in pats {
                    collect_pattern_renames(p, renames);
                }
            }
            Pattern::PCon(_, args) => {
                for a in args {
                    collect_pattern_renames(a, renames);
                }
            }
            Pattern::PConNamed(_, named) => {
                for (_, p) in named {
                    collect_pattern_renames(p, renames);
                }
            }
            Pattern::PWildcard | Pattern::PLit(_) => {}
        }
    }

    fn apply_gensym_renames(expr: &mut Expr, renames: &HashMap<String, String>, scope: usize) {
        match expr {
            Expr::EWhile(cond, body) => {
                apply_gensym_renames(cond, renames, scope);
                apply_gensym_renames(body, renames, scope);
            }
            Expr::EAssign(target, value) => {
                if let Some(new_name) = renames.get(&target.name) {
                    target.name = new_name.clone();
                }
                apply_gensym_renames(value, renames, scope);
            }
            Expr::EVar(ident) => {
                if let Some(new_name) = renames.get(&ident.name) {
                    ident.name = new_name.clone();
                }
                if ident.scope == TEMPLATE_MARKER {
                    ident.scope = scope;
                }
            }
            Expr::ELet(bindings, body) => {
                for b in bindings.iter_mut() {
                    apply_gensym_renames(&mut b.init, renames, scope);
                    apply_pattern_renames(&mut b.pat, renames, scope);
                }
                apply_gensym_renames(body, renames, scope);
            }
            Expr::ELam(params, body) => {
                for pat in params.iter_mut() {
                    apply_pattern_renames(pat, renames, scope);
                }
                apply_gensym_renames(body, renames, scope);
            }
            Expr::EMatch(target, arms) => {
                apply_gensym_renames(target, renames, scope);
                for (pat, body) in arms.iter_mut() {
                    apply_pattern_renames(pat, renames, scope);
                    apply_gensym_renames(body, renames, scope);
                }
            }
            Expr::EApp(func, arg) => {
                apply_gensym_renames(func, renames, scope);
                apply_gensym_renames(arg, renames, scope);
            }
            Expr::EIf(cond, t, e) => {
                apply_gensym_renames(cond, renames, scope);
                apply_gensym_renames(t, renames, scope);
                apply_gensym_renames(e, renames, scope);
            }
            Expr::EBegin(exprs) => {
                for e in exprs {
                    apply_gensym_renames(e, renames, scope);
                }
            }
            Expr::EInfix(left, _, right) => {
                apply_gensym_renames(left, renames, scope);
                apply_gensym_renames(right, renames, scope);
            }
            Expr::ECast(inner, _)
            | Expr::EConsume(inner)
            | Expr::EGrouped(inner)
            | Expr::EField(inner, _) => {
                apply_gensym_renames(inner, renames, scope);
            }
            Expr::ETuple(elems) | Expr::EList(elems) => {
                for e in elems {
                    apply_gensym_renames(e, renames, scope);
                }
            }
            Expr::ESetField(base, _, value) | Expr::EHandle(base, _, value) => {
                apply_gensym_renames(base, renames, scope);
                apply_gensym_renames(value, renames, scope);
            }
            Expr::EAlloc(_, Some(init), _) => {
                apply_gensym_renames(init, renames, scope);
            }
            Expr::ETypeSig(inner, _) | Expr::ESplice(inner) => {
                apply_gensym_renames(inner, renames, scope);
            }
            Expr::EStructCon(_, args) => {
                for a in args {
                    apply_gensym_renames(a, renames, scope);
                }
            }
            Expr::ECond(branches, else_expr) => {
                for (c, b) in branches {
                    apply_gensym_renames(c, renames, scope);
                    apply_gensym_renames(b, renames, scope);
                }
                if let Some(e) = else_expr {
                    apply_gensym_renames(e, renames, scope);
                }
            }
            Expr::EQualified(_, _)
            | Expr::ELit(..)
            | Expr::ESizeof(..)
            | Expr::EAlignof(..)
            | Expr::EError(..)
            | Expr::EAlloc(..)
            | Expr::EQuasiquote(..)
            | Expr::EUnquote(..) => {}
        }
    }

    fn apply_pattern_renames(pat: &mut Pattern, renames: &HashMap<String, String>, scope: usize) {
        match pat {
            Pattern::PVar(ident) => {
                if let Some(new_name) = renames.get(&ident.name) {
                    ident.name = new_name.clone();
                }
                ident.scope = scope;
            }
            Pattern::PTuple(pats) | Pattern::PList(pats) => {
                for p in pats {
                    apply_pattern_renames(p, renames, scope);
                }
            }
            Pattern::PCon(_, args) => {
                for a in args {
                    apply_pattern_renames(a, renames, scope);
                }
            }
            Pattern::PConNamed(_, named) => {
                for (_, p) in named {
                    apply_pattern_renames(p, renames, scope);
                }
            }
            Pattern::PWildcard | Pattern::PLit(_) => {}
        }
    }
}

use expander::expand_macros;

fn merge_type_checker(_source_tc: &TypeChecker, state: &mut ReplState) {
    // Simple approach: re-parse all declarations
    state.type_checker = TypeChecker::new();
    re_register_decls(&state.declarations, &mut state.type_checker);
}
