use crate::{IrBlock, IrConst, IrFunction, IrInst, IrModule, IrStruct, IrValue, TypeId};
use axiom_ast::ast::*;
use axiom_ast::span::Ident;
use axiom_sema::TypeChecker;
use std::collections::{HashMap, HashSet};

pub struct TailContext {
    pub func_name: String,
    pub entry_label: String,
    pub param_names: Vec<String>,
    pub arena_mark: Option<String>,
}

pub struct IrGen {
    module: IrModule,
    local_counter: usize,
    block_counter: usize,
    lambda_counter: usize,
    /// Monotonic counter behind [`IrGen::new_alloca`].
    ///
    /// Alloca names used to be derived from the source name alone
    /// (`_alloca_x`), which is not unique: a function that binds `x` in two
    /// `match` arms, or shadows a parameter with a `let`, emitted
    /// `%_alloca_x = alloca i64` twice in one LLVM function - rejected by
    /// `llc` ("multiple definition of local value") rather than by a
    /// diagnostic. Every alloca now carries a per-function-independent
    /// serial number so no two can ever collide.
    alloca_counter: usize,
    current_block: Option<String>,
    entry_block: Option<String>,
    /// Constructor tags whose data type has *only* nullary constructors.
    /// These are stored as immediates (no heap allocation) because every
    /// value of the type is a simple tag — there are no boxed fields.
    nullary_tags: HashSet<i64>,
    /// Alloca names whose stored value is a raw constructor tag
    /// (from an all-nullary `data` type).  When `EVar` loads them
    /// it returns `IrValue::Tag` so that the match machinery can
    /// skip the box-unbox round-trip.
    tag_alloca_names: HashSet<String>,
    /// Top-level functions declared with no parameters.
    ///
    /// A bare `foo` where `foo` is nullary has to lower to a *call*,
    /// not to a variable read: there is no local named `foo`, so
    /// reading one produced LLVM referencing an undefined value and
    /// failed at `llc` rather than at a diagnostic. Nullary functions
    /// are how Axiom source expresses a named constant (there is no
    /// `const` declaration), so the standard library's syscall-number
    /// and flag tables depend on this.
    nullary_fns: HashSet<String>,
    all_fns: HashSet<String>,
    current_fn_has_raw: bool,
}

/// Look up a data constructor by name across every `data` type the type
/// checker collected, returning:
///
/// * a globally-unique integer tag - unique across every constructor in
///   the program, not just within one `data` type, so two different
///   `data` types' constructors can never compare equal by accident
///   during pattern matching;
/// * its arity, decomposed from the constructor's curried arrow type
///   (`Field1 -> Field2 -> ... -> TheType`; zero `TArr`s means a nullary
///   constructor).
///
/// The tag is the constructor's *ordinal position in a flat walk of every
/// `data` type's constructor list*, not `data_type_index * stride +
/// constructor_index`. A strided scheme has to pick a stride, and any
/// stride caps both the number of constructors one `data` type may declare
/// and the number of `data` types a program may contain before two
/// distinct constructors collide on a tag - a miscompile with no
/// diagnostic, since matching would then accept the wrong constructor. A
/// flat ordinal is unique by construction with no cap at all.
///
/// Determinism is what makes this safe: the walk order is
/// `type_checker.data_types`' own order, which is fixed for the whole
/// compilation, so every call agrees on every tag.
///
/// Both constructor *construction* (`EVar`/`EApp`, see
/// [`IrGen::gen_construct`]) and constructor *matching* (`EMatch`) call
/// this, so a value built with one tag is always compared against that
/// exact same tag - there is exactly one place in the generator that
/// decides what a constructor's tag is.
fn find_constructor(type_checker: &TypeChecker, name: &str) -> Option<(i64, usize)> {
    let mut tag: i64 = 0;
    for dt in type_checker.data_types.iter() {
        for con in dt.constructors.iter() {
            if con.name == name {
                let arity = constructor_arity(&con.ty);
                return Some((tag, arity));
            }
            tag += 1;
        }
    }
    None
}

fn constructor_arity(ty: &TypeId) -> usize {
    let mut n = 0;
    let mut current = ty;
    while let TypeId::TArr(_, rest) = current {
        n += 1;
        current = rest;
    }
    n
}

fn constructor_field_names(
    type_checker: &TypeChecker,
    con_name: &str,
) -> Option<Vec<String>> {
    for dt in &type_checker.data_types {
        for con in &dt.constructors {
            if con.name == con_name {
                return con.field_names.clone();
            }
        }
    }
    None
}

impl Default for IrGen {
    fn default() -> Self {
        Self::new()
    }
}

fn free_variables(body: &Expr, params: &[Pattern]) -> Vec<String> {
    let mut bound: HashSet<String> = params
        .iter()
        .filter_map(|p| {
            if let Pattern::PVar(ident) = p {
                Some(ident.name.clone())
            } else {
                None
            }
        })
        .collect();
    let mut free = Vec::new();
    collect_free(body, &mut bound, &mut free);
    free
}

fn collect_free(expr: &Expr, bound: &mut HashSet<String>, out: &mut Vec<String>) {
    match expr {
        Expr::EVar(ident) => {
            if !bound.contains(&ident.name) && !out.contains(&ident.name) && !is_builtin(&ident.name)
            {
                out.push(ident.name.clone());
            }
        }
        Expr::ELam(params, body) => {
            let mut inner_bound = bound.clone();
            for p in params {
                if let Pattern::PVar(ident) = p {
                    inner_bound.insert(ident.name.clone());
                }
            }
            collect_free(body, &mut inner_bound, out);
        }
        Expr::ELet(bindings, body) => {
            for (pat, init) in bindings {
                collect_free(init, bound, out);
                if let Pattern::PVar(ident) = pat {
                    let mut inner_bound = bound.clone();
                    inner_bound.insert(ident.name.clone());
                    collect_free(body, &mut inner_bound, out);
                }
            }
        }
        Expr::EApp(func, arg) => {
            collect_free(func, bound, out);
            collect_free(arg, bound, out);
        }
        Expr::EIf(cond, then_expr, else_expr) => {
            collect_free(cond, bound, out);
            collect_free(then_expr, bound, out);
            collect_free(else_expr, bound, out);
        }
        Expr::EBegin(exprs) => {
            for e in exprs {
                collect_free(e, bound, out);
            }
        }
        Expr::EMatch(target, arms) => {
            collect_free(target, bound, out);
            for (pat, body) in arms {
                let mut arm_bound = bound.clone();
                add_pat_bindings(pat, &mut arm_bound);
                collect_free(body, &mut arm_bound, out);
            }
        }
        Expr::EInfix(left, _, right) => {
            collect_free(left, bound, out);
            collect_free(right, bound, out);
        }
        Expr::ETuple(elems) | Expr::EList(elems) => {
            for e in elems {
                collect_free(e, bound, out);
            }
        }
        Expr::ECast(inner, _) | Expr::EConsume(inner) | Expr::EGrouped(inner)
        | Expr::ETypeSig(inner, _) => {
            collect_free(inner, bound, out);
        }
        Expr::ESizeof(_, _) | Expr::EAlignof(_, _) => {}
        Expr::EHandle(inner, _, _) => {
            collect_free(inner, bound, out);
        }
        Expr::EField(inner, _) => {
            collect_free(inner, bound, out);
        }
        Expr::EAlloc(_, Some(init), _) => {
            collect_free(init, bound, out);
        }
        Expr::EAlloc(_, None, _) => {}
        Expr::ESetField(inner, _, value) => {
            collect_free(inner, bound, out);
            collect_free(value, bound, out);
        }
        Expr::ECond(clauses, default) => {
            for (cond, body) in clauses {
                collect_free(cond, bound, out);
                collect_free(body, bound, out);
            }
            if let Some(def) = default {
                collect_free(def, bound, out);
            }
        }
        Expr::EStructCon(_, args) => {
            for a in args {
                collect_free(a, bound, out);
            }
        }
        _ => {}
    }
}

fn is_builtin(name: &str) -> bool {
    matches!(
        name,
        "+" | "-" | "*" | "/" | "%"
            | "==" | "!=" | "<" | ">" | "<=" | ">="
            | "&&" | "||"
            | "memAlloc"
            | "memSetWord"
            | "memGetWord"
            | "memCopy"
            | "memSetByte"
            | "memGetByte"
    )
}

fn add_pat_bindings(pat: &Pattern, bound: &mut HashSet<String>) {
    match pat {
        Pattern::PVar(ident) => {
            bound.insert(ident.name.clone());
        }
        Pattern::PConNamed(_, named_args) => {
            for (_, a) in named_args {
                add_pat_bindings(a, bound);
            }
        }
        Pattern::PCon(_, args) | Pattern::PTuple(args) | Pattern::PList(args) => {
            for a in args {
                add_pat_bindings(a, bound);
            }
        }
        _ => {}
    }
}

impl IrGen {
    pub fn new() -> Self {
        Self {
            module: IrModule::new(),
            local_counter: 0,
            block_counter: 0,
            lambda_counter: 0,
            alloca_counter: 0,
            current_block: None,
            entry_block: None,
            nullary_tags: HashSet::new(),
            tag_alloca_names: HashSet::new(),
            nullary_fns: HashSet::new(),
            all_fns: HashSet::new(),
            current_fn_has_raw: false,
        }
    }

