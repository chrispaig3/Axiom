use axiom_ast::ast::*;
use axiom_ast::span::Ident;
use std::fmt::Write;

const INDENT: &str = "  ";

pub fn format_module(module: &Module) -> String {
    let mut out = String::new();
    let mut state = FormatState::new();

    for (i, decl) in module.decls.iter().enumerate() {
        if i > 0 {
            out.push('\n');
        }
        format_decl(decl, &mut out, &mut state);
        out.push('\n');
    }

    out
}

struct FormatState {
    indent_level: usize,
}

impl FormatState {
    fn new() -> Self {
        Self { indent_level: 0 }
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
}

fn format_decl(decl: &Decl, out: &mut String, state: &mut FormatState) {
    match decl {
        Decl::DSig { name, ty, .. } => {
            write!(out, "(:: {} {})", name, format_type(ty)).unwrap();
        }
        Decl::DFn {
            name, params, body, ..
        } => {
            format_function_decl(name, params, body, out, state);
        }
        Decl::DData {
            name,
            tyvars,
            constructors,
            deriving,
            ..
        } => {
            format_data_decl(name, tyvars, constructors, deriving, out, state);
        }
        Decl::DStruct {
            name,
            tyvars,
            fields,
            repr,
            ..
        } => {
            format_struct_decl(name, tyvars, fields, repr, out, state);
        }
        Decl::DType {
            name,
            tyvars,
            alias,
            ..
        } => {
            write!(out, "(type {}", name.name).unwrap();
            if !tyvars.is_empty() {
                out.push(' ');
                format_type_vars(tyvars, out);
            }
            write!(out, " {})", format_type(alias)).unwrap();
        }
        Decl::DForeign {
            name, ty, source, ..
        } => {
            write!(
                out,
                "(foreign {} :: {} = \"{}\")",
                name,
                format_type(ty),
                source
            )
            .unwrap();
        }
        Decl::DImport { module, names } => {
            out.push_str("(import");
            for m in module {
                write!(out, " {}", m.name).unwrap();
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
            format_trait_decl(name, tyvar, supertraits, methods, effects, out, state);
        }
        Decl::DImpl {
            trait_name,
            ty,
            methods,
            effects,
            ..
        } => {
            format_impl_decl(trait_name, ty, methods, effects, out, state);
        }
        Decl::DEffect {
            name, operations, ..
        } => {
            format_effect_decl(name, operations, out, state);
        }
        Decl::DMacro { name, params, body, .. } => {
            write!(out, "(macro ({} ", name.name).unwrap();
            format_pattern(params, out);
            write!(out, ") ").unwrap();
            format_expr(body, out, state);
            out.push(')');
        }
    }
}

fn format_function_decl(
    name: &Ident,
    params: &[Pattern],
    body: &Expr,
    out: &mut String,
    state: &mut FormatState,
) {
    out.push_str("(define (");
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
        out.push_str(&state.indent_str());
        format_expr(body, out, state);
        state.pop_indent();
        out.push('\n');
        out.push_str(&state.indent_str());
        out.push(')');
    }
}

fn format_data_decl(
    name: &Ident,
    tyvars: &[String],
    constructors: &[DataCon],
    deriving: &[Ident],
    out: &mut String,
    state: &mut FormatState,
) {
    out.push_str("(data ");
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
            out.push_str(" (deriving");
            for d in deriving {
                write!(out, " {}", d.name).unwrap();
            }
            out.push(')');
        }
        out.push(')');
    } else {
        for con in constructors {
            out.push('\n');
            state.push_indent();
            out.push_str(&state.indent_str());
            write!(out, "({}", con.name.name).unwrap();
            for ty in con.field_types() {
                out.push(' ');
                out.push_str(&format_type(ty));
            }
            out.push(')');
            state.pop_indent();
        }
        if !deriving.is_empty() {
            out.push_str(" (deriving");
            for d in deriving {
                write!(out, " {}", d.name).unwrap();
            }
            out.push(')');
        }
        out.push(')');
    }
}

fn format_struct_decl(
    name: &Ident,
    tyvars: &[String],
    fields: &[Field],
    repr: &Option<TypeRepr>,
    out: &mut String,
    state: &mut FormatState,
) {
    out.push_str("(struct ");
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
        out.push('\n');
        state.push_indent();
        for f in fields {
            out.push_str(&state.indent_str());
            write!(out, "({} {})", f.name.name, format_type(&f.ty)).unwrap();
            if f.mutable {
                out.push_str(" mut");
            }
        }
        state.pop_indent();
    }
    out.push(')');
}

