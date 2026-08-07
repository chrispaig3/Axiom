use axiom_ast::ast::*;
use axiom_ast::span::Ident;
use std::fmt::Write;

const INDENT: &str = "  ";

/// One comment recovered from the source, with what the formatter needs
/// in order to put it back.
///
/// Comments are not part of the syntax tree - the lexer discards them so
/// that no later stage has to skip them - so the formatter cannot find
/// them by walking the AST. Instead it walks the AST and the comment list
/// together, in source order, emitting each comment when it reaches the
/// construct that followed it. That is why `start` is here: it is the
/// only thing tying a comment back to a position in the tree.
pub struct Comment {
    /// The comment exactly as written, including its `;` or `#| |#`
    /// delimiters. Re-emitted verbatim: reflowing a comment is a
    /// judgement about prose, and getting it wrong loses meaning that the
    /// formatter has no way to recover.
    pub text: String,
    /// Character offset of the comment's first character.
    pub start: usize,
    /// Zero-based source line the comment sits on. A trailing comment is
    /// re-emitted only onto a construct from this same line, so that an
    /// annotation cannot migrate onto an unrelated expression that merely
    /// happened to be formatted when the comment reached the queue.
    pub line: usize,
    /// Whether only whitespace precedes the comment on its source line.
    ///
    /// This is the difference between a comment that documents the line
    /// below it and one that annotates the line it sits on. Emitting a
    /// trailing `; 64: blocks are contiguous` above its expression, or a
    /// heading below its section, both change what the file says while
    /// preserving every byte of it.
    pub own_line: bool,
}

/// Recover the comments in `source`, given the spans the lexer recorded
/// while discarding them.
///
/// Spans are character offsets, so the source is indexed as characters
/// rather than bytes - slicing a `str` by a char offset would panic on
/// any file with a multi-byte character in it, which in this repo means
/// any file whose prose uses a dash.
pub fn collect_comments(source: &[char], spans: &[axiom_ast::span::Span]) -> Vec<Comment> {
    let lines = LineIndex::new(source);
    let mut comments: Vec<Comment> = spans
        .iter()
        .map(|span| {
            let end = span.end.min(source.len());
            let start = span.start.min(end);
            // Walk back to the line start; anything but whitespace before
            // the comment makes it a trailing comment.
            let own_line = source[..start]
                .iter()
                .rev()
                .take_while(|c| **c != '\n')
                .all(|c| c.is_whitespace());
            Comment {
                text: source[start..end]
                    .iter()
                    .collect::<String>()
                    .trim_end()
                    .to_string(),
                start,
                line: lines.line_at(start),
                own_line,
            }
        })
        .collect();
    comments.sort_by_key(|c| c.start);
    comments
}

/// Character offset to line number, for deciding whether a comment sits
/// on the same source line as the construct it annotates.
struct LineIndex {
    /// Offset of the first character of each line, ascending.
    starts: Vec<usize>,
}

impl LineIndex {
    fn new(source: &[char]) -> Self {
        let mut starts = vec![0];
        for (i, c) in source.iter().enumerate() {
            if *c == '\n' {
                starts.push(i + 1);
            }
        }
        Self { starts }
    }

    fn line_at(&self, offset: usize) -> usize {
        match self.starts.binary_search(&offset) {
            Ok(line) => line,
            Err(next) => next - 1,
        }
    }
}

pub fn format_module(module: &Module, source: &[char], comments: Vec<Comment>) -> String {
    let mut out = String::new();
    let mut state = FormatState::new(comments, LineIndex::new(source));

    // Imports are parsed into `Module::imports`, not `Module::decls`.
    // Formatting only `decls` therefore deleted every `(import ...)` line
    // in the file - the one loss here that stops the result from
    // compiling at all, and it was reported as a successful format.
    let decls = module.imports.iter().chain(module.decls.iter());

    for (i, decl) in decls.enumerate() {
        if i > 0 {
            out.push('\n');
        }
        let start = decl_start(decl);
        state.flush_leading(start, &mut out);
        let mark = out.len();
        format_decl(decl, &mut out, &mut state);
        state.flush_trailing(start, mark, &mut out);
        out.push('\n');
    }

    // Comments after the last declaration - a trailing footnote, or an
    // entire commented-out block at the end of a file - have no following
    // construct to be attached to, and would otherwise be dropped.
    state.flush_remaining(&mut out);

    out
}

/// The offset the formatter treats as a declaration's start, for deciding
/// which comments precede it.
///
/// Declarations carry no span of their own, so this uses the name, which
/// sits a few tokens later - after `(`, any `pub`, and the keyword. That
/// is close enough for ordering against comments, which live on earlier
/// lines entirely.
fn decl_start(decl: &Decl) -> usize {
    match decl {
        Decl::DData { name, .. }
        | Decl::DStruct { name, .. }
        | Decl::DType { name, .. }
        | Decl::DTrait { name, .. }
        | Decl::DSig { name, .. }
        | Decl::DFn { name, .. }
        | Decl::DMacro { name, .. }
        | Decl::DForeign { name, .. }
        | Decl::DEffect { name, .. } => name.span.start,
        Decl::DImpl { trait_name, .. } => trait_name.span.start,
        Decl::DImport { module, names } => module
            .first()
            .or_else(|| names.first())
            .map(|i| i.span.start)
            .unwrap_or(0),
    }
}

struct FormatState {
    indent_level: usize,
    comments: Vec<Comment>,
    /// Index of the first comment not yet emitted. Comments are emitted
    /// in source order and never revisited, so this is the whole cursor.
    next: usize,
    lines: LineIndex,
}

impl FormatState {
    fn new(comments: Vec<Comment>, lines: LineIndex) -> Self {
        Self {
            indent_level: 0,
            comments,
            next: 0,
            lines,
        }
    }