    pub fn generate(&mut self, ast_module: &Module, type_checker: &mut TypeChecker) -> IrModule {
        // Collected up front, before any body is lowered, so a
        // nullary function can be referenced by a function defined
        // above it (declaration order is not significant in Axiom -
        // `axiom-sema`'s checker is two-pass for the same reason).
        self.nullary_fns = ast_module
            .decls
            .iter()
            .filter_map(|d| match d {
                Decl::DFn { name, params, .. } if params.is_empty() => Some(name.name.clone()),
                _ => None,
            })
            .collect();

        self.all_fns = ast_module
            .decls
            .iter()
            .filter_map(|d| match d {
                Decl::DFn { name, .. } => Some(name.name.clone()),
                _ => None,
            })
            .collect();

        self.nullary_tags = {
            let mut tags: HashSet<i64> = HashSet::new();
            // S1: unboxed nullary constructors — disabled for now.
            // When enabled, uncomment the loop below to populate tags
            // for all-nullary data types.  The per-alloca Tag tracking
            // (`tag_alloca_names`, `IrValue::Tag`, `box_if_tag`) is
            // already wired; only the tag-set population is off.
            let mut tag: i64 = 0;
            for dt in &type_checker.data_types {
                let _all_nullary = dt.constructors.iter().all(|c| constructor_arity(&c.ty) == 0);
                for con in &dt.constructors {
                    if false /* all_nullary */ {
                        tags.insert(tag);
                    }
                    let arity = constructor_arity(&con.ty);
                    while self.module.tag_arities.len() <= tag as usize {
                        self.module.tag_arities.push(0);
                    }
                    self.module.tag_arities[tag as usize] = arity;
                    tag += 1;
                }
            }
            tags
        };

        for decl in &ast_module.decls {
            match decl {
                Decl::DStruct {
                    name, fields, repr, ..
                } => {
                    let packed = matches!(repr, Some(TypeRepr::Packed));
                    let align = if let Some(TypeRepr::Align(n)) = repr {
                        Some(*n)
                    } else {
                        None
                    };

                    let ir_fields: Vec<(String, TypeId)> = fields
                        .iter()
                        .map(|f| (f.name.name.clone(), self.type_to_id(&f.ty)))
                        .collect();

                    self.module.structs.push(IrStruct {
                        name: name.name.clone(),
                        fields: ir_fields,
                        packed,
                        align,
                    });
                }
                Decl::DFn {
                    name, params, body, ..
                } => {
                    let func = self.gen_function(name, params, body, type_checker);
                    self.module.functions.push(func);
                }
                Decl::DForeign { name, ty, .. } => {
                    let mut params = Vec::new();
                    let mut current = self.type_to_id(ty);
                    while let TypeId::TArr(param, rest) = current {
                        params.push(*param);
                        current = *rest;
                    }
                    self.module
                        .extern_funcs
                        .push((name.name.clone(), params, current));
                }
                Decl::DSig { name, ty, .. } => {
                    let _ = (name, ty);
                }
                _ => {}
            }
        }

        std::mem::take(&mut self.module)
    }

    fn gen_function(
        &mut self,
        name: &Ident,
        params: &[Pattern],
        body: &Expr,
        type_checker: &mut TypeChecker,
    ) -> IrFunction {
        let mut fn_params: Vec<(String, TypeId)> = Vec::new();
        fn_params.push(("_closure".to_string(), TypeId::TCon("I64".to_string(), vec![])));
        for p in params {
            if let Pattern::PVar(ident) = p {
                fn_params.push((ident.name.clone(), TypeId::TCon("I64".to_string(), vec![])));
            }
        }

        let return_type = TypeId::TCon("I64".to_string(), vec![]);

        let mut func = IrFunction {
            name: name.name.clone(),
            params: fn_params.clone(),
            return_type,
            blocks: Vec::new(),
            locals: Vec::new(),
        };

        let entry_label = self.new_block_label();
        self.current_block = Some(entry_label.clone());
        self.entry_block = Some(entry_label.clone());

        func.blocks.push(IrBlock {
            label: entry_label.clone(),
            insts: Vec::new(),
        });

        let mut alloca_map: HashMap<String, String> = HashMap::new();

        for (pname, pty) in &fn_params {
            let alloca_name = self.new_alloca(pname);
            func.locals.push((pname.clone(), pty.clone()));
            self.emit_to_func(
                &mut func,
                IrInst::Alloca {
                    dest: IrValue::Local(alloca_name.clone()),
                    ty: pty.clone(),
                },
            );
            self.emit_to_func(
                &mut func,
                IrInst::Store {
                    ptr: IrValue::Local(alloca_name.clone()),
                    value: IrValue::Local(pname.clone()),
                },
            );
            alloca_map.insert(pname.clone(), alloca_name.clone());
        }

        let body_header = self.new_block_label();
        self.emit_to_func(
            &mut func,
            IrInst::Br {
                target: body_header.clone(),
            },
        );
        func.blocks.push(IrBlock {
            label: body_header.clone(),
            insts: Vec::new(),
        });
        self.current_block = Some(body_header.clone());

        let tc = TailContext {
            func_name: name.name.clone(),
            entry_label: body_header.clone(),
            param_names: fn_params
                .iter()
                .skip(1) // skip _closure
                .map(|(n, _)| n.clone())
                .collect(),
            arena_mark: None,
        };

        self.current_fn_has_raw = false;

        let body_val =
            self.gen_expr_to_func_with_allocas(&mut func, body, &mut alloca_map, type_checker, Some(&tc));

        self.emit_to_func(
            &mut func,
            IrInst::Ret {
                value: Some(body_val),
            },
        );

        self.entry_block = None;

        func
    }

