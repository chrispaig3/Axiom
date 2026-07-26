use std::fs;
use std::process::Command;

use axiom_lexer::Lexer;
use axiom_parser::{Parser, DeclOrExpr};
use axiom_sema::TypeChecker;
use axiom_ir::generator::IrGen;
use axiom_codegen::LlvmCodeGen;
use axiom_errors::{Diagnostic, DiagnosticFormat};

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
    Run {
        input: String,
        args: Vec<String>,
    },
    /// Check syntax and types
    Check {
        input: String,
    },
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
        Commands::Build { input, output, emit_llvm, opt } => {
            if let Err(e) = build(&input, &output, emit_llvm, opt, format) {
                eprintln!("{}", e);
                std::process::exit(1);
            }
        }
        Commands::Run { input, args } => {
            if let Err(e) = run(&input, &args, format) {
                eprintln!("{}", e);
                std::process::exit(1);
            }
        }
        Commands::Check { input } => {
            if let Err(e) = check(&input, format) {
                eprintln!("{}", e);
                std::process::exit(1);
            } else {
                println!("OK");
            }
        }
        Commands::EmitLlvm { input, output } => {
            if let Err(e) = emit_llvm(&input, output.as_deref()) {
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
            println!("  {}  {}  ({})", info.code.bright_yellow(), info.title, info.slug);
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
fn print_diagnostics(diags: Vec<Diagnostic>, filename: &str, source: &str, format: DiagnosticFormat) {
    let rendered = match format {
        DiagnosticFormat::Human => axiom_errors::render_human(&diags, filename, source),
        DiagnosticFormat::Ai => axiom_errors::render_ai(&diags, filename, source),
        DiagnosticFormat::Json => axiom_errors::render_json(&diags, filename, source),
    };
    eprint!("{}", rendered);
}

/// Run the lexer, parser and type checker on `source`, printing any
/// diagnostics in `format`. Returns the checked AST and type checker on
/// success. This is shared by `build` and `check` so the two commands can
/// never drift apart in how they report errors.
///
/// When `announce` is set, prints a `[stage/5]` progress line immediately
/// before each stage actually runs (not all up front) so a failure in an
/// early stage doesn't misleadingly claim later stages happened too.
fn analyze(input: &str, source: &str, format: DiagnosticFormat, announce: bool) -> Result<(axiom_ast::Module, TypeChecker), String> {
    if announce {
        println!("[1/5] Lexing...");
    }
    let mut lexer = Lexer::new(source, 0);
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
    let ast = match parser.parse_module() {
        Ok(ast) => ast,
        Err(e) => {
            print_diagnostics(vec![e.to_diagnostic()], input, source, format);
            return Err("compilation failed due to a syntax error".to_string());
        }
    };

    if announce {
        println!("[3/5] Type checking...");
    }
    let mut type_checker = TypeChecker::new();
    match type_checker.check(&ast) {
        Ok(()) => Ok((ast, type_checker)),
        Err(errors) => {
            let diags: Vec<Diagnostic> = errors.iter().map(|e| e.to_diagnostic()).collect();
            // Cascade-dedup once up front so the count in the summary line
            // matches exactly what gets printed, instead of the old
            // behavior of reporting a raw (and often inflated) error count.
            // `print_diagnostics` is handed the already-deduped list
            // directly (bypassing `axiom_errors::render`'s own internal
            // dedup) so we don't do the (harmless but wasteful) work twice.
            let diags = axiom_errors::dedup(diags);
            let shown = diags.len();
            print_diagnostics(diags, input, source, format);
            Err(format!(
                "compilation failed due to {} previous error{}",
                shown,
                if shown == 1 { "" } else { "s" }
            ))
        }
    }
}

fn build(input: &str, output: &str, emit_llvm: bool, _opt: u8, format: DiagnosticFormat) -> Result<(), String> {
    let source = fs::read_to_string(input)
        .map_err(|e| format!("Failed to read file '{}': {}", input, e))?;

    let (ast, type_checker) = analyze(input, &source, format, true)?;

    println!("[4/5] Generating IR...");
    let mut ir_gen = IrGen::new();
    let ir_module = ir_gen.generate(&ast, &type_checker);

    let has_main = ir_module.functions.iter().any(|f| f.name == "main");
    if !has_main {
        let diag = Diagnostic::error(&axiom_errors::code::MISSING_MAIN, "no `main` function found")
            .with_help("add `(:: main Int)` and `(define main ...)` as the program entry point");
        print_diagnostics(vec![diag], input, &source, format);
        return Err("compilation failed: missing entry point".to_string());
    }

    println!("[5/5] Generating LLVM IR...");
    let mut codegen = LlvmCodeGen::new();
    let llvm_ir = codegen.compile(&ir_module)?;

    let ll_path = format!("{}.ll", output);
    fs::write(&ll_path, &llvm_ir)
        .map_err(|e| format!("Failed to write LLVM IR: {}", e))?;

    if emit_llvm {
        println!("LLVM IR written to {}", ll_path);
    }

    let obj_path = format!("{}.o", output);

    let llc_status = Command::new("llc")
        .arg(&ll_path)
        .arg("-filetype=obj")
        .arg("-o")
        .arg(&obj_path)
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

fn run(input: &str, args: &[String], format: DiagnosticFormat) -> Result<(), String> {
    let output = "axiom_temp_output";
    build(input, output, false, 0, format)?;

    let mut cmd = Command::new(format!("./{}", output));
    for arg in args {
        cmd.arg(arg);
    }

    let status = cmd.status()
        .map_err(|e| format!("Failed to run program: {}", e))?;

    fs::remove_file(output).ok();

    if !status.success() {
        return Err(format!("Program exited with status: {}", status));
    }

    Ok(())
}

fn check(input: &str, format: DiagnosticFormat) -> Result<(), String> {
    let source = fs::read_to_string(input)
        .map_err(|e| format!("Failed to read file '{}': {}", input, e))?;

    analyze(input, &source, format, false)?;
    Ok(())
}

fn emit_llvm(input: &str, output: Option<&str>) -> Result<(), String> {
    let source = fs::read_to_string(input)
        .map_err(|e| format!("Failed to read file '{}': {}", input, e))?;

    let mut lexer = Lexer::new(&source, 0);
    let tokens = lexer.tokenize()
        .map_err(|e| format!("Lexer error: {}", e))?;

    let mut parser = Parser::new(tokens);
    let ast = parser.parse_module()
        .map_err(|e| format!("Parser error: {}", e))?;

    let mut type_checker = TypeChecker::new();
    type_checker.check(&ast)
        .map_err(|errors| {
            let msgs: Vec<String> = errors.iter().map(|e| format!("{}", e)).collect();
            msgs.join("\n")
        })?;

    let mut ir_gen = IrGen::new();
    let ir_module = ir_gen.generate(&ast, &type_checker);

    let mut codegen = LlvmCodeGen::new();
    let llvm_ir = codegen.compile(&ir_module)?;

    match output {
        Some(path) => {
            fs::write(path, &llvm_ir)
                .map_err(|e| format!("Failed to write LLVM IR: {}", e))?;
            println!("LLVM IR written to {}", path);
        }
        None => println!("{}", llvm_ir),
    }

    Ok(())
}

fn fmt(input: &str, check: bool) -> Result<(), String> {
    let source = fs::read_to_string(input)
        .map_err(|e| format!("Failed to read file '{}': {}", input, e))?;

    let mut lexer = Lexer::new(&source, 0);
    let tokens = lexer.tokenize()
        .map_err(|e| format!("Lexer error: {}", e))?;

    let mut parser = Parser::new(tokens);
    let ast = parser.parse_module()
        .map_err(|e| format!("Parser error: {}", e))?;

    let formatted = fmt::format_module(&ast);

    if check {
        if source == formatted {
            println!("{} {} is already formatted", "OK:".bright_green().bold(), input.bright_white());
        } else {
            println!("{} {} needs formatting", "Error:".bright_red().bold(), input.bright_white());
            std::process::exit(1);
        }
    } else {
        fs::write(input, &formatted)
            .map_err(|e| format!("Failed to write formatted file: {}", e))?;
        println!("{} {} formatted", "OK:".bright_green().bold(), input.bright_white());
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
        let prompt = format!("{} {} ", "axiom>".bright_blue().bold(), state.line_count + 1);
        
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
    println!("{}", "╔═══════════════════════════════════════════════════════════╗".bright_cyan());
    println!("{}", "║                                                           ║".bright_cyan());
    println!("{}", format!("║   Axiom v{} - Functional Systems Language              ║", env!("CARGO_PKG_VERSION")).bright_cyan());
    println!("{}", "║                                                           ║".bright_cyan());
    println!("{}", "║   Type :help for commands, :quit to exit                 ║".bright_cyan());
    println!("{}", "║                                                           ║".bright_cyan());
    println!("{}", "╚═══════════════════════════════════════════════════════════╝".bright_cyan());
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
            println!("{} Unknown command '{}'. Type :help for available commands.", 
                "Error:".bright_red().bold(), cmd.bright_yellow());
        }
    }
}

fn show_help() {
    println!();
    println!("{}", "Available Commands:".bold().bright_cyan());
    println!("  {}     Show this help message", ":help, :h, ?".bright_green());
    println!("  {}      Exit the REPL", ":quit, :q, :exit".bright_green());
    println!("  {} <expr>  Show the type of an expression", ":type, :t".bright_green());
    println!("  {} <file>  Load a file into the REPL", ":load, :l".bright_green());
    println!("  {}        Reset the REPL state", ":reset, :r".bright_green());
    println!("  {}       Show all definitions in scope", ":defs, :d".bright_green());
    println!("  {} <expr>  Show generated LLVM IR", ":llvm".bright_green());
    println!("  {} <expr>  Time expression evaluation", ":time".bright_green());
    println!();
    println!("{}", "Tips:".bold().bright_cyan());
    println!("  • Define functions: {}", "(define (add x y) (+ x y))".bright_white());
    println!("  • Type signatures: {}", "(:: add (-> Int Int Int))".bright_white());
    println!("  • Data types: {}", "(data Maybe (a) (Nothing) (Just a))".bright_white());
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
            println!("{} : {}", expr_str.bright_white(), ty.to_string().bright_cyan());
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
                    println!("{} Loaded '{}'", "OK:".bright_green().bold(), file.bright_white());
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
            println!("  {} : {}", fn_info.name.bright_white(), fn_info.ty.to_string().bright_cyan());
        }
    }
    
    for dt in &tc.data_types {
        println!("  data {} with {} constructors", 
            dt.name.bright_white(), 
            dt.constructors.len());
        for con in &dt.constructors {
            println!("    {} : {}", con.name.bright_green(), con.ty.to_string().bright_cyan());
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
                    let mut tc = TypeChecker::new();
                    if tc.check(&ast).is_ok() {
                        let mut ir_gen = IrGen::new();
                        let ir_module = ir_gen.generate(&ast, &tc);
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
                        let mut tc = TypeChecker::new();
                        if tc.check(&ast).is_ok() {
                            let mut ir_gen = IrGen::new();
                            let ir_module = ir_gen.generate(&ast, &tc);
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
                println!("{} {} defined", "OK:".bright_green().bold(), name.name.bright_white());
            } else {
                println!("{}", "OK".bright_green().bold());
            }
        }
        Some(DeclOrExpr::Expr(expr)) => {
            let mut tc = TypeChecker::new();
            re_register_decls(&state.declarations, &mut tc);

            match tc.check_single_expr(&expr) {
                Ok(ty) => {
                    println!("{} : {}", "type".bright_yellow(), ty.to_string().bright_cyan());
                    
                    let wrapper = generate_repl_wrapper(&state.declarations, expr_str, &ty);

                    let mut lexer = Lexer::new(&wrapper, 0);
                    if let Ok(tokens) = lexer.tokenize() {
                        let mut parser = Parser::new(tokens);
                        if let Ok(ast) = parser.parse_module() {
                            let mut tc2 = TypeChecker::new();
                            if tc2.check(&ast).is_ok() {
                                let mut ir_gen = IrGen::new();
                                let ir_module = ir_gen.generate(&ast, &tc2);

                                let mut codegen = LlvmCodeGen::new();
                                if let Ok(llvm_ir) = codegen.compile(&ir_module) {
                                    let start = std::time::Instant::now();
                                    let result = compile_and_run_repl(&llvm_ir);
                                    let duration = start.elapsed();
                                    
                                    if let Some(value) = result {
                                        println!("{} {}", "result".bright_green(), value.bright_white());
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
                println!("{} {} defined", "OK:".bright_green().bold(), name.name.bright_white());
            } else if let axiom_ast::ast::Decl::DData { name, .. } = &decl {
                println!("{} data {} defined", "OK:".bright_green().bold(), name.name.bright_white());
            } else if let axiom_ast::ast::Decl::DSig { name, .. } = &decl {
                println!("{} {} defined", "OK:".bright_green().bold(), name.name.bright_white());
            } else {
                println!("{}", "OK".bright_green().bold());
            }
        }
        Some(DeclOrExpr::Expr(expr)) => {
            let mut tc = TypeChecker::new();
            re_register_decls(&state.declarations, &mut tc);

            match tc.check_single_expr(&expr) {
                Ok(ty) => {
                    println!("{} : {}", "type".bright_yellow(), ty.to_string().bright_cyan());
                    
                    let wrapper = generate_repl_wrapper(&state.declarations, input, &ty);

                    let mut lexer = Lexer::new(&wrapper, 0);
                    if let Ok(tokens) = lexer.tokenize() {
                        let mut parser = Parser::new(tokens);
                        if let Ok(ast) = parser.parse_module() {
                            let mut tc2 = TypeChecker::new();
                            if tc2.check(&ast).is_ok() {
                                let mut ir_gen = IrGen::new();
                                let ir_module = ir_gen.generate(&ast, &tc2);

                                let mut codegen = LlvmCodeGen::new();
                                if let Ok(llvm_ir) = codegen.compile(&ir_module) {
                                    let result = compile_and_run_repl(&llvm_ir);
                                    if let Some(value) = result {
                                        println!("{} {}", "result".bright_green(), value.bright_white());
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
        .map_or(false, |s| s.success())
    {
        fs::remove_file(temp_ll).ok();
        return None;
    }
    
    if !Command::new("cc")
        .arg(&obj_path)
        .arg("-o")
        .arg(temp_out)
        .status()
        .map_or(false, |s| s.success())
    {
        fs::remove_file(&obj_path).ok();
        fs::remove_file(temp_ll).ok();
        return None;
    }
    
    let output = Command::new(format!("./{}", temp_out))
        .output();
    
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