    fn indent_str(&self) -> String {
        INDENT.repeat(self.indent_level)
    }

    fn push_indent(&mut self) {
        self.indent_level += 1;
    }

    fn pop_indent(&mut self) {
        if self.indent_level > 0 {
            self.indent_level -= 1;
        }
    }

    /// Emit every pending comment that starts before `before`, each on its
    /// own line at the current indent, leaving the cursor at the start of
    /// a fresh line.
    ///
    /// Call this immediately *before* writing the indent for the construct
    /// at `before`; it writes its own indentation.
    ///
    /// Trailing comments are emitted here too when they reach the front of
    /// the queue, which happens when the construct they trailed was not
    /// one of the sites that calls `flush_trailing`. Relocating such a
    /// comment to its own line is a formatting change; dropping it is data
    /// loss, and only one of those is recoverable by the reader.
    fn flush_leading(&mut self, before: usize, out: &mut String) {
        while self.next < self.comments.len() && self.comments[self.next].start < before {
            let indent = self.indent_str();
            let comment = &self.comments[self.next];
            out.push_str(&indent);
            out.push_str(&comment.text);
            out.push('\n');
            self.next += 1;
        }
    }

    /// Emit a pending trailing comment onto the current line, if the next
    /// one belongs to the construct just written.
    ///
    /// Call this directly after writing a construct, passing an offset
    /// inside it; the cursor must still be on that construct's line.
    ///
    /// The line check is what keeps the annotation attached to what it
    /// annotates. Without it, any trailing comment reaching the front of
    /// the queue would be emitted after whatever construct happened to be
    /// formatted next - which put `; 1: allocation advances the waterline`
    /// on a type signature forty lines above the expression it describes.
    /// `mark` is `out.len()` from immediately before the construct was
    /// written, which is how this tells whether the construct was laid out
    /// on a single line.
    ///
    /// That condition is what makes formatting idempotent. A trailing
    /// comment can only stay trailing across a second pass if the thing it
    /// trails still ends on the line it starts on: when the formatter
    /// breaks a one-line source construct across several lines, the
    /// comment ends up after the closing paren, on a line that is no
    /// longer the construct's first line, so the next pass would not
    /// recognise it as trailing and would move it again. Such a comment is
    /// left in the queue and emitted on its own line instead - it moves
    /// once, and then it is stable.
    fn flush_trailing(&mut self, anchor: usize, mark: usize, out: &mut String) {
        if out[mark..].contains('\n') {
            return;
        }
        let line = self.lines.line_at(anchor);
        if self.next < self.comments.len()
            && !self.comments[self.next].own_line
            && self.comments[self.next].line == line
        {
            out.push_str("  ");
            out.push_str(&self.comments[self.next].text);
            self.next += 1;
        }
    }

    /// Emit every comment still pending, at the current indent.
    fn flush_remaining(&mut self, out: &mut String) {
        let count = self.comments.len();
        self.flush_leading(usize::MAX, out);
        debug_assert_eq!(self.next, count, "every comment must be emitted");
    }
}

/// The `pub` marker for a declaration, as it is spelled in source:
/// immediately inside the opening paren, before the keyword.
///
/// Dropping this was silent data loss of the worst kind available to a
/// formatter - it does not change how the file parses, so nothing
/// downstream complains, but it removes every name the module exported.
/// Importers then fail to resolve names that are still visibly present
/// in the file, which is about as far from the cause as a diagnostic can
/// land.
fn vis_prefix(vis: &Visibility) -> &'static str {
    if vis.is_pub() {
        "pub "
    } else {
        ""
    }
}

/// AXTAGs belonging to a declaration, re-emitted as the `;@axiom:` lines
/// they were parsed from.
///
/// These are lexed as real tokens rather than discarded as comments, so
/// the comment guard never counted them - which meant they were the one
/// category of source text `fmt` deleted without even refusing. They are
/// compiler-checked metadata (an `effect(io)` claim is validated against
/// the body), so losing them silently changes what the compiler verifies
/// about the file.
fn format_axtags(axtags: &[Axtag], out: &mut String, state: &FormatState) {
    for tag in axtags {
        out.push_str(&state.indent_str());
        write!(out, ";@axiom:{}", tag.key).unwrap();
        if let Some(value) = &tag.value {
            write!(out, "({})", value).unwrap();
        }
        out.push('\n');
    }
}