    /// Build a heap-boxed constructor value: `HeapAlloc` a block of `(1 +
    /// args.len()) * 8` bytes, `StoreOffset` the tag into word 0, then
    /// `StoreOffset` each argument into words `1..`. Every `data`
    /// constructor - nullary or not - goes through this one path, so
    /// there is exactly one runtime representation for a value of a given
    /// `data` type regardless of which constructor produced it (see
    /// [`find_constructor`] and the module-level `HeapAlloc` docs in
    /// `axiom-ir`'s `lib.rs`).
    fn box_if_tag(&mut self, func: &mut IrFunction, value: &IrValue) -> IrValue {
        let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
        if let IrValue::Const(IrConst::Int(tag, _)) = value {
            if self.nullary_tags.contains(tag) {
                let box_ptr = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::HeapAlloc {
                        dest: IrValue::Local(box_ptr.clone()),
                        size: IrValue::Const(IrConst::Int(8, i64_ty.clone())),
                    },
                );
                self.emit_to_func(
                    func,
                    IrInst::StoreOffset {
                        ptr: IrValue::Local(box_ptr.clone()),
                        offset: 0,
                        value: IrValue::Const(IrConst::Int(*tag, i64_ty.clone())),
                    },
                );
                return IrValue::Local(box_ptr);
            }
        }
        if let IrValue::Tag(_) = value {
            let box_ptr = self.new_local();
            self.emit_to_func(
                func,
                IrInst::HeapAlloc {
                    dest: IrValue::Local(box_ptr.clone()),
                    size: IrValue::Const(IrConst::Int(8, i64_ty.clone())),
                },
            );
            self.emit_to_func(
                func,
                IrInst::StoreOffset {
                    ptr: IrValue::Local(box_ptr.clone()),
                    offset: 0,
                    value: value.clone(),
                },
            );
            return IrValue::Local(box_ptr);
        }
        value.clone()
    }

    fn gen_construct(&mut self, func: &mut IrFunction, tag: i64, args: Vec<IrValue>) -> IrValue {
        let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
        if args.is_empty() && self.nullary_tags.contains(&tag) {
            return IrValue::Const(IrConst::Int(tag, i64_ty));
        }
        let size = ((1 + args.len()) * 8) as i64;
        let ptr_local = self.new_local();

        self.emit_to_func(
            func,
            IrInst::HeapAlloc {
                dest: IrValue::Local(ptr_local.clone()),
                size: IrValue::Const(IrConst::Int(size, i64_ty.clone())),
            },
        );
        self.emit_to_func(
            func,
            IrInst::StoreOffset {
                ptr: IrValue::Local(ptr_local.clone()),
                offset: 0,
                value: IrValue::Const(IrConst::Int(tag, i64_ty.clone())),
            },
        );
        for (i, arg) in args.into_iter().enumerate() {
            let needs_box = matches!(&arg, IrValue::Const(IrConst::Int(val, _)) if self.nullary_tags.contains(val));
            let arg_val = if needs_box {
                let val = if let IrValue::Const(IrConst::Int(v, _)) = arg { v } else { unreachable!() };
                let box_ptr = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::HeapAlloc {
                        dest: IrValue::Local(box_ptr.clone()),
                        size: IrValue::Const(IrConst::Int(8, i64_ty.clone())),
                    },
                );
                self.emit_to_func(
                    func,
                    IrInst::StoreOffset {
                        ptr: IrValue::Local(box_ptr.clone()),
                        offset: 0,
                        value: IrValue::Const(IrConst::Int(val, i64_ty.clone())),
                    },
                );
                IrValue::Local(box_ptr)
            } else {
                arg
            };
            self.emit_to_func(
                func,
                IrInst::StoreOffset {
                    ptr: IrValue::Local(ptr_local.clone()),
                    offset: ((1 + i) * 8) as i64,
                    value: arg_val,
                },
            );
        }

        IrValue::Local(ptr_local)
    }

    /// Generate IR to check sub-patterns of a `PCon` arm or
    /// elements of a `PTuple`/`PList` arm against the fields
    /// of a boxed constructor or tuple/list value.
    ///
    /// `target_val` is the pointer (as an `i64` local) to the
    /// boxed block whose fields should be extracted and compared.
    /// `pats` are the sub-patterns to match against the fields.
    /// `field_offset` is the byte offset of the first field
    /// within `target_val` (`1 * 8` for `PCon` arms, `0` for
    /// tuples/lists). Each subsequent sub-pattern uses the
    /// next offset (`field_offset + i * 8`).
    ///
    /// Each sub-pattern that requires a runtime comparison
    /// (`PLit`, nested `PCon`, nested `PTuple`/`PList`) emits
    /// a check block that either falls through to the next
    /// sub-pattern on match or branches to `next_check` on
    /// failure. `PVar` bindings and `PWildcard` skips are
    /// emitted inline without branching. `PCon` sub-patterns
    /// trigger recursive calls that handle the inner
    /// constructor's own sub-patterns.
    ///
    /// Variable bindings from `PVar` sub-patterns are added
    /// to `arm_map`.
    // One parameter per piece of the match being compiled (target
    // value, pattern, success/failure labels, field offset, ...);
    // grouping them into a struct would add a type whose only purpose
    // is to be destructured immediately at the single call site.
    #[allow(clippy::too_many_arguments)]
    fn gen_sub_pattern_checks(
        &mut self,
        func: &mut IrFunction,
        target_val: IrValue,
        pats: &[Pattern],
        type_checker: &TypeChecker,
        next_check: String,
        arm_map: &mut HashMap<String, String>,
        field_offset: i64,
    ) {
        let i64_ty = TypeId::TCon("I64".to_string(), vec![]);

        for (field_idx, arg_pat) in pats.iter().enumerate() {
            let offset = field_offset + (field_idx as i64) * 8;
            let field_local = self.new_local();
            self.emit_to_func(
                func,
                IrInst::LoadOffset {
                    dest: IrValue::Local(field_local.clone()),
                    ptr: target_val.clone(),
                    offset,
                },
            );

            match arg_pat {
                Pattern::PVar(ident) => {
                    let arg_alloca = self.new_alloca(&ident.name);
                    func.locals.push((ident.name.clone(), i64_ty.clone()));
                    self.emit_to_func(
                        func,
                        IrInst::Alloca {
                            dest: IrValue::Local(arg_alloca.clone()),
                            ty: i64_ty.clone(),
                        },
                    );
                    self.emit_to_func(
                        func,
                        IrInst::Store {
                            ptr: IrValue::Local(arg_alloca.clone()),
                            value: IrValue::Local(field_local),
                        },
                    );
                    arm_map.insert(ident.name.clone(), arg_alloca);
                }
                Pattern::PWildcard => {}
                Pattern::PLit(lit) => {
                    let lit_val = self.gen_literal(lit);
                    let cmp_dest = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::Eq {
                            dest: IrValue::Local(cmp_dest.clone()),
                            lhs: IrValue::Local(field_local.clone()),
                            rhs: lit_val,
                        },
                    );
                    let cont = self.new_block_label();
                    self.emit_to_func(
                        func,
                        IrInst::CondBr {
                            cond: IrValue::Local(cmp_dest),
                            then_target: cont.clone(),
                            else_target: next_check.clone(),
                        },
                    );
                    func.blocks.push(IrBlock {
                        label: cont.clone(),
                        insts: Vec::new(),
                    });
                    self.current_block = Some(cont);
                }
                Pattern::PCon(ident, nested_args) => {
                    match find_constructor(type_checker, &ident.name) {
                        Some((tag, _arity)) => {
                            let inner_tag_local = self.new_local();
                            self.emit_to_func(
                                func,
                                IrInst::LoadOffset {
                                    dest: IrValue::Local(inner_tag_local.clone()),
                                    ptr: IrValue::Local(field_local.clone()),
                                    offset: 0,
                                },
                            );
                            let cmp_dest = self.new_local();
                            self.emit_to_func(
                                func,
                                IrInst::Eq {
                                    dest: IrValue::Local(cmp_dest.clone()),
                                    lhs: IrValue::Local(inner_tag_local),
                                    rhs: IrValue::Const(IrConst::Int(tag, i64_ty.clone())),
                                },
                            );
                            let cont = self.new_block_label();
                            self.emit_to_func(
                                func,
                                IrInst::CondBr {
                                    cond: IrValue::Local(cmp_dest),
                                    then_target: cont.clone(),
                                    else_target: next_check.clone(),
                                },
                            );
                            func.blocks.push(IrBlock {
                                label: cont.clone(),
                                insts: Vec::new(),
                            });
                            self.current_block = Some(cont);
                            self.gen_sub_pattern_checks(
                                func,
                                IrValue::Local(field_local),
                                nested_args,
                                type_checker,
                                next_check.clone(),
                                arm_map,
                                8,
                            );
                        }
                        None => {
                            // Undefined constructor: skip comparison
                            // (sema already reported the error).
                            self.gen_sub_pattern_checks(
                                func,
                                IrValue::Local(field_local),
                                nested_args,
                                type_checker,
                                next_check.clone(),
                                arm_map,
                                8,
                            );
                        }
                    }
                }
                Pattern::PConNamed(ident, named_args) => {
                    let positional_args: Vec<Pattern> = if let Some(field_names) = constructor_field_names(type_checker, &ident.name) {
                        field_names.iter().map(|fnm| {
                            named_args.iter().find(|(n, _)| &n.name == fnm)
                                .map(|(_, p)| p.clone())
                                .unwrap_or(Pattern::PWildcard)
                        }).collect()
                    } else {
                        named_args.iter().map(|(_, p)| p.clone()).collect()
                    };
                    match find_constructor(type_checker, &ident.name) {
                        Some((tag, _arity)) => {
                            let inner_tag_local = self.new_local();
                            self.emit_to_func(
                                func,
                                IrInst::LoadOffset {
                                    dest: IrValue::Local(inner_tag_local.clone()),
                                    ptr: IrValue::Local(field_local.clone()),
                                    offset: 0,
                                },
                            );
                            let cmp_dest = self.new_local();
                            self.emit_to_func(
                                func,
                                IrInst::Eq {
                                    dest: IrValue::Local(cmp_dest.clone()),
                                    lhs: IrValue::Local(inner_tag_local),
                                    rhs: IrValue::Const(IrConst::Int(tag, i64_ty.clone())),
                                },
                            );
                            let cont = self.new_block_label();
                            self.emit_to_func(
                                func,
                                IrInst::CondBr {
                                    cond: IrValue::Local(cmp_dest),
                                    then_target: cont.clone(),
                                    else_target: next_check.clone(),
                                },
                            );
                            func.blocks.push(IrBlock {
                                label: cont.clone(),
                                insts: Vec::new(),
                            });
                            self.current_block = Some(cont);
                            self.gen_sub_pattern_checks(
                                func,
                                IrValue::Local(field_local),
                                &positional_args,
                                type_checker,
                                next_check.clone(),
                                arm_map,
                                8,
                            );
                        }
                        None => {
                            self.gen_sub_pattern_checks(
                                func,
                                IrValue::Local(field_local),
                                &positional_args,
                                type_checker,
                                next_check.clone(),
                                arm_map,
                                8,
                            );
                        }
                    }
                }
                Pattern::PTuple(pats) | Pattern::PList(pats) => {
                    self.gen_sub_pattern_checks(
                        func,
                        IrValue::Local(field_local),
                        pats,
                        type_checker,
                        next_check.clone(),
                        arm_map,
                        0,
                    );
                    return;
                }
            }
        }
    }

    /// Compile a lambda expression as a named IR function in the
    /// module so it can be passed as a first-class value or called
    /// directly. Parameters are always `I64`; non-`PVar` patterns
    /// are not yet supported for lambda parameters. Free variables
    /// captured from the enclosing scope are not yet supported
    /// (a known limitation).
    /// Lower a call to one of Axiom's freestanding primitives (see
    /// `axiom_sema::PRIMITIVES`) to the IR instruction that
    /// implements it, returning `None` if `name` is not a primitive.
    ///
    /// An arity mismatch also returns `None` rather than emitting
    /// something wrong: semantic analysis has already reported the
    /// mismatch against the primitive's declared type, so falling
    /// through to the generic call path keeps the "one diagnostic,
    /// no invalid IR" contract instead of inventing a second failure
    /// mode further down the pipeline.
    fn gen_primitive(
        &mut self,
        func: &mut IrFunction,
        name: &str,
        args: &[IrValue],
        dest: &str,
    ) -> Option<IrValue> {
        let dest_val = IrValue::Local(dest.to_string());
        let inst = match (name, args.len()) {
            // `(__syscallN num a1 .. aN)`: the first argument is
            // always the syscall number.
            (
                "__syscall0" | "__syscall1" | "__syscall2" | "__syscall3" | "__syscall4"
                | "__syscall5" | "__syscall6",
                n,
            ) if n >= 1 => {
                let expected = name
                    .strip_prefix("__syscall")
                    .and_then(|d| d.parse::<usize>().ok())
                    .map(|d| d + 1)?;
                if n != expected {
                    return None;
                }
                IrInst::Syscall {
                    dest: dest_val.clone(),
                    num: args[0].clone(),
                    args: args[1..].to_vec(),
                }
            }
            ("__load8", 2) => IrInst::LoadIdx {
                dest: dest_val.clone(),
                ptr: args[0].clone(),
                index: args[1].clone(),
            },
            ("__store8", 3) => IrInst::StoreIdx {
                ptr: args[0].clone(),
                index: args[1].clone(),
                value: args[2].clone(),
            },
            ("__load64", 2) => IrInst::LoadWordIdx {
                dest: dest_val.clone(),
                ptr: args[0].clone(),
                index: args[1].clone(),
            },
            ("__store64", 3) => IrInst::StoreWordIdx {
                ptr: args[0].clone(),
                index: args[1].clone(),
                value: args[2].clone(),
            },
            ("__alloc", 1) => {
                self.current_fn_has_raw = true;
                IrInst::HeapAlloc {
                    dest: dest_val.clone(),
                    size: args[0].clone(),
                }
            },
            ("__addr", 1) => IrInst::AddrOf {
                dest: dest_val.clone(),
                value: args[0].clone(),
            },
            ("__axiom_arena_mark", 0) => IrInst::ArenaMark {
                dest: dest_val.clone(),
            },
            ("__axiom_arena_reset", 1) => IrInst::ArenaReset {
                ptr: args[0].clone(),
            },
            _ => return None,
        };
        // The store-shaped primitives have no result; they still
        // evaluate to something, and `0` keeps them usable in
        // sequencing position (`{ (__store8 p i c) ... }`) exactly
        // like their `Int`-returning declared type says.
        let is_store = matches!(inst, IrInst::StoreIdx { .. } | IrInst::StoreWordIdx { .. } | IrInst::ArenaReset { .. });
        self.emit_to_func(func, inst);
        if is_store {
            Some(IrValue::Const(IrConst::Int(
                0,
                TypeId::TCon("I64".to_string(), vec![]),
            )))
        } else {
            Some(dest_val)
        }
    }

    fn gen_lambda(
        &mut self,
        params: &[Pattern],
        body: &Expr,
        type_checker: &mut TypeChecker,
    ) -> (IrValue, Vec<String>) {
        self.lambda_counter += 1;
        let lambda_name = format!("_lambda_{}", self.lambda_counter);

        let free_vars = free_variables(body, params);

        let mut lambda_params: Vec<(String, TypeId)> = Vec::new();
        lambda_params.push(("_closure".to_string(), TypeId::TCon("I64".to_string(), vec![])));
        for p in params {
            if let Pattern::PVar(ident) = p {
                lambda_params.push((ident.name.clone(), TypeId::TCon("I64".to_string(), vec![])));
            }
        }

        let lambda_return = TypeId::TCon("I64".to_string(), vec![]);

        let mut lambda_func = IrFunction {
            name: lambda_name.clone(),
            params: lambda_params.clone(),
            return_type: lambda_return,
            blocks: Vec::new(),
            locals: Vec::new(),
        };

        let entry_label = self.new_block_label();
        self.current_block = Some(entry_label.clone());
        let saved_entry = self.entry_block.clone();
        self.entry_block = Some(entry_label.clone());
        lambda_func.blocks.push(IrBlock {
            label: entry_label.clone(),
            insts: Vec::new(),
        });

        let mut lambda_alloca_map: HashMap<String, String> = HashMap::new();
        for (pname, pty) in &lambda_params {
            let alloca_name = self.new_alloca(pname);
            lambda_func.locals.push((pname.clone(), pty.clone()));
            self.emit_to_func(
                &mut lambda_func,
                IrInst::Alloca {
                    dest: IrValue::Local(alloca_name.clone()),
                    ty: pty.clone(),
                },
            );
            self.emit_to_func(
                &mut lambda_func,
                IrInst::Store {
                    ptr: IrValue::Local(alloca_name.clone()),
                    value: IrValue::Local(pname.clone()),
                },
            );
            lambda_alloca_map.insert(pname.clone(), alloca_name);
        }

        for (i, fv) in free_vars.iter().enumerate() {
                let ld = self.new_local();
                self.emit_to_func(
                    &mut lambda_func,
                    IrInst::LoadOffset {
                        dest: IrValue::Local(ld.clone()),
                        ptr: IrValue::Local("_closure".to_string()),
                        offset: 8 * (1 + i as i64),
                    },
                );
                let fv_alloca = self.new_alloca(fv);
                lambda_func.locals.push((fv.clone(), TypeId::TCon("I64".to_string(), vec![])));
                self.emit_to_func(
                    &mut lambda_func,
                    IrInst::Alloca {
                        dest: IrValue::Local(fv_alloca.clone()),
                        ty: TypeId::TCon("I64".to_string(), vec![]),
                    },
                );
                self.emit_to_func(
                    &mut lambda_func,
                    IrInst::Store {
                        ptr: IrValue::Local(fv_alloca.clone()),
                        value: IrValue::Local(ld),
                    },
                );
                lambda_alloca_map.insert(fv.clone(), fv_alloca);
        }

        let body_val = self.gen_expr_to_func_with_allocas(
            &mut lambda_func,
            body,
            &mut lambda_alloca_map,
            type_checker,
            None,
        );
        self.emit_to_func(
            &mut lambda_func,
            IrInst::Ret {
                value: Some(body_val),
            },
        );

        self.module.functions.push(lambda_func);

        self.entry_block = saved_entry;

        (IrValue::Global(lambda_name), free_vars)
    }

    fn gen_expr_to_func_with_allocas(
        &mut self,
        func: &mut IrFunction,
        expr: &Expr,
        alloca_map: &mut HashMap<String, String>,
        type_checker: &mut TypeChecker,
        tail_ctx: Option<&TailContext>,
    ) -> IrValue {
        match expr {
            Expr::ELit(lit, _) => self.gen_literal(lit),
        Expr::EVar(ident) | Expr::EQualified(_, ident) => {
                // A *bare* reference to a nullary constructor (`Nothing`,
                // `Nil`, ...) constructs its (fieldless) boxed value
                // directly. A non-nullary constructor referenced bare
                // (not applied to any arguments) falls through to the
                // ordinary variable-lookup path below, same as before -
                // using a data constructor as a first-class function
                // value isn't supported by this generator either way, and
                // this at least doesn't regress that pre-existing gap.
                if let Some((tag, arity)) = find_constructor(type_checker, &ident.name) {
                    if arity == 0 {
                        return self.gen_construct(func, tag, Vec::new());
                    }
                }
                if let Some(alloca_name) = alloca_map.get(&ident.name) {
                    let dest = self.new_local();
                    let _ty = func
                        .locals
                        .iter()
                        .find(|(n, _)| n == &ident.name)
                        .map(|(_, t)| t.clone())
                        .unwrap_or(TypeId::TCon("I64".to_string(), vec![]));
                    self.emit_to_func(
                        func,
                        IrInst::Load {
                            dest: IrValue::Local(dest.clone()),
                            ptr: IrValue::Local(alloca_name.clone()),
                        },
                    );
                    if self.tag_alloca_names.contains(alloca_name) {
                        IrValue::Tag(dest)
                    } else {
                        IrValue::Local(dest)
                    }
                } else if self.nullary_fns.contains(&ident.name) {
                    let dest = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::Call {
                            dest: IrValue::Local(dest.clone()),
                            func: ident.name.clone(),
                            args: vec![IrValue::Const(IrConst::Int(
                                0,
                                TypeId::TCon("I64".to_string(), vec![]),
                            ))],
                        },
                    );
                    IrValue::Local(dest)
                } else if self.all_fns.contains(&ident.name) {
                    let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                    let closure_addr = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::HeapAlloc {
                            dest: IrValue::Local(closure_addr.clone()),
                            size: IrValue::Const(IrConst::Int(8, i64_ty.clone())),
                        },
                    );
                    let fn_addr = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::AddrOf {
                            dest: IrValue::Local(fn_addr.clone()),
                            value: IrValue::Global(ident.name.clone()),
                        },
                    );
                    self.emit_to_func(
                        func,
                        IrInst::StoreOffset {
                            ptr: IrValue::Local(closure_addr.clone()),
                            offset: 0,
                            value: IrValue::Local(fn_addr),
                        },
                    );
                    IrValue::Local(closure_addr)
                } else {
                    IrValue::Local(ident.name.clone())
                }
            }
            Expr::EInfix(left, op, right) => {
                let lhs = self.gen_expr_to_func_with_allocas(func, left, alloca_map, type_checker, None);
                let rhs = self.gen_expr_to_func_with_allocas(func, right, alloca_map, type_checker, None);
                let dest = self.new_local();

                let inst = match op.as_str() {
                    "+" => IrInst::Add {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "-" => IrInst::Sub {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "*" => IrInst::Mul {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "/" => IrInst::Div {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "%" => IrInst::Mod {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "==" => IrInst::Eq {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "!=" => IrInst::Neq {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "<" => IrInst::Lt {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    ">" => IrInst::Gt {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "<=" => IrInst::Le {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    ">=" => IrInst::Ge {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "&&" => IrInst::And {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "||" => IrInst::Or {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    _ => IrInst::Add {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                };

                self.emit_to_func(func, inst);
                IrValue::Local(dest)
            }
            Expr::EApp(_func_expr, _arg_expr) => {
                let mut arg_exprs: Vec<&Expr> = Vec::new();
                let mut current = expr;
                while let Expr::EApp(inner_func, inner_arg) = current {
                    arg_exprs.push(inner_arg.as_ref());
                    current = inner_func.as_ref();
                }
                arg_exprs.reverse();

                let is_self_tail = tail_ctx.and_then(|tc| {
                    if let Expr::EVar(ident) | Expr::EQualified(_, ident) = current {
                        if ident.name == tc.func_name {
                            Some(tc)
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                });

                let arena_mark: Option<String> = if is_self_tail.is_some() && !self.current_fn_has_raw {
                    let mark = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::ArenaMark {
                            dest: IrValue::Local(mark.clone()),
                        },
                    );
                    Some(mark)
                } else {
                    None
                };

                let mut all_args: Vec<IrValue> = Vec::new();
                for arg in &arg_exprs {
                    all_args.push(self.gen_expr_to_func_with_allocas(
                        func,
                        arg,
                        alloca_map,
                        type_checker,
                        None,
                    ));
                }

                // `(Just 42)`/`(Cons h t)`-style constructor application:
                // build the real heap-boxed value instead of falling
                // through to the generic `Call` path below, which would
                // otherwise emit a call to a function literally named
                // after the constructor (e.g. `@Just`) that is never
                // declared anywhere - invalid LLVM IR that fails at the
                // `llc`/`cc` stage instead of at a compiler diagnostic.
                // Only handled when the argument count matches the
                // constructor's declared arity exactly; a mismatch here
                // means semantic analysis already reported
                // `ConstructorArity` (see `axiom-sema`), so falling
                // through to the old (still-broken) `Call` path for that
                // case is no worse than before and avoids generating a
                // *third*, different kind of wrong code for an
                // already-diagnosed program.
                if let Expr::EVar(ident) | Expr::EQualified(_, ident) = current {
                    if let Some((tag, arity)) = find_constructor(type_checker, &ident.name) {
                        if arity == all_args.len() {
                            return self.gen_construct(func, tag, all_args);
                        }
                    }
                    // Struct construction: `(Point 1 2)` where `Point`
                    // is a known struct name. Allocate space and store
                    // each field at the appropriate offset (no tag word).
                    if let Some(si) = type_checker.structs.iter().find(|s| s.name == ident.name) {
                        if si.fields.len() != all_args.len() {
                            return IrValue::Const(IrConst::Int(
                                0,
                                TypeId::TCon("I64".to_string(), vec![]),
                            ));
                        }
                        let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                        let struct_size = (si.fields.len() * 8) as i64;
                        let ptr_local = self.new_local();
                        self.emit_to_func(
                            func,
                            IrInst::HeapAlloc {
                                dest: IrValue::Local(ptr_local.clone()),
                                size: IrValue::Const(IrConst::Int(struct_size, i64_ty.clone())),
                            },
                        );
                        for (i, arg) in all_args.into_iter().enumerate() {
                            self.emit_to_func(
                                func,
                                IrInst::StoreOffset {
                                    ptr: IrValue::Local(ptr_local.clone()),
                                    offset: (i * 8) as i64,
                    value: arg,
                                },
                            );
                        }
                        return IrValue::Local(ptr_local);
                    }
                }

                if let Expr::ELam(params, body) = current {
                    let saved = self.current_block.clone();
                    let saved_entry = self.entry_block.clone();
                    let (lambda_val, _free_vars) = self.gen_lambda(params, body, type_checker);
                    self.current_block = saved;
                    self.entry_block = saved_entry;
                    let lambda_name;
                    if let IrValue::Global(name) = lambda_val {
                        lambda_name = name;
                    } else {
                        lambda_name = "unknown".to_string();
                    }

                    let dest = self.new_local();
                    let mut lambda_args = all_args;
                    lambda_args.insert(
                        0,
                        IrValue::Const(IrConst::Int(0, TypeId::TCon("I64".to_string(), vec![]))),
                    );
                    let boxed_lambda_args: Vec<IrValue> = lambda_args
                        .iter()
                        .map(|a| self.box_if_tag(func, a))
                        .collect();
                    self.emit_to_func(
                        func,
                        IrInst::Call {
                            dest: IrValue::Local(dest.clone()),
                            func: lambda_name,
                            args: boxed_lambda_args,
                        },
                    );
                    return IrValue::Local(dest);
                }

                let func_name;
                if let Expr::EVar(ident) | Expr::EQualified(_, ident) = current {
                    func_name = ident.name.clone();
                } else {
                    func_name = "unknown".to_string();
                }

                let dest = self.new_local();

                if all_args.len() == 2 {
                    let lhs = all_args[0].clone();
                    let rhs = all_args[1].clone();
                    let inst = match func_name.as_str() {
                        "+" => Some(IrInst::Add {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "-" => Some(IrInst::Sub {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "*" => Some(IrInst::Mul {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "/" => Some(IrInst::Div {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "%" => Some(IrInst::Mod {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "==" => Some(IrInst::Eq {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "!=" => Some(IrInst::Neq {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "<" => Some(IrInst::Lt {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        ">" => Some(IrInst::Gt {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "<=" => Some(IrInst::Le {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        ">=" => Some(IrInst::Ge {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "&&" => Some(IrInst::And {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "||" => Some(IrInst::Or {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        _ => None,
                    };
                    if let Some(inst) = inst {
                        self.emit_to_func(func, inst);
                        return IrValue::Local(dest);
                    }
                }

                // Freestanding primitives lower to dedicated
                // instructions, not to a call: there is no function
                // named `__syscall3` anywhere to call, and emitting
                // one would produce LLVM IR that fails at link time
                // instead of at a diagnostic.
                if let Some(val) = self.gen_primitive(func, &func_name, &all_args, &dest) {
                    return val;
                }

                if let (Some(tc), Some(mark)) = (is_self_tail, &arena_mark) {
                    let arena_end = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::ArenaMark {
                            dest: IrValue::Local(arena_end.clone()),
                        },
                    );
                    self.emit_to_func(
                        func,
                        IrInst::ArenaReset {
                            ptr: IrValue::Local(mark.clone()),
                        },
                    );
                    let mut compacted_args: Vec<IrValue> = Vec::new();
                    let mut compact_results: Vec<IrValue> = Vec::new();
                    for _ in &all_args {
                        let res = self.new_local();
                        compact_results.push(IrValue::Local(res));
                    }
                    self.emit_to_func(
                        func,
                        IrInst::ArenaCompact {
                            mark: IrValue::Local(mark.clone()),
                            arena_end: IrValue::Local(arena_end),
                            roots: all_args.clone(),
                            results: compact_results.clone(),
                        },
                    );
                    for result in &compact_results {
                        compacted_args.push(result.clone());
                    }
                    for (i, arg_val) in compacted_args.iter().enumerate() {
                        if i < tc.param_names.len() {
                            if let Some(alloca) = alloca_map.get(&tc.param_names[i]) {
                                let store_val = self.box_if_tag(func, arg_val);
                                self.emit_to_func(
                                    func,
                                    IrInst::Store {
                                        ptr: IrValue::Local(alloca.clone()),
                                        value: store_val,
                                    },
                                );
                            }
                        }
                    }
                    self.emit_to_func(
                        func,
                        IrInst::Br {
                            target: tc.entry_label.clone(),
                        },
                    );
                    return IrValue::Const(IrConst::Int(
                        0,
                        TypeId::TCon("I64".to_string(), vec![]),
                    ));
                }

                if let Some(tc) = tail_ctx {
                    if func_name == tc.func_name {
                        for (i, arg_val) in all_args.iter().enumerate() {
                            if i < tc.param_names.len() {
                                if let Some(alloca) = alloca_map.get(&tc.param_names[i]) {
                                    let store_val = self.box_if_tag(func, arg_val);
                                    self.emit_to_func(
                                        func,
                                        IrInst::Store {
                                            ptr: IrValue::Local(alloca.clone()),
                                            value: store_val,
                                        },
                                    );
                                }
                            }
                        }
                        self.emit_to_func(
                            func,
                            IrInst::Br {
                                target: tc.entry_label.clone(),
                            },
                        );
                        return IrValue::Const(IrConst::Int(
                            0,
                            TypeId::TCon("I64".to_string(), vec![]),
                        ));
                    }
                }

                if let Expr::EVar(ident) | Expr::EQualified(_, ident) = current {
                    if let Some(alloca_name) = alloca_map.get(&ident.name) {
                        let closure_val = self.new_local();
                        self.emit_to_func(
                            func,
                            IrInst::Load {
                                dest: IrValue::Local(closure_val.clone()),
                                ptr: IrValue::Local(alloca_name.clone()),
                            },
                        );
                        let fn_ptr = self.new_local();
                        self.emit_to_func(
                            func,
                            IrInst::LoadOffset {
                                dest: IrValue::Local(fn_ptr.clone()),
                                ptr: IrValue::Local(closure_val.clone()),
                                offset: 0,
                            },
                        );
                        let mut indirect_args = all_args;
                        indirect_args.insert(0, IrValue::Local(closure_val));
                        let boxed_args: Vec<IrValue> = indirect_args
                            .iter()
                            .map(|a| self.box_if_tag(func, a))
                            .collect();
                        self.emit_to_func(
                            func,
                            IrInst::CallIndirect {
                                dest: IrValue::Local(dest.clone()),
                                ptr: IrValue::Local(fn_ptr),
                                args: boxed_args,
                            },
                        );
                        return IrValue::Local(dest);
                    }
                }

                let mut call_args = all_args;
                if self.all_fns.contains(&func_name) || func_name.starts_with("_lambda_") {
                    call_args.insert(
                        0,
                        IrValue::Const(IrConst::Int(0, TypeId::TCon("I64".to_string(), vec![]))),
                    );
                }
                let boxed_args: Vec<IrValue> = call_args
                    .iter()
                    .map(|a| self.box_if_tag(func, a))
                    .collect();
                self.emit_to_func(
                    func,
                    IrInst::Call {
                        dest: IrValue::Local(dest.clone()),
                        func: func_name,
                        args: boxed_args,
                    },
                );

                IrValue::Local(dest)
            }
            Expr::EIf(cond, then_expr, else_expr) => {
                let cond_val =
                    self.gen_expr_to_func_with_allocas(func, cond, alloca_map, type_checker, None);
                let then_label = self.new_block_label();
                let else_label = self.new_block_label();
                let merge_label = self.new_block_label();
                let result_alloca = self.new_local();

                self.emit_to_func(
                    func,
                    IrInst::Alloca {
                        dest: IrValue::Local(result_alloca.clone()),
                        ty: TypeId::TCon("I64".to_string(), vec![]),
                    },
                );

                self.emit_to_func(
                    func,
                    IrInst::CondBr {
                        cond: cond_val,
                        then_target: then_label.clone(),
                        else_target: else_label.clone(),
                    },
                );

                func.blocks.push(IrBlock {
                    label: then_label.clone(),
                    insts: Vec::new(),
                });
                self.current_block = Some(then_label.clone());
                let then_val =
                    self.gen_expr_to_func_with_allocas(func, then_expr, alloca_map, type_checker, tail_ctx);
                self.emit_to_func(
                    func,
                    IrInst::Store {
                        ptr: IrValue::Local(result_alloca.clone()),
                        value: then_val,
                    },
                );
                self.emit_to_func(
                    func,
                    IrInst::Br {
                        target: merge_label.clone(),
                    },
                );

                func.blocks.push(IrBlock {
                    label: else_label.clone(),
                    insts: Vec::new(),
                });
                self.current_block = Some(else_label.clone());
                let else_val =
                    self.gen_expr_to_func_with_allocas(func, else_expr, alloca_map, type_checker, tail_ctx);
                self.emit_to_func(
                    func,
                    IrInst::Store {
                        ptr: IrValue::Local(result_alloca.clone()),
                        value: else_val,
                    },
                );
                self.emit_to_func(
                    func,
                    IrInst::Br {
                        target: merge_label.clone(),
                    },
                );

                func.blocks.push(IrBlock {
                    label: merge_label.clone(),
                    insts: Vec::new(),
                });
                self.current_block = Some(merge_label.clone());

                let load_dest = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::Load {
                        dest: IrValue::Local(load_dest.clone()),
                        ptr: IrValue::Local(result_alloca),
                    },
                );
                IrValue::Local(load_dest)
            }
            Expr::ELet(bindings, body) => {
                for (pat, init) in bindings {
                    if let Pattern::PVar(ident) = pat {
                        let value = self.gen_expr_to_func_with_allocas(
                            func,
                            init,
                            alloca_map,
                            type_checker,
                            None,
                        );
                        let is_tag = matches!(&value, IrValue::Const(IrConst::Int(tag, _)) if self.nullary_tags.contains(tag))
                            || matches!(&value, IrValue::Tag(_));
                        let alloca_name = self.new_alloca(&ident.name);
                        func.locals
                            .push((ident.name.clone(), TypeId::TCon("I64".to_string(), vec![])));
                        self.emit_to_func(
                            func,
                            IrInst::Alloca {
                                dest: IrValue::Local(alloca_name.clone()),
                                ty: TypeId::TCon("I64".to_string(), vec![]),
                            },
                        );
                        self.emit_to_func(
                            func,
                            IrInst::Store {
                                ptr: IrValue::Local(alloca_name.clone()),
                                value,
                            },
                        );
                        alloca_map.insert(ident.name.clone(), alloca_name.clone());
                        if is_tag {
                            self.tag_alloca_names.insert(alloca_name);
                        }
                    }
                }
                self.gen_expr_to_func_with_allocas(func, body, alloca_map, type_checker, None)
            }
            Expr::EMatch(target, arms) => {
                let target_val =
                    self.gen_expr_to_func_with_allocas(func, target, alloca_map, type_checker, None);
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                let result_alloca = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::Alloca {
                        dest: IrValue::Local(result_alloca.clone()),
                        ty: i64_ty.clone(),
                    },
                );
                self.emit_to_func(
                    func,
                    IrInst::Store {
                        ptr: IrValue::Local(result_alloca.clone()),
                        value: IrValue::Const(IrConst::Int(0, i64_ty.clone())),
                    },
                );

                // Load the scrutinee's tag *once*, up front, rather than
                // re-deriving "is this a constructor value" per arm - every
                // `PCon` arm below compares against this same loaded tag,
                // and every arm agrees on what a given constructor's tag is
                // because both this and construction (`gen_construct`) go
                // through the one shared `find_constructor` lookup. Only
                // emitted when at least one arm actually needs it: a `match`
                // over a plain `Int`/`Bool` scrutinee with only
                // `PLit`/`PVar`/`PWildcard` arms has nothing to unbox.
                let needs_tag = arms.iter().any(|(pat, _)| {
                    matches!(pat, Pattern::PCon(ident, ..) | Pattern::PConNamed(ident, ..) if find_constructor(type_checker, &ident.name).is_some())
                });
                let tag_val = if needs_tag {
                    if let IrValue::Tag(name) = &target_val {
                        Some(IrValue::Tag(name.clone()))
                    } else if let IrValue::Const(IrConst::Int(t, _)) = &target_val {
                        if self.nullary_tags.contains(t) {
                            Some(target_val.clone())
                        } else {
                            None
                        }
                    } else {
                        let tag_local = self.new_local();
                        self.emit_to_func(
                            func,
                            IrInst::LoadOffset {
                                dest: IrValue::Local(tag_local.clone()),
                                ptr: target_val.clone(),
                                offset: 0,
                            },
                        );
                        Some(IrValue::Local(tag_local))
                    }
                } else {
                    None
                };

                let merge_label = self.new_block_label();
                let mut arm_labels: Vec<String> = Vec::new();
                let mut check_labels: Vec<String> = Vec::new();
                for _ in arms {
                    arm_labels.push(self.new_block_label());
                    check_labels.push(self.new_block_label());
                }

                if !check_labels.is_empty() {
                    self.emit_to_func(
                        func,
                        IrInst::Br {
                            target: check_labels[0].clone(),
                        },
                    );
                }

                for (i, (pat, body)) in arms.iter().enumerate() {
                    let arm_label = &arm_labels[i];
                    let check_label = &check_labels[i];
                    let mut arm_map = alloca_map.clone();

                    let next_check = if i < arms.len() - 1 {
                        check_labels[i + 1].clone()
                    } else {
                        merge_label.clone()
                    };

                    // Emit an unconditional-match check block: no
                    // comparison, straight through to the arm. Shared by
                    // `PWildcard`, `PVar`, and any constructor name sema
                    // already flagged as undefined (see
                    // `SemError::UndefinedConstructor`) - codegen doesn't
                    // re-diagnose that, it just avoids compiling the
                    // already-reported-invalid program into something
                    // that miscompares against a tag that doesn't exist.
                    let unconditional_arm = |gen: &mut Self, func: &mut IrFunction| {
                        func.blocks.push(IrBlock {
                            label: check_label.clone(),
                            insts: Vec::new(),
                        });
                        gen.current_block = Some(check_label.clone());
                        gen.emit_to_func(
                            func,
                            IrInst::Br {
                                target: arm_label.clone(),
                            },
                        );
                        func.blocks.push(IrBlock {
                            label: arm_label.clone(),
                            insts: Vec::new(),
                        });
                        gen.current_block = Some(arm_label.clone());
                    };

                    match pat {
                        Pattern::PCon(ident, args) => {
                            match find_constructor(type_checker, &ident.name) {
                                Some((tag, _arity)) => {
                                    func.blocks.push(IrBlock {
                                        label: check_label.clone(),
                                        insts: Vec::new(),
                                    });
                                    self.current_block = Some(check_label.clone());

                                    let cmp_dest = self.new_local();
                                    self.emit_to_func(
                                        func,
                                        IrInst::Eq {
                                            dest: IrValue::Local(cmp_dest.clone()),
                                            lhs: tag_val.clone().expect(
                                                "needs_tag scan above must have found this arm",
                                            ),
                                            rhs: IrValue::Const(IrConst::Int(tag, i64_ty.clone())),
                                        },
                                    );
                                    self.emit_to_func(
                                        func,
                                        IrInst::CondBr {
                                            cond: IrValue::Local(cmp_dest),
                                            then_target: arm_label.clone(),
                                            else_target: next_check,
                                        },
                                    );

                                    func.blocks.push(IrBlock {
                                        label: arm_label.clone(),
                                        insts: Vec::new(),
                                    });
                                    self.current_block = Some(arm_label.clone());

                                    // Non-`PVar` sub-patterns (nested constructors,
                                    // literals, tuples, lists) are handled by
                                    // `gen_sub_pattern_checks` which implements
                                    // recursive matching.
                                    self.gen_sub_pattern_checks(
                                        func,
                                        target_val.clone(),
                                        args,
                                        type_checker,
                                        merge_label.clone(),
                                        &mut arm_map,
                                        8,
                                    );
                                }
                                None => unconditional_arm(self, func),
                            }
                        }
                        Pattern::PVar(ident) => {
                            unconditional_arm(self, func);

                            let var_alloca = self.new_alloca(&ident.name);
                            func.locals.push((ident.name.clone(), i64_ty.clone()));
                            self.emit_to_func(
                                func,
                                IrInst::Alloca {
                                    dest: IrValue::Local(var_alloca.clone()),
                                    ty: i64_ty.clone(),
                                },
                            );
                            self.emit_to_func(
                                func,
                                IrInst::Store {
                                    ptr: IrValue::Local(var_alloca.clone()),
                                    value: target_val.clone(),
                                },
                            );
                            arm_map.insert(ident.name.clone(), var_alloca);
                        }
                        Pattern::PConNamed(ident, named_args) => {
                            let positional_args: Vec<Pattern> = if let Some(field_names) = constructor_field_names(type_checker, &ident.name) {
                                field_names.iter().map(|fnm| {
                                    named_args.iter().find(|(n, _)| &n.name == fnm)
                                        .map(|(_, p)| p.clone())
                                        .unwrap_or(Pattern::PWildcard)
                                }).collect()
                            } else {
                                named_args.iter().map(|(_, p)| p.clone()).collect()
                            };
                            match find_constructor(type_checker, &ident.name) {
                                Some((tag, _arity)) => {
                                    func.blocks.push(IrBlock {
                                        label: check_label.clone(),
                                        insts: Vec::new(),
                                    });
                                    self.current_block = Some(check_label.clone());
                                    let cmp_dest = self.new_local();
                                    self.emit_to_func(
                                        func,
                                        IrInst::Eq {
                                            dest: IrValue::Local(cmp_dest.clone()),
                                            lhs: tag_val.clone().expect("needs_tag scan above must have found this arm"),
                                            rhs: IrValue::Const(IrConst::Int(tag, i64_ty.clone())),
                                        },
                                    );
                                    self.emit_to_func(
                                        func,
                                        IrInst::CondBr {
                                            cond: IrValue::Local(cmp_dest),
                                            then_target: arm_label.clone(),
                                            else_target: next_check,
                                        },
                                    );
                                    func.blocks.push(IrBlock {
                                        label: arm_label.clone(),
                                        insts: Vec::new(),
                                    });
                                    self.current_block = Some(arm_label.clone());
                                    self.gen_sub_pattern_checks(
                                        func,
                                        target_val.clone(),
                                        &positional_args,
                                        type_checker,
                                        merge_label.clone(),
                                        &mut arm_map,
                                        8,
                                    );
                                }
                                None => unconditional_arm(self, func),
                            }
                        }
                        Pattern::PWildcard => unconditional_arm(self, func),
                        Pattern::PLit(lit) => {
                            func.blocks.push(IrBlock {
                                label: check_label.clone(),
                                insts: Vec::new(),
                            });
                            self.current_block = Some(check_label.clone());

                            let lit_val = self.gen_literal(lit);
                            let cmp_dest = self.new_local();
                            self.emit_to_func(
                                func,
                                IrInst::Eq {
                                    dest: IrValue::Local(cmp_dest.clone()),
                                    lhs: target_val.clone(),
                                    rhs: lit_val,
                                },
                            );
                            self.emit_to_func(
                                func,
                                IrInst::CondBr {
                                    cond: IrValue::Local(cmp_dest),
                                    then_target: arm_label.clone(),
                                    else_target: next_check,
                                },
                            );

                            func.blocks.push(IrBlock {
                                label: arm_label.clone(),
                                insts: Vec::new(),
                            });
                            self.current_block = Some(arm_label.clone());
                        }
                        Pattern::PTuple(pats) | Pattern::PList(pats) => {
                            func.blocks.push(IrBlock {
                                label: check_label.clone(),
                                insts: vec![IrInst::Br {
                                    target: arm_label.clone(),
                                }],
                            });
                            self.current_block = Some(arm_label.clone());

                            func.blocks.push(IrBlock {
                                label: arm_label.clone(),
                                insts: Vec::new(),
                            });
                            self.current_block = Some(arm_label.clone());

                            self.gen_sub_pattern_checks(
                                func,
                                target_val.clone(),
                                pats,
                                type_checker,
                                merge_label.clone(),
                                &mut arm_map,
                                0,
                            );
                        }
                    }

                    let body_val =
                        self.gen_expr_to_func_with_allocas(func, body, &mut arm_map, type_checker, tail_ctx);
                    self.emit_to_func(
                        func,
                        IrInst::Store {
                            ptr: IrValue::Local(result_alloca.clone()),
                            value: body_val,
                        },
                    );
                    self.emit_to_func(
                        func,
                        IrInst::Br {
                            target: merge_label.clone(),
                        },
                    );
                }

                let trap_label = self.new_block_label();
                func.blocks.push(IrBlock {
                    label: trap_label.clone(),
                    insts: vec![IrInst::Unreachable],
                });

                func.blocks.push(IrBlock {
                    label: merge_label.clone(),
                    insts: Vec::new(),
                });
                self.current_block = Some(merge_label.clone());

                let load_dest = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::Load {
                        dest: IrValue::Local(load_dest.clone()),
                        ptr: IrValue::Local(result_alloca),
                    },
                );
                IrValue::Local(load_dest)
            }
            Expr::EBegin(exprs) => {
                let mut last_val =
                    IrValue::Const(IrConst::Int(0, TypeId::TCon("I64".to_string(), vec![])));
                for (i, e) in exprs.iter().enumerate() {
                    let ctx = if i == exprs.len() - 1 { tail_ctx } else { None };
                    last_val =
                        self.gen_expr_to_func_with_allocas(func, e, alloca_map, type_checker, ctx);
                }
                last_val
            }
            Expr::ECast(inner, target_type) => {
                let src = self.gen_expr_to_func_with_allocas(func, inner, alloca_map, type_checker, None);
                let dest = self.new_local();
                let target_ty = self.type_to_id(target_type);

                self.emit_to_func(
                    func,
                    IrInst::Cast {
                        dest: IrValue::Local(dest.clone()),
                        src,
                        target_ty,
                    },
                );

                IrValue::Local(dest)
            }
            Expr::ESizeof(ty, _) => {
                let dest = self.new_local();
                let resolved_ty = self.type_to_id(ty);
                self.emit_to_func(
                    func,
                    IrInst::Sizeof {
                        dest: IrValue::Local(dest.clone()),
                        ty: resolved_ty,
                    },
                );
                IrValue::Local(dest)
            }
            Expr::EAlignof(ty, _) => {
                let dest = self.new_local();
                let resolved_ty = self.type_to_id(ty);
                self.emit_to_func(
                    func,
                    IrInst::Alignof {
                        dest: IrValue::Local(dest.clone()),
                        ty: resolved_ty,
                    },
                );
                IrValue::Local(dest)
            }
            Expr::EGrouped(inner) => {
                self.gen_expr_to_func_with_allocas(func, inner, alloca_map, type_checker, None)
            }
            Expr::ELam(params, body) => {
                let saved = self.current_block.clone();
                let saved_entry = self.entry_block.clone();
                let (lambda_val, free_vars) = self.gen_lambda(params, body, type_checker);
                self.current_block = saved;
                self.entry_block = saved_entry;

                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                let closure_size = 8 * (1 + free_vars.len() as i64);
                let closure_addr = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::HeapAlloc {
                        dest: IrValue::Local(closure_addr.clone()),
                        size: IrValue::Const(IrConst::Int(closure_size, i64_ty.clone())),
                    },
                );
                let fn_addr = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::AddrOf {
                        dest: IrValue::Local(fn_addr.clone()),
                        value: lambda_val,
                    },
                );
                self.emit_to_func(
                    func,
                    IrInst::StoreOffset {
                        ptr: IrValue::Local(closure_addr.clone()),
                        offset: 0,
                        value: IrValue::Local(fn_addr),
                    },
                );
                for (i, fv) in free_vars.iter().enumerate() {
                    let fv_val = if let Some(alloca_name) = alloca_map.get(fv) {
                        let ld = self.new_local();
                        self.emit_to_func(
                            func,
                            IrInst::Load {
                                dest: IrValue::Local(ld.clone()),
                                ptr: IrValue::Local(alloca_name.clone()),
                            },
                        );
                        IrValue::Local(ld)
                    } else {
                        IrValue::Local(fv.clone())
                    };
                    self.emit_to_func(
                        func,
                        IrInst::StoreOffset {
                            ptr: IrValue::Local(closure_addr.clone()),
                            offset: 8 * (1 + i as i64),
                            value: fv_val,
                        },
                    );
                }
                IrValue::Local(closure_addr)
            }
            Expr::ETuple(elements) => {
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                let tuple_size = (elements.len() * 8) as i64;
                let ptr_local = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::HeapAlloc {
                        dest: IrValue::Local(ptr_local.clone()),
                        size: IrValue::Const(IrConst::Int(tuple_size, i64_ty.clone())),
                    },
                );
                for (i, elem) in elements.iter().enumerate() {
                    let val =
                        self.gen_expr_to_func_with_allocas(func, elem, alloca_map, type_checker, None);
                    self.emit_to_func(
                        func,
                        IrInst::StoreOffset {
                            ptr: IrValue::Local(ptr_local.clone()),
                            offset: (i * 8) as i64,
                            value: val,
                        },
                    );
                }
                IrValue::Local(ptr_local)
            }
            Expr::EList(items) => {
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                let list_size = (items.len() * 8) as i64;
                let ptr_local = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::HeapAlloc {
                        dest: IrValue::Local(ptr_local.clone()),
                        size: IrValue::Const(IrConst::Int(list_size, i64_ty.clone())),
                    },
                );
                for (i, item) in items.iter().enumerate() {
                    let val =
                        self.gen_expr_to_func_with_allocas(func, item, alloca_map, type_checker, None);
                    self.emit_to_func(
                        func,
                        IrInst::StoreOffset {
                            ptr: IrValue::Local(ptr_local.clone()),
                            offset: (i * 8) as i64,
                            value: val,
                        },
                    );
                }
                IrValue::Local(ptr_local)
            }
            Expr::EHandle(body, _, handler) => {
                let _ = handler;
                self.gen_expr_to_func_with_allocas(func, body, alloca_map, type_checker, None)
            }
            Expr::EConsume(e) => {
                self.gen_expr_to_func_with_allocas(func, e, alloca_map, type_checker, None)
            }
            Expr::EField(base, field_ident) => {
                let base_val =
                    self.gen_expr_to_func_with_allocas(func, base, alloca_map, type_checker, None);
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                if let Some((_name, field_index, _field_ty)) =
                    type_checker.find_struct_field_by_name(&field_ident.name)
                {
                    let offset = (field_index * 8) as i64;
                    let result_reg = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::LoadOffset {
                            dest: IrValue::Local(result_reg.clone()),
                            ptr: base_val,
                            offset,
                        },
                    );
                    IrValue::Local(result_reg)
                } else if let Some((_dt_name, field_index, _field_ty)) =
                    type_checker.find_data_field_by_name(&field_ident.name)
                {
                    let offset = ((1 + field_index) * 8) as i64;
                    let result_reg = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::LoadOffset {
                            dest: IrValue::Local(result_reg.clone()),
                            ptr: base_val,
                            offset,
                        },
                    );
                    IrValue::Local(result_reg)
                } else {
                    IrValue::Const(IrConst::Int(0, i64_ty))
                }
            }
            Expr::ESetField(base, field_ident, value) => {
                let base_val =
                    self.gen_expr_to_func_with_allocas(func, base, alloca_map, type_checker, None);
                let value_val =
                    self.gen_expr_to_func_with_allocas(func, value, alloca_map, type_checker, None);
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                if let Some((_name, field_index, _field_ty)) =
                    type_checker.find_struct_field_by_name(&field_ident.name)
                {
                    let offset = (field_index * 8) as i64;
                    self.emit_to_func(
                        func,
                        IrInst::StoreOffset {
                            ptr: base_val,
                            offset,
                            value: value_val,
                        },
                    );
                    IrValue::Const(IrConst::Int(0, i64_ty))
                } else if let Some((_dt_name, field_index, _field_ty)) =
                    type_checker.find_data_field_by_name(&field_ident.name)
                {
                    let offset = ((1 + field_index) * 8) as i64;
                    self.emit_to_func(
                        func,
                        IrInst::StoreOffset {
                            ptr: base_val,
                            offset,
                            value: value_val,
                        },
                    );
                    IrValue::Const(IrConst::Int(0, i64_ty))
                } else {
                    IrValue::Const(IrConst::Int(0, i64_ty))
                }
            }
            Expr::EStructCon(name, args) => {
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                if let Some(si) = type_checker.structs.iter().find(|s| s.name == name.name) {
                    if si.fields.len() != args.len() {
                        return IrValue::Const(IrConst::Int(0, i64_ty));
                    }
                    let struct_size = (si.fields.len() * 8) as i64;
                    let ptr_local = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::HeapAlloc {
                            dest: IrValue::Local(ptr_local.clone()),
                            size: IrValue::Const(IrConst::Int(struct_size, i64_ty.clone())),
                        },
                    );
                    for (i, arg) in args.iter().enumerate() {
                        let val =
                            self.gen_expr_to_func_with_allocas(func, arg, alloca_map, type_checker, None);
                        self.emit_to_func(
                            func,
                            IrInst::StoreOffset {
                                ptr: IrValue::Local(ptr_local.clone()),
                                offset: (i * 8) as i64,
                                value: val,
                            },
                        );
                    }
                    IrValue::Local(ptr_local)
                } else {
                    IrValue::Const(IrConst::Int(0, i64_ty))
                }
            }
            _ => IrValue::Const(IrConst::Int(0, TypeId::TCon("I64".to_string(), vec![]))),
        }
    }

    fn gen_literal(&self, lit: &Literal) -> IrValue {
        match lit {
            Literal::LInt(n) => {
                IrValue::Const(IrConst::Int(*n, TypeId::TCon("I64".to_string(), vec![])))
            }
            Literal::LFloat(n) => {
                IrValue::Const(IrConst::Float(*n, TypeId::TCon("F64".to_string(), vec![])))
            }
            Literal::LBool(b) => IrValue::Const(IrConst::Bool(*b)),
            Literal::LChar(c) => IrValue::Const(IrConst::Int(
                *c as i64,
                TypeId::TCon("U8".to_string(), vec![]),
            )),
            Literal::LStr(s) => IrValue::Const(IrConst::Str(s.clone())),
        }
    }

    fn type_to_id(&self, ty: &Type) -> TypeId {
        match ty {
            Type::TCon(ident, _) => match ident.name.as_str() {
                "Int" | "Integer" => TypeId::TCon("Int".to_string(), vec![]),
                "Float" => TypeId::TCon("Float".to_string(), vec![]),
                "Double" => TypeId::TCon("Double".to_string(), vec![]),
                "Bool" => TypeId::TCon("Bool".to_string(), vec![]),
                "Char" => TypeId::TCon("Char".to_string(), vec![]),
                "String" => TypeId::TCon("String".to_string(), vec![]),
                "Void" => TypeId::TCon("Void".to_string(), vec![]),
                "Any" => TypeId::TCon("Any".to_string(), vec![]),
                "I8" => TypeId::TCon("I8".to_string(), vec![]),
                "I16" => TypeId::TCon("I16".to_string(), vec![]),
                "I32" => TypeId::TCon("I32".to_string(), vec![]),
                "I64" => TypeId::TCon("I64".to_string(), vec![]),
                "I128" => TypeId::TCon("I128".to_string(), vec![]),
                "Isize" => TypeId::TCon("Isize".to_string(), vec![]),
                "U8" => TypeId::TCon("U8".to_string(), vec![]),
                "U16" => TypeId::TCon("U16".to_string(), vec![]),
                "U32" => TypeId::TCon("U32".to_string(), vec![]),
                "U64" => TypeId::TCon("U64".to_string(), vec![]),
                "U128" => TypeId::TCon("U128".to_string(), vec![]),
                "Usize" => TypeId::TCon("Usize".to_string(), vec![]),
                "F32" => TypeId::TCon("F32".to_string(), vec![]),
                "F64" => TypeId::TCon("F64".to_string(), vec![]),
                _ => TypeId::TCon(ident.name.clone(), vec![]),
            },
            Type::TPtr(inner, mutable) => TypeId::TPtr(Box::new(self.type_to_id(inner)), *mutable),
            Type::TList(inner) => TypeId::TList(Box::new(self.type_to_id(inner))),
            Type::TTuple(_) => TypeId::TTuple(vec![]),
            Type::TArr(from, to) => TypeId::TArr(
                Box::new(self.type_to_id(from)),
                Box::new(self.type_to_id(to)),
            ),
            Type::TVar(name) => TypeId::TVar(name.clone()),
            Type::TForall(_, inner) => self.type_to_id(inner),
            Type::TEffect(inner, _) => self.type_to_id(inner),
            Type::TLinear(inner) => {
                TypeId::TCon("Linear".to_string(), vec![self.type_to_id(inner)])
            }
        }
    }

    fn emit_to_func(&mut self, func: &mut IrFunction, inst: IrInst) {
        let target_label = match &inst {
            IrInst::Alloca { .. } => self.entry_block.as_ref().or(self.current_block.as_ref()),
            _ => self.current_block.as_ref(),
        };
        if let Some(label) = target_label {
            if let Some(block) = func.blocks.iter_mut().find(|b| &b.label == label) {
                let target_block = block;
                if matches!(&inst, IrInst::Alloca { .. }) && target_block.label != self.current_block.as_deref().unwrap_or("") {
                    let term_idx = target_block.insts.iter().position(|i| {
                        matches!(i, IrInst::Br { .. } | IrInst::CondBr { .. } | IrInst::Ret { .. })
                    });
                    match term_idx {
                        Some(idx) => target_block.insts.insert(idx, inst),
                        None => target_block.insts.push(inst),
                    }
                } else {
                    target_block.insts.push(inst);
                }
            }
        }
    }

    fn new_alloca(&mut self, name: &str) -> String {
        let alloca_name = format!("_alloca_{}_{}", name, self.alloca_counter);
        self.alloca_counter += 1;
        alloca_name
    }

    fn new_local(&mut self) -> String {
        let name = format!("_local_{}", self.local_counter);
        self.local_counter += 1;
        name
    }

    fn new_block_label(&mut self) -> String {
        let name = format!("_block_{}", self.block_counter);
        self.block_counter += 1;
        name
    }
}