fn format_trait_decl(
    name: &Ident,
    tyvar: &str,
    supertraits: &[Type],
    methods: &[TraitMethod],
    effects: &[Effect],
    out: &mut String,
    state: &mut FormatState,
) {
    out.push_str("(trait (");
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
    if !supertraits.is_empty() {
        out.push('\n');
        state.push_indent();
        for s in supertraits {
            out.push_str(&state.indent_str());
            out.push_str(&format_type(s));
        }
        state.pop_indent();
    }
    if !methods.is_empty() {
        out.push('\n');
        state.push_indent();
        for m in methods {
            out.push_str(&state.indent_str());
            write!(out, "({} {}", m.name.name, format_type(&m.ty)).unwrap();
            if !m.effects.is_empty() {
                out.push(' ');
                out.push('(');
                for (i, e) in m.effects.iter().enumerate() {
                    if i > 0 {
                        out.push(' ');
                    }
                    out.push_str(&format!("{}", e));
                }
                out.push(')');
            }
            if let Some(default) = &m.default {
                out.push('\n');
                state.push_indent();
                out.push_str(&state.indent_str());
                format_expr(default, out, state);
                state.pop_indent();
            }
            out.push(')');
        }
        state.pop_indent();
    }
    out.push(')');
}

fn format_impl_decl(
    trait_name: &Ident,
    ty: &Type,
    methods: &[(Ident, Expr)],
    effects: &[Effect],
    out: &mut String,
    state: &mut FormatState,
) {
    out.push_str("(impl (");
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
    if !methods.is_empty() {
        out.push('\n');
        state.push_indent();
        for (name, body) in methods {
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
    }
    out.push(')');
}

fn format_effect_decl(
    name: &Ident,
    operations: &[EffectOp],
    out: &mut String,
    state: &mut FormatState,
) {
    out.push_str("(effect ");
    out.push_str(&name.name);
    if !operations.is_empty() {
        out.push('\n');
        state.push_indent();
        for op in operations {
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

fn format_type(ty: &Type) -> String {
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
        Type::TArr(from, to) => {
            format!("(-> {} {})", format_type(from), format_type(to))
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
        Type::TEffect(inner, effects) => {
            let mut s = format_type(inner);
            if !effects.is_empty() {
                s.push_str(" (effect");
                for e in effects {
                    s.push(' ');
                    s.push_str(&format!("{}", e));
                }
                s.push(')');
            }
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
            if args.is_empty() {
                out.push_str(&name.name);
            } else {
                out.push('(');
                out.push_str(&name.name);
                for a in args {
                    out.push(' ');
                    format_pattern(a, out);
                }
                out.push(')');
            }
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

fn format_literal(lit: &Literal, out: &mut String) {
    match lit {
        Literal::LInt(n) => write!(out, "{}", n).unwrap(),
        Literal::LFloat(n) => write!(out, "{}", n).unwrap(),
        Literal::LBool(b) => write!(out, "{}", b).unwrap(),
        Literal::LChar(c) => write!(out, "'{}'", c).unwrap(),
        Literal::LStr(s) => write!(out, "\"{}\"", s).unwrap(),
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
                let (pat, init) = &bindings[0];
                out.push('(');
                format_pattern(pat, out);
                out.push_str(" = ");
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
                for (i, (pat, init)) in bindings.iter().enumerate() {
                    if i > 0 {
                        out.push('\n');
                    }
                    out.push_str(&state.indent_str());
                    out.push('(');
                    format_pattern(pat, out);
                    out.push_str(" = ");
                    format_expr(init, out, state);
                    out.push(')');
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
        Expr::EIf(cond, then, else_) => {
            out.push_str("(if ");
            format_expr(cond, out, state);
            out.push('\n');
            state.push_indent();
            out.push_str(&state.indent_str());
            format_expr(then, out, state);
            out.push('\n');
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
            for (test, body) in branches {
                out.push_str(&state.indent_str());
                out.push('(');
                format_expr(test, out, state);
                out.push('\n');
                state.push_indent();
                out.push_str(&state.indent_str());
                format_expr(body, out, state);
                state.pop_indent();
                out.push('\n');
                out.push_str(&state.indent_str());
                out.push(')');
            }
            if let Some(else_body) = else_ {
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
                out.push_str(&state.indent_str());
                format_expr(e, out, state);
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
            out.push_str(&name.name);
            out.push(' ');
            for (i, arg) in args.iter().enumerate() {
                if i > 0 {
                    out.push(' ');
                }
                format_expr(arg, out, state);
            }
        }
        Expr::ESetField(base, field_ident, value) => {
            out.push_str("(set-field ");
            format_expr(base, out, state);
            out.push(' ');
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