fn format_decl(decl: &Decl, out: &mut String, state: &mut FormatState) {
    format_axtags(decl.axtags(), out, state);
    let vis = vis_prefix(decl.visibility());
    match decl {
        Decl::DSig { name, ty, .. } => {
            write!(out, "({}:: {} {})", vis, name, format_type(ty)).unwrap();
        }
        Decl::DFn {
            name, params, body, ..
        } => {
            format_function_decl(vis, name, params, body, out, state);
        }
        Decl::DData {
            name,
            tyvars,
            constructors,
            deriving,
            ..
        } => {
            format_data_decl(vis, name, tyvars, constructors, deriving, out, state);
        }
        Decl::DStruct {
            name,
            tyvars,
            fields,
            repr,
            ..
        } => {
            format_struct_decl(vis, name, tyvars, fields, repr, out, state);
        }
        Decl::DType {
            name,
            tyvars,
            alias,
            ..
        } => {
            write!(out, "({}type {}", vis, name.name).unwrap();
            if !tyvars.is_empty() {
                out.push(' ');
                format_type_vars(tyvars, out);
            }
            // `(type Name = Alias)`. The `=` is part of the syntax; the
            // formatter omitted it, so a formatted type alias no longer
            // parsed. No `.ax` file in the repository declares one,
            // which is why `check-fmt.sh` never caught it - the gate is
            // only as wide as the corpus it runs on.
            write!(out, " = {})", format_type(alias)).unwrap();
        }
        Decl::DForeign {
            name, ty, source, ..
        } => {
            write!(
                out,
                "({}foreign {} :: {} = \"{}\")",
                vis,
                name,
                format_type(ty),
                source
            )
            .unwrap();
        }
        Decl::DImport { module, names } => {
            // `Q.Inner`, not `Q Inner`. A dotted module path is one path,
            // and space-separating its segments produced an import of a
            // module named `Q` followed by a stray token - which did not
            // parse, so the formatted file would not compile.
            out.push_str("(import ");
            for (i, m) in module.iter().enumerate() {
                if i > 0 {
                    out.push('.');
                }
                out.push_str(&m.name);
            }
            if !names.is_empty() {
                out.push_str(" (");
                for (i, n) in names.iter().enumerate() {
                    if i > 0 {
                        out.push(' ');
                    }
                    out.push_str(&n.name);
                }
                out.push(')');
            }
            out.push(')');
        }
        Decl::DTrait {
            name,
            tyvar,
            supertraits,
            methods,
            effects,
            ..
        } => {
            format_trait_decl(
                TraitParts {
                    vis,
                    name,
                    tyvar,
                    supertraits,
                    methods,
                    effects,
                },
                out,
                state,
            );
        }
        Decl::DImpl {
            trait_name,
            ty,
            methods,
            effects,
            ..
        } => {
            format_impl_decl(vis, trait_name, ty, methods, effects, out, state);
        }
        Decl::DEffect {
            name, operations, ..
        } => {
            format_effect_decl(vis, name, operations, out, state);
        }
        Decl::DMacro {
            name, params, body, ..
        } => {
            // The head prints like a function's: `(macro (name p1 p2) t)`.
            // `parse_macro` wraps two-plus parameters in a synthetic
            // `PTuple`, and printing that tuple as one pattern -
            // `(macro (name (p1 p2)) t)` - wrote a *constructor pattern*
            // into the head. That reparses cleanly, so the formatter's
            // own verification could not see it, but the macro's arity
            // collapsed to one and every call site silently stopped
            // matching - the expansion just never happened, and the
            // macro's name surfaced later as an undefined function.
            write!(out, "({}macro ({}", vis, name.name).unwrap();
            let elems: &[Pattern] = match params {
                Pattern::PTuple(ps) => ps,
                single => std::slice::from_ref(single),
            };
            for p in elems {
                out.push(' ');
                format_pattern(p, out);
            }
            write!(out, ") ").unwrap();
            format_expr(body, out, state);
            out.push(')');
        }
    }
}

fn format_function_decl(
    vis: &str,
    name: &Ident,
    params: &[Pattern],
    body: &Expr,
    out: &mut String,
    state: &mut FormatState,
) {
    // `fn`, not `define`. Both parse, but every `.ax` file in the repo is
    // written with `fn`, so emitting `define` rewrote working source into
    // a second spelling of itself on the first format.
    out.push('(');
    out.push_str(vis);
    out.push_str("fn (");
    out.push_str(&name.name);
    for p in params {
        out.push(' ');
        format_pattern(p, out);
    }
    out.push(')');

    if is_simple_expr(body) {
        out.push(' ');
        format_expr(body, out, state);
        out.push(')');
    } else {
        out.push('\n');
        state.push_indent();
        state.flush_leading(body.span().start, out);
        out.push_str(&state.indent_str());
        format_expr(body, out, state);
        state.pop_indent();
        out.push('\n');
        out.push_str(&state.indent_str());
        out.push(')');
    }
}

fn format_data_decl(
    vis: &str,
    name: &Ident,
    tyvars: &[String],
    constructors: &[DataCon],
    deriving: &[Ident],
    out: &mut String,
    state: &mut FormatState,
) {
    out.push('(');
    out.push_str(vis);
    out.push_str("data ");
    out.push_str(&name.name);
    if !tyvars.is_empty() {
        out.push(' ');
        format_type_vars(tyvars, out);
    }

    if constructors.is_empty() {
        out.push(')');
    } else if constructors.len() == 1 && constructors[0].is_nullary() {
        write!(out, " ({})", constructors[0].name.name).unwrap();
        if !deriving.is_empty() {
            format_deriving(deriving, out);
        }
        out.push(')');
    } else {
        for con in constructors {
            out.push('\n');
            state.push_indent();
            out.push_str(&state.indent_str());
            format_data_con(con, out);
            state.pop_indent();
        }
        if !deriving.is_empty() {
            format_deriving(deriving, out);
        }
        out.push(')');
    }
}

fn format_struct_decl(
    vis: &str,
    name: &Ident,
    tyvars: &[String],
    fields: &[Field],
    repr: &Option<TypeRepr>,
    out: &mut String,
    state: &mut FormatState,
) {
    out.push('(');
    out.push_str(vis);
    out.push_str("struct ");
    out.push_str(&name.name);
    if !tyvars.is_empty() {
        out.push(' ');
        format_type_vars(tyvars, out);
    }
    if let Some(r) = repr {
        out.push(' ');
        match r {
            TypeRepr::C => out.push_str("repr(C)"),
            TypeRepr::Packed => out.push_str("packed"),
            TypeRepr::Align(n) => write!(out, "align({})", n).unwrap(),
        }
    }
    if !fields.is_empty() {
        state.push_indent();
        for f in fields {
            // One field per line. Without this newline every field after
            // the first was concatenated onto the same line as the one
            // before it.
            out.push('\n');
            out.push_str(&state.indent_str());
            // `(x : Int)`, not `(x Int)`. The separator is part of the
            // syntax, and omitting it produced a struct declaration that
            // did not parse.
            // `(mut y : Int)`, not `(y : Int) mut`. `parse_struct`
            // reads the `mut` immediately after the opening paren, so
            // the trailing spelling did not parse and `fmt` refused
            // every struct with a mutable field.
            write!(
                out,
                "({}{} : {})",
                if f.mutable { "mut " } else { "" },
                f.name.name,
                format_type(&f.ty)
            )
            .unwrap();
        }
        state.pop_indent();
    }
    out.push(')');
}

/// The parts of a `trait` declaration, grouped so that the formatter's
/// entry point stays inside a readable argument count. They are always
/// destructured from the same `Decl::DTrait` and only ever passed
/// together.
struct TraitParts<'a> {
    vis: &'a str,
    name: &'a Ident,
    tyvar: &'a str,
    supertraits: &'a [Type],
    methods: &'a [TraitMethod],
    effects: &'a [Effect],
}

fn format_trait_decl(parts: TraitParts<'_>, out: &mut String, state: &mut FormatState) {
    let TraitParts {
        vis,
        name,
        tyvar,
        supertraits,
        methods,
        effects,
    } = parts;
    out.push('(');
    out.push_str(vis);
    out.push_str("trait (");
    out.push_str(&name.name);
    out.push(' ');
    out.push_str(tyvar);
    out.push(')');
    if !effects.is_empty() {
        out.push(' ');
        out.push('(');
        for (i, e) in effects.iter().enumerate() {
            if i > 0 {
                out.push(' ');
            }
            out.push_str(&format!("{}", e));
        }
        out.push(')');
    }
    // Supertraits are a parenthesised list. They were emitted bare, one
    // after another with no delimiters at all, so a trait with any
    // supertrait formatted into something that did not parse.
    if !supertraits.is_empty() {
        out.push_str(" (");
        for (i, s) in supertraits.iter().enumerate() {
            if i > 0 {
                out.push(' ');
            }
            out.push_str(&format_type(s));
        }
        out.push(')');
    }
    // Methods live in `where ( ... )` and each is `name :: type`. The
    // `where`, the wrapping parens and the `::` were all missing, so a
    // trait with methods did not round-trip either. Nothing in the
    // repository declares a trait, which is why `check-fmt.sh` never
    // saw any of it.
    if !methods.is_empty() {
        out.push_str(" where (");
        out.push('\n');
        state.push_indent();
        for (i, m) in methods.iter().enumerate() {
            // One method per line. With a single `\n` before the loop,
            // every method after the first ran onto the line before it.
            if i > 0 {
                out.push('\n');
            }
            out.push_str(&state.indent_str());
            // No per-method parentheses: the parser reads a *flat*
            // sequence of `name :: type` inside the single `where (...)`
            // group, so wrapping each one made the result unparseable.
            write!(out, "{} :: {}", m.name.name, format_type(&m.ty)).unwrap();
            // Order matters: the parser reads `= default` before an
            // effect list, and the two were emitted the other way round
            // with the `=` missing entirely.
            if let Some(default) = &m.default {
                out.push_str(" = ");
                format_expr(default, out, state);
            }
            if !m.effects.is_empty() {
                out.push_str(" (");
                for (j, e) in m.effects.iter().enumerate() {
                    if j > 0 {
                        out.push(' ');
                    }
                    out.push_str(&format!("{}", e));
                }
                out.push(')');
            }
        }
        state.pop_indent();
        out.push('\n');
        out.push_str(&state.indent_str());
        out.push(')');
    }
    out.push(')');
}

fn format_impl_decl(
    vis: &str,
    trait_name: &Ident,
    ty: &Type,
    methods: &[(Ident, Expr)],
    effects: &[Effect],
    out: &mut String,
    state: &mut FormatState,
) {
    out.push('(');
    out.push_str(vis);
    out.push_str("impl (");
    out.push_str(&trait_name.name);
    out.push(' ');
    out.push_str(&format_type(ty));
    out.push(')');
    if !effects.is_empty() {
        out.push(' ');
        out.push('(');
        for (i, e) in effects.iter().enumerate() {
            if i > 0 {
                out.push(' ');
            }
            out.push_str(&format!("{}", e));
        }
        out.push(')');
    }
    // As for `trait`: the methods live in `where ( ... )`, and the
    // keyword and wrapping parens were missing, so an `impl` with any
    // method formatted into something that did not parse.
    if !methods.is_empty() {
        out.push_str(" where (");
        out.push('\n');
        state.push_indent();
        for (i, (name, body)) in methods.iter().enumerate() {
            if i > 0 {
                out.push('\n');
            }
            out.push_str(&state.indent_str());
            write!(out, "({}", name.name).unwrap();
            if is_simple_expr(body) {
                out.push(' ');
                format_expr(body, out, state);
            } else {
                out.push('\n');
                state.push_indent();
                out.push_str(&state.indent_str());
                format_expr(body, out, state);
                state.pop_indent();
                out.push('\n');
                out.push_str(&state.indent_str());
            }
            out.push(')');
        }
        state.pop_indent();
        out.push('\n');
        out.push_str(&state.indent_str());
        out.push(')');
    }
    out.push(')');
}

fn format_effect_decl(
    vis: &str,
    name: &Ident,
    operations: &[EffectOp],
    out: &mut String,
    state: &mut FormatState,
) {
    out.push('(');
    out.push_str(vis);
    out.push_str("effect ");
    out.push_str(&name.name);
    if !operations.is_empty() {
        state.push_indent();
        for op in operations {
            out.push('\n');
            out.push_str(&state.indent_str());
            write!(out, "({} :: ", op.name.name).unwrap();
            let ty: Type = if op.params.is_empty() {
                op.return_type.clone()
            } else {
                let mut result = op.return_type.clone();
                for param in op.params.iter().rev() {
                    result = Type::arr(param.clone(), result);
                }
                result
            };
            out.push_str(&format_type(&ty));
            out.push(')');
        }
        state.pop_indent();
    }
    out.push(')');
}

/// `deriving (Eq Show)` - the keyword OUTSIDE the parentheses.
///
/// This printed `(deriving Eq Show)`, with the keyword inside, which
/// `parse_data` does not accept: it expects `deriving` and then a
/// parenthesised list. So `fmt` refused every `data` declaration with a
/// `deriving` clause, and nothing in the repository has one - the same
/// blind spot as the applied type in §2.4h, in the neighbouring branch.
fn format_deriving(deriving: &[Ident], out: &mut String) {
    out.push_str(" deriving (");
    for (i, d) in deriving.iter().enumerate() {
        if i > 0 {
            out.push(' ');
        }
        out.push_str(&d.name);
    }
    out.push(')');
}

/// One constructor of a `data` declaration.
///
/// Named fields must be emitted named. Printing them through
/// `field_types()` erased the names - `(Circle { r : Int })` came back as
/// `(Circle Int)` - which is a struct variant silently demoted to a
/// positional one. Every `s.r` and every `(Rect { w, h })` pattern in the
/// program then failed to resolve against a constructor that, as far as
/// the file now said, had no named fields at all.
fn format_data_con(con: &DataCon, out: &mut String) {
    write!(out, "({}", con.name.name).unwrap();
    match &con.con_fields {
        ConFields::Positional(tys) => {
            for ty in tys {
                out.push(' ');
                out.push_str(&format_type(ty));
            }
        }
        ConFields::Named(fields) => {
            out.push_str(" {");
            for (i, f) in fields.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write!(out, " {} : {}", f.name.name, format_type(&f.ty)).unwrap();
            }
            out.push_str(" }");
        }
    }
    out.push(')');
}

fn format_type_vars(tyvars: &[String], out: &mut String) {
    if tyvars.len() == 1 {
        out.push_str(&tyvars[0]);
    } else {
        out.push('(');
        for (i, v) in tyvars.iter().enumerate() {
            if i > 0 {
                out.push(' ');
            }
            out.push_str(v);
        }
        out.push(')');
    }
}

/// A type, spelled so that it can be dropped into any position without
/// regrouping what encloses it.
///
/// A type application is written by juxtaposition, so `Tree a` is two
/// tokens with no delimiter of its own. Emitting it unparenthesised
/// silently changes the arity of whatever encloses it:
/// `(Node (Tree a) a (Tree a))` came back as `(Node Tree a a Tree a)`, a
/// constructor of five fields rather than three, and
/// `(-> (Tree Int) Int)` came back as `(-> Tree Int Int)`, a function of
/// two arguments rather than one. Both still *parse*, which is why the
/// formatter's own round-trip check passes them - the result is
/// well-formed source that means something else. Only type-checking the
/// output catches it, which is what `check-fmt.sh` now does.
///
/// This is the spelling every caller wants, and it is deliberately the
/// one with the short name. It used to be the exception - three of the
/// twenty places that print a type asked for it and the other seventeen
/// did not - which meant a parenthesised type application was destroyed
/// in fourteen of the sixteen positions the language allows one, and in
/// most of them the result did not even parse. Every other type form
/// brings its own delimiters (`(-> ..)`, `[..]`, `(* ..)`,
/// `(forall ..)`), so only an application needs wrapping.
fn format_type(ty: &Type) -> String {
    match ty {
        Type::TCon(_, args) if !args.is_empty() => format!("({})", format_type_bare(ty)),
        _ => format_type_bare(ty),
    }
}

/// The bare spelling, without the parentheses an application needs.
///
/// Correct in exactly one position: inside the parentheses `format_type`
/// has just written. Everywhere else - including every recursive call
/// below - use `format_type`.
fn format_type_bare(ty: &Type) -> String {
    match ty {
        Type::TVar(name) => name.clone(),
        Type::TCon(ident, args) => {
            if args.is_empty() {
                ident.name.clone()
            } else {
                let mut s = ident.name.clone();
                for a in args {
                    s.push(' ');
                    s.push_str(&format_type(a));
                }
                s
            }
        }
        Type::TArr(_, _) => {
            // Flatten the right spine so `(-> Int Int Int)` comes back out
            // the way it went in. Arrows are right-associated, so the
            // parser reads that as `(-> Int (-> Int Int))`; printing the
            // nested form is type-correct but is not the source the author
            // wrote, and it grows a level of parens per parameter on every
            // reformat.
            //
            // Only the result position is flattened. A function-typed
            // *argument* is formatted by the recursive call and keeps its
            // own parentheses, so `(-> (-> Int Int) Int)` is preserved
            // rather than collapsed into the wrong arity.
            let mut parts = Vec::new();
            let mut cur = ty;
            while let Type::TArr(from, to) = cur {
                parts.push(format_type(from));
                cur = to;
            }
            parts.push(format_type(cur));
            format!("(-> {})", parts.join(" "))
        }
        Type::TTuple(types) => {
            if types.is_empty() {
                "Unit".to_string()
            } else {
                let mut s = String::from('(');
                for (i, t) in types.iter().enumerate() {
                    if i > 0 {
                        s.push(' ');
                    }
                    s.push_str(&format_type(t));
                }
                s.push(')');
                s
            }
        }
        Type::TList(inner) => {
            format!("[{}]", format_type(inner))
        }
        Type::TPtr(inner, mutable) => {
            if *mutable {
                format!("(* mut {})", format_type(inner))
            } else {
                format!("(* {})", format_type(inner))
            }
        }
        Type::TForall(vars, inner) => {
            let mut s = String::from("(forall");
            for v in vars {
                s.push(' ');
                s.push_str(v);
            }
            s.push(' ');
            s.push_str(&format_type(inner));
            s.push(')');
            s
        }
        Type::TLinear(inner) => {
            format!("(linear {})", format_type(inner))
        }
    }
}

fn format_pattern(pat: &Pattern, out: &mut String) {
    match pat {
        Pattern::PVar(ident) => out.push_str(&ident.name),
        Pattern::PWildcard => out.push('_'),
        Pattern::PLit(lit) => format_literal(lit, out),
        Pattern::PCon(name, args) => {
            // The parentheses are what make this a constructor pattern.
            // Printing a nullary constructor as a bare `Red` turns it into
            // a *variable* pattern that binds anything, so `((Red) 1)`
            // became `(Red 1)` and matched every value instead of one -
            // every later arm in the match became unreachable. The program
            // still compiled and still ran; it just returned the first
            // arm's answer for every input.
            out.push('(');
            out.push_str(&name.name);
            for a in args {
                out.push(' ');
                format_pattern(a, out);
            }
            out.push(')');
        }
        Pattern::PConNamed(name, args) => {
            out.push('(');
            out.push_str(&name.name);
            out.push_str(" {");
            for (i, (fname, fpat)) in args.iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                out.push_str(&fname.name);
                out.push_str(" = ");
                format_pattern(fpat, out);
            }
            out.push('}');
            out.push(')');
        }
        Pattern::PTuple(pats) => {
            out.push('(');
            for (i, p) in pats.iter().enumerate() {
                if i > 0 {
                    out.push(' ');
                }
                format_pattern(p, out);
            }
            out.push(')');
        }
        Pattern::PList(pats) => {
            out.push('[');
            for (i, p) in pats.iter().enumerate() {
                if i > 0 {
                    out.push(' ');
                }
                format_pattern(p, out);
            }
            out.push(']');
        }
    }
}

/// Re-escape a character for output inside a string or character literal.
///
/// The lexer stores the *decoded* value, so a source `\n` is a real
/// newline in the AST and a source `\\d` is a real backslash followed by
/// `d`. Writing either back out verbatim does not round-trip: the newline
/// ends the literal, and the lone backslash re-reads as the escape `\d`,
/// which is not one - that is a formatted file that no longer lexes.
fn escape_char(c: char, out: &mut String) {
    match c {
        '\\' => out.push_str("\\\\"),
        '\n' => out.push_str("\\n"),
        '\r' => out.push_str("\\r"),
        '\t' => out.push_str("\\t"),
        '\0' => out.push_str("\\0"),
        '"' => out.push_str("\\\""),
        _ => out.push(c),
    }
}

fn format_literal(lit: &Literal, out: &mut String) {
    match lit {
        Literal::LInt(n) => write!(out, "{}", n).unwrap(),
        // `{:?}` rather than `{}`, so a float with no fractional part
        // keeps its point: `Display` renders `2.0` as `2`, which re-lexes
        // as an `Int` and turns `(* 2.0 x)` into integer multiplication
        // of a bit pattern.
        Literal::LFloat(n) => write!(out, "{:?}", n).unwrap(),
        Literal::LBool(b) => write!(out, "{}", b).unwrap(),
        Literal::LChar(c) => {
            out.push('\'');
            // A `"` needs no escaping inside a character literal, and
            // escaping it there would change the character.
            if *c == '"' {
                out.push('"');
            } else {
                escape_char(*c, out);
            }
            out.push('\'');
        }
        Literal::LStr(s) => {
            out.push('"');
            for c in s.chars() {
                escape_char(c, out);
            }
            out.push('"');
        }
    }
}

fn is_simple_expr(expr: &Expr) -> bool {
    match expr {
        Expr::EVar(_) | Expr::ELit(_, _) => true,
        Expr::EApp(f, a) => is_simple_expr(f) && is_simple_expr(a),
        Expr::EInfix(l, _, r) => is_simple_expr(l) && is_simple_expr(r),
        Expr::ETuple(items) => items.iter().all(is_simple_expr),
        Expr::EList(items) => items.iter().all(is_simple_expr),
        Expr::EField(base, _) => is_simple_expr(base),
        _ => false,
    }
}

fn format_expr(expr: &Expr, out: &mut String, state: &mut FormatState) {
    match expr {
        Expr::EVar(ident) => out.push_str(&ident.name),
        Expr::ELit(lit, _) => format_literal(lit, out),
        Expr::EApp(_, _) => {
            format_app(expr, out, state);
        }
        Expr::ELam(patterns, body) => {
            out.push_str("(lambda (");
            for (i, p) in patterns.iter().enumerate() {
                if i > 0 {
                    out.push(' ');
                }
                format_pattern(p, out);
            }
            out.push(')');
            if is_simple_expr(body) {
                out.push(' ');
                format_expr(body, out, state);
            } else {
                out.push('\n');
                state.push_indent();
                out.push_str(&state.indent_str());
                format_expr(body, out, state);
                state.pop_indent();
                out.push('\n');
                out.push_str(&state.indent_str());
            }
            out.push(')');
        }
        Expr::ELet(bindings, body) => {
            out.push_str("(let (");
            if bindings.len() == 1 {
                let (pat, init) = (&bindings[0].pat, &bindings[0].init);
                // `(x init)`, not `(x = init)`. Both parse in the Rust
                // front end, but the `=` spelling appears nowhere in the
                // corpus and the self-hosted parser in `self_host/` does
                // not implement it - so formatting a file rewrote it into
                // a dialect that stage1 could no longer compile, which is
                // the bootstrap breaking on a whitespace change.
                if bindings[0].mutable {
                    out.push_str("(mut ");
                } else {
                    out.push('(');
                }
                format_pattern(pat, out);
                out.push(' ');
                if is_simple_expr(init) {
                    format_expr(init, out, state);
                } else {
                    out.push('\n');
                    state.push_indent();
                    out.push_str(&state.indent_str());
                    format_expr(init, out, state);
                    state.pop_indent();
                    out.push('\n');
                    out.push_str(&state.indent_str());
                }
                out.push(')');
            } else {
                out.push('\n');
                state.push_indent();
                for (i, b) in bindings.iter().enumerate() {
                    let (pat, init) = (&b.pat, &b.init);
                    if i > 0 {
                        out.push('\n');
                    }
                    state.flush_leading(init.span().start, out);
                    let mark = out.len();
                    out.push_str(&state.indent_str());
                    out.push_str(if b.mutable { "(mut " } else { "(" });
                    format_pattern(pat, out);
                    out.push(' ');
                    format_expr(init, out, state);
                    out.push(')');
                    state.flush_trailing(init.span().start, mark, out);
                }
                state.pop_indent();
                out.push('\n');
                out.push_str(&state.indent_str());
            }
            out.push(')');
            out.push('\n');
            state.push_indent();
            out.push_str(&state.indent_str());
            format_expr(body, out, state);
            state.pop_indent();
            out.push('\n');
            out.push_str(&state.indent_str());
            out.push(')');
        }
        Expr::EWhile(cond, body) => {
            out.push_str("(while ");
            format_expr(cond, out, state);
            out.push('\n');
            state.push_indent();
            out.push_str(&state.indent_str());
            format_expr(body, out, state);
            state.pop_indent();
            out.push(')');
        }
        Expr::EAssign(target, value) => {
            out.push_str("(set ");
            out.push_str(&target.name);
            out.push(' ');
            format_expr(value, out, state);
            out.push(')');
        }
        Expr::EIf(cond, then, else_) => {
            let cond_mark = out.len();
            out.push_str("(if ");
            format_expr(cond, out, state);
            state.flush_trailing(cond.span().start, cond_mark, out);
            out.push('\n');
            state.push_indent();
            state.flush_leading(then.span().start, out);
            let then_mark = out.len();
            out.push_str(&state.indent_str());
            format_expr(then, out, state);
            state.flush_trailing(then.span().start, then_mark, out);
            out.push('\n');
            state.flush_leading(else_.span().start, out);
            out.push_str(&state.indent_str());
            format_expr(else_, out, state);
            state.pop_indent();
            out.push('\n');
            out.push_str(&state.indent_str());
            out.push(')');
        }
        Expr::EMatch(target, arms) => {
            out.push_str("(match ");
            format_expr(target, out, state);
            out.push('\n');
            state.push_indent();
            for (i, (pat, body)) in arms.iter().enumerate() {
                if i > 0 {
                    out.push('\n');
                }
                state.flush_leading(body.span().start, out);
                out.push_str(&state.indent_str());
                out.push('(');
                format_pattern(pat, out);
                if is_simple_expr(body) {
                    out.push(' ');
                    format_expr(body, out, state);
                } else {
                    out.push('\n');
                    state.push_indent();
                    out.push_str(&state.indent_str());
                    format_expr(body, out, state);
                    state.pop_indent();
                    out.push('\n');
                    out.push_str(&state.indent_str());
                }
                out.push(')');
            }
            state.pop_indent();
            out.push('\n');
            out.push_str(&state.indent_str());
            out.push(')');
        }
        Expr::ECond(branches, else_) => {
            out.push_str("(cond");
            out.push('\n');
            state.push_indent();
            for (i, (test, body)) in branches.iter().enumerate() {
                // One clause per line. Without this the closing paren of
                // one clause and the opening paren of the next shared a
                // line: `)    ((== n 0)`.
                if i > 0 {
                    out.push('\n');
                }
                state.flush_leading(test.span().start, out);
                out.push_str(&state.indent_str());
                out.push('(');
                format_expr(test, out, state);
                // A clause whose body fits beside its test reads far
                // better than one broken across three lines, and `cond`
                // exists precisely to put a column of short cases
                // together.
                if is_simple_expr(body) {
                    out.push(' ');
                    format_expr(body, out, state);
                } else {
                    out.push('\n');
                    state.push_indent();
                    out.push_str(&state.indent_str());
                    format_expr(body, out, state);
                    state.pop_indent();
                    out.push('\n');
                    out.push_str(&state.indent_str());
                }
                out.push(')');
            }
            if let Some(else_body) = else_ {
                if !branches.is_empty() {
                    out.push('\n');
                }
                out.push_str(&state.indent_str());
                out.push_str("(else ");
                if is_simple_expr(else_body) {
                    format_expr(else_body, out, state);
                } else {
                    out.push('\n');
                    state.push_indent();
                    out.push_str(&state.indent_str());
                    format_expr(else_body, out, state);
                    state.pop_indent();
                    out.push('\n');
                    out.push_str(&state.indent_str());
                }
                out.push(')');
            }
            state.pop_indent();
            out.push('\n');
            out.push_str(&state.indent_str());
            out.push(')');
        }
        Expr::EBegin(exprs) => {
            out.push_str("{\n");
            state.push_indent();
            for (i, e) in exprs.iter().enumerate() {
                if i > 0 {
                    out.push('\n');
                }
                state.flush_leading(e.span().start, out);
                let mark = out.len();
                out.push_str(&state.indent_str());
                format_expr(e, out, state);
                state.flush_trailing(e.span().start, mark, out);
            }
            state.pop_indent();
            out.push('\n');
            out.push_str(&state.indent_str());
            out.push('}');
        }
        Expr::ETuple(items) => {
            out.push('(');
            for (i, e) in items.iter().enumerate() {
                if i > 0 {
                    out.push(' ');
                }
                format_expr(e, out, state);
            }
            out.push(')');
        }
        Expr::EList(items) => {
            if items.is_empty() {
                out.push_str("[]");
            } else if items.iter().all(is_simple_expr) {
                out.push('[');
                for (i, e) in items.iter().enumerate() {
                    if i > 0 {
                        out.push(' ');
                    }
                    format_expr(e, out, state);
                }
                out.push(']');
            } else {
                out.push_str("[\n");
                state.push_indent();
                for e in items {
                    out.push_str(&state.indent_str());
                    format_expr(e, out, state);
                }
                state.pop_indent();
                out.push('\n');
                out.push_str(&state.indent_str());
                out.push(']');
            }
        }
        Expr::EInfix(left, op, right) => {
            // Unary minus arrives as `EInfix(0, "-", x)` - the parser's
            // desugaring of `-5` and `(- x)`. Printing that desugared
            // form as `(0 - 5)` wrote infix spelling into files whose
            // corpus is otherwise pure prefix; the literal gets its
            // sign back, and the general case prints as the prefix
            // subtraction it means.
            if op == "-" && matches!(**left, Expr::ELit(Literal::LInt(0), _)) {
                match &**right {
                    Expr::ELit(Literal::LInt(n), _) => {
                        write!(out, "-{}", n).unwrap();
                        return;
                    }
                    Expr::ELit(Literal::LFloat(f), _) => {
                        // `{:?}` keeps the decimal point (`2.0`, not
                        // `2`), matching the positive-literal printer.
                        write!(out, "-{:?}", f).unwrap();
                        return;
                    }
                    _ => {
                        out.push_str("(- 0 ");
                        format_expr(right, out, state);
                        out.push(')');
                        return;
                    }
                }
            }
            out.push('(');
            format_expr(left, out, state);
            out.push(' ');
            out.push_str(op);
            out.push(' ');
            format_expr(right, out, state);
            out.push(')');
        }
        Expr::ETypeSig(inner, ty) => {
            out.push_str("(:: ");
            format_expr(inner, out, state);
            write!(out, " {})", format_type(ty)).unwrap();
        }
        Expr::ECast(inner, ty) => {
            out.push_str("(cast ");
            out.push_str(&format_type(ty));
            out.push(' ');
            format_expr(inner, out, state);
            out.push(')');
        }
        Expr::EAlloc(ty, count, _) => {
            out.push_str("(alloc ");
            out.push_str(&format_type(ty));
            if let Some(c) = count {
                out.push(' ');
                format_expr(c, out, state);
            }
            out.push(')');
        }
        Expr::ESizeof(ty, _) => {
            write!(out, "(sizeof {})", format_type(ty)).unwrap();
        }
        Expr::EAlignof(ty, _) => {
            write!(out, "(alignof {})", format_type(ty)).unwrap();
        }
        Expr::EGrouped(inner) => {
            out.push('\'');
            format_expr(inner, out, state);
        }
        Expr::EHandle(body, effects, handler) => {
            out.push_str("(handle ");
            format_expr(body, out, state);
            out.push_str(" (");
            for (i, e) in effects.iter().enumerate() {
                if i > 0 {
                    out.push(' ');
                }
                out.push_str(&format!("{}", e));
            }
            out.push_str(") ");
            format_expr(handler, out, state);
            out.push(')');
        }
        Expr::EConsume(inner) => {
            out.push_str("(consume ");
            format_expr(inner, out, state);
            out.push(')');
        }
        Expr::EField(base, field_ident) => {
            format_expr(base, out, state);
            out.push('.');
            out.push_str(&field_ident.name);
        }
        Expr::EStructCon(name, args) => {
            // `(struct Name field...)`, keyword and parens included -
            // the same class of never-exercised spelling as
            // `ESetField` below. This printed `Name field...` bare,
            // which is not an expression at all: `(struct P 40 2)`
            // formatted to `P 40 2`, and the result either failed to
            // parse or re-parsed as an application and lost its
            // arguments on the next pass. Nothing in the corpus used
            // the form until a conformance case did, so the fmt zoo
            // carries one now.
            out.push_str("(struct ");
            out.push_str(&name.name);
            for arg in args.iter() {
                out.push(' ');
                format_expr(arg, out, state);
            }
            out.push(')');
        }
        Expr::ESetField(base, field_ident, value) => {
            // `(set base.field v)`, not `(set-field base field v)`.
            // There is no `set-field` form in the language - the
            // spelling here was invented, and could never round-trip,
            // because until now nothing could produce an `ESetField` for
            // the formatter to print.
            out.push_str("(set ");
            format_expr(base, out, state);
            out.push('.');
            out.push_str(&field_ident.name);
            out.push(' ');
            format_expr(value, out, state);
            out.push(')');
        }
        Expr::EError(msg, _) => {
            write!(out, "_{}", msg).unwrap();
        }
        Expr::EQuasiquote(inner) => {
            out.push('`');
            format_expr(inner, out, state);
        }
        Expr::EUnquote(inner) => {
            out.push(',');
            format_expr(inner, out, state);
        }
        Expr::EQualified(path, name) => {
            for seg in path.iter() {
                out.push_str(&seg.name);
                out.push_str("::");
            }
            out.push_str(&name.name);
        }
        Expr::ESplice(inner) => {
            out.push_str(",@");
            format_expr(inner, out, state);
        }
    }
}

fn format_app(expr: &Expr, out: &mut String, state: &mut FormatState) {
    let mut func = expr;
    let mut args = Vec::new();

    while let Expr::EApp(f, a) = func {
        args.push(a.as_ref());
        func = f.as_ref();
    }

    args.reverse();

    if is_simple_expr(func) && args.iter().all(|a| is_simple_expr(a)) && args.len() <= 4 {
        out.push('(');
        format_expr(func, out, state);
        for a in &args {
            out.push(' ');
            format_expr(a, out, state);
        }
        out.push(')');
    } else {
        out.push('(');
        format_expr(func, out, state);
        out.push('\n');
        state.push_indent();
        for a in &args {
            out.push_str(&state.indent_str());
            format_expr(a, out, state);
        }
        state.pop_indent();
        out.push('\n');
        out.push_str(&state.indent_str());
        out.push(')');
    }
}
