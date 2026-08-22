//! `#[axiom_export]`, `#[axiom_opaque]` and `#[axiom_record]` — turn
//! ordinary Rust into something Axiom can link against.
//!
//! `#[axiom_export]` generates a `#[no_mangle] pub extern "C"` shim
//! whose signature is entirely `i64`s, because that is Axiom's whole
//! ABI: every value is one 64-bit word and every emitted function is
//! `define i64 @name(i64, ...)` (`self_host/codegen.ax:3014-3018`).
//! The shim is the only `unsafe` the crate author does not write. It
//! converts words to Rust types on the way in, calls the real function,
//! and converts back on the way out.
//!
//! `#[axiom_opaque]` marks a type Axiom holds as a handle and generates
//! its destructor pair. `#[axiom_record]` marks a struct that crosses
//! AS ITS FIELDS, one word each, and derives the conversions.
//!
//! # Shim shapes
//!
//! | Rust return | Shim signature | Meaning |
//! |---|---|---|
//! | scalar / `()` / opaque `T` | `fn(args..) -> i64` | the value (an opaque `T` as its boxed address) |
//! | `String` / `Vec<u8>` | `fn(args.., out: i64) -> i64` | status 0; `out` gets (ptr, len) |
//! | `Vec<T>` (T a word scalar) | `fn(args.., out: i64) -> i64` | status 0; `out` gets (ptr, len) of words |
//! | `Vec<String>` | `fn(args.., out: i64) -> i64` | status 0; `out` gets (pairs, n) |
//! | record `T` | `fn(args.., out: i64) -> i64` | status 0; `out` (ARITY words) gets the fields |
//! | `Result<T, E>` | `fn(args.., out: i64) -> i64` | 0: payload in `out`; 1: message (ptr, len) in `out` |
//! | `Option<T>` | `fn(args.., out: i64) -> i64` | 0: payload in `out`; 2: `None` |
//!
//! A byte return needs two words (pointer and length) and Axiom emits
//! `ret i64` for everything, so those shapes take an out-cell the Axiom
//! caller allocates. There is no wider return to reach for.
//!
//! Beside every shim the macro exports its **signature descriptor**: a
//! no-op `axffi_x__sig_<params>_<ret>` (`axffi_add__sig_ii_i`,
//! `axffi_shout__sig_si_i`, `axffi_abi_probe__sig__i`) whose name the
//! driver derives independently from the Axiom `extern` item's declared
//! type, so a block that declares the wrong arity or a `Float` where
//! the shim takes a word is refused before the link (AX4005). The tags
//! come from `axiom-ffi-classify`, the same table bindgen reads.
//!
//! A callback parameter (`AxFn1`, `AxFn2`, `AxFn3`) arrives as the
//! closure record word and is wrapped without a copy; a `&[T]`
//! parameter is an Axiom `Vec` handle read in place (`i64`, `f64`) or
//! converted into a temporary (every other word scalar); a `&[&str]`
//! is a `Vec` of Strings borrowed one `&str` each.
//!
//! # Records and the companion macro
//!
//! A record parameter is ONE SHIM ARGUMENT PER FIELD, so expanding a
//! function that takes `p: Point` needs `Point`'s field list - which a
//! proc macro cannot see: it is handed one item at a time. So
//! `#[axiom_record]` (and `#[axiom_opaque]`, because a bare `-> T` is
//! a record or a handle and only the type knows which) also declares
//! a COMPANION: a `macro_rules!` named exactly like the type, which
//! appends `@record Point { x: i64, y: f64 }` (or `@opaque Counter`)
//! to a callback invocation. `#[axiom_export]` on a signature that
//! names such a type expands to `Point! { ..; __axiom_export_resolved ;
//! [attr] fn .. }`, and the resolved macro does the real expansion with
//! the field lists in hand. The companion is re-exported into the
//! type's module with `pub(crate) use`, so it resolves by path in that
//! module regardless of order, and a `use` of the type imports it too
//! (a `use` takes every namespace of the name).
//!
//! # What the shim refuses at runtime
//!
//! Axiom cannot receive an error from an infallible call, so the shim
//! aborts (message on fd 2, exit 72) rather than answer wrongly when a
//! narrow integer is out of range (an argument, a record field, a
//! `&[T]` element), a `&str` argument is not UTF-8 (under the default
//! `utf8 = "strict"`; a `Result` function gets `Err` instead), or a
//! borrowed handle has been closed.
//!
//! The type table, the attribute grammar and every refusal message live
//! in `axiom-ffi-classify`, shared with `axiom-bindgen`.

use axiom_ffi_classify as cls;
use cls::{Named, Param, Payload, RecordTy, Registry, Ret, Scalar, Utf8};
use proc_macro::TokenStream;
use proc_macro2::TokenStream as TokenStream2;
use quote::{format_ident, quote};
use syn::parse::{Parse, ParseStream};
use syn::punctuated::Punctuated;
use syn::{
    braced, bracketed, parse_macro_input, FnArg, Ident, Item, ItemFn, ItemStruct, Meta, PatType,
    ReturnType, Token, Type,
};

fn attr_metas(attr: TokenStream) -> Result<Punctuated<Meta, Token![,]>, syn::Error> {
    use syn::parse::Parser;
    Punctuated::<Meta, Token![,]>::parse_terminated.parse(attr)
}

fn attr_error(e: cls::AttrError) -> syn::Error {
    match e.meta {
        Some(m) => syn::Error::new_spanned(m, e.message),
        None => syn::Error::new(proc_macro2::Span::call_site(), e.message),
    }
}

/// Export a function to Axiom.
///
/// Accepts `symbol = "name"` (the linker symbol; default `axffi_<fn>`)
/// and `utf8 = "lossy"` (convert invalid `&str` arguments with
/// `from_utf8_lossy` instead of refusing them). Any other key is an
/// error naming those two.
#[proc_macro_attribute]
pub fn axiom_export(attr: TokenStream, item: TokenStream) -> TokenStream {
    let func = parse_macro_input!(item as ItemFn);
    let expanded = attr_metas(attr).and_then(|metas| {
        let parsed = cls::parse_export_attr(metas.iter()).map_err(attr_error)?;
        expand_export_first(func, parsed, &metas)
    });
    match expanded {
        Ok(ts) => ts.into(),
        Err(e) => e.to_compile_error().into(),
    }
}

/// The second half of `#[axiom_export]` for a signature that names a
/// record or an opaque type bare: reached through the types' companion
/// macros, which append what each type is. Not for direct use.
#[doc(hidden)]
#[proc_macro]
pub fn __axiom_export_resolved(input: TokenStream) -> TokenStream {
    let resolved = parse_macro_input!(input as Resolved);
    let expanded = cls::parse_export_attr(resolved.attr.iter())
        .map_err(attr_error)
        .and_then(|a| expand_export(resolved.func, a, &resolved.table));
    match expanded {
        Ok(ts) => ts.into(),
        Err(e) => e.to_compile_error().into(),
    }
}

/// Mark a type Axiom holds as an opaque handle.
///
/// Generates `axffi_<stem>_drop(h) -> i64` (a null-checked
/// `Box::from_raw`) and `axffi_<stem>_drop_fn() -> i64` (its address),
/// where `<stem>` is the type name in snake_case or `symbol = "..."`,
/// plus the type's companion macro (see the crate note).
#[proc_macro_attribute]
pub fn axiom_opaque(attr: TokenStream, item: TokenStream) -> TokenStream {
    let item = parse_macro_input!(item as Item);
    let parsed = attr_metas(attr)
        .and_then(|metas| cls::parse_opaque_attr(metas.iter()).map_err(attr_error));
    match parsed.and_then(|a| expand_opaque(item, a)) {
        Ok(ts) => ts.into(),
        Err(e) => e.to_compile_error().into(),
    }
}

/// Mark a struct that crosses the boundary AS ITS FIELDS.
///
/// A plain struct with named fields, every one a word scalar
/// (`i64 i32 i16 i8 u32 u16 u8 usize isize bool f64 f32`). Derives
/// `axiom_ffi::AxRecord` - `ARITY`, `from_words`, `write_words` - and
/// the companion macro `#[axiom_export]` reads the field list from.
/// A parameter of the type is one shim argument per field; a result
/// is written into an out-cell of `ARITY` words. Takes no keys.
#[proc_macro_attribute]
pub fn axiom_record(attr: TokenStream, item: TokenStream) -> TokenStream {
    let item = parse_macro_input!(item as Item);
    let keys = attr_metas(attr).and_then(|metas| match metas.first() {
        Some(m) => Err(syn::Error::new_spanned(
            m,
            "`#[axiom_record]` takes no keys: the record's name is the Axiom `data` name and \
             its fields are the words",
        )),
        None => Ok(()),
    });
    match keys.and_then(|()| expand_record(item)) {
        Ok(ts) => ts.into(),
        Err(e) => e.to_compile_error().into(),
    }
}

// ---------------------------------------------------------------------
// Companions
// ---------------------------------------------------------------------

/// The companion macro of `name`, answering `payload` (`@opaque Name`
/// or `@record Name { .. }`) to a callback: declared in a hidden
/// module and re-exported beside the type.
fn companion(name: &Ident, payload: TokenStream2) -> TokenStream2 {
    let module = format_ident!("{}", cls::companion_module(&name.to_string()));
    let doc = format!(
        "The companion macro of `{name}`: how `#[axiom_export]` learns what the type is. \
         Never invoked by hand."
    );
    quote! {
        #[doc = #doc]
        #[doc(hidden)]
        #[allow(non_snake_case)]
        pub mod #module {
            #[allow(unused_macros)]
            macro_rules! #name {
                ($callee:path ; $($args:tt)*) => { $callee ! { $($args)* #payload } };
            }
            #[allow(unused_imports)]
            pub(crate) use #name;
        }
        #[doc(hidden)]
        #[allow(unused_imports)]
        pub(crate) use #module::#name;
    }
}

/// What the companions appended: `[attr] fn .. (@record N {..} | @opaque N)*`.
struct Resolved {
    attr: Punctuated<Meta, Token![,]>,
    func: ItemFn,
    table: Table,
}

/// The named types a resolved expansion knows.
struct Table(Vec<(String, Named)>);

impl Registry for Table {
    fn lookup(&self, name: &str) -> Option<Named> {
        self.0.iter().find(|(n, _)| n == name).map(|(_, k)| k.clone())
    }
}

impl Parse for Resolved {
    fn parse(input: ParseStream) -> syn::Result<Self> {
        let content;
        bracketed!(content in input);
        let attr = content.parse_terminated(Meta::parse, Token![,])?;
        let func: ItemFn = input.parse()?;
        let mut table = Vec::new();
        while input.peek(Token![@]) {
            input.parse::<Token![@]>()?;
            let kind: Ident = input.parse()?;
            let name: Ident = input.parse()?;
            let entry = match kind.to_string().as_str() {
                "opaque" => Named::Opaque,
                "record" => {
                    let body;
                    braced!(body in input);
                    let fields: Punctuated<RecordFieldSyntax, Token![,]> =
                        body.parse_terminated(RecordFieldSyntax::parse, Token![,])?;
                    let named: Vec<(String, Type)> =
                        fields.iter().map(|f| (f.name.to_string(), f.ty.clone())).collect();
                    let classified = cls::classify_record_fields(
                        named.iter().map(|(n, t)| (n.as_str(), t)),
                    )
                    .map_err(|m| syn::Error::new(name.span(), m))?;
                    Named::Record(classified)
                }
                other => {
                    return Err(syn::Error::new(
                        kind.span(),
                        format!("unknown companion payload `@{other}`"),
                    ))
                }
            };
            table.push((name.to_string(), entry));
        }
        Ok(Resolved { attr, func, table: Table(table) })
    }
}

/// `name: Type` inside a `@record` payload.
struct RecordFieldSyntax {
    name: Ident,
    ty: Type,
}

impl Parse for RecordFieldSyntax {
    fn parse(input: ParseStream) -> syn::Result<Self> {
        let name: Ident = input.parse()?;
        input.parse::<Token![:]>()?;
        let ty: Type = input.parse()?;
        Ok(RecordFieldSyntax { name, ty })
    }
}

// ---------------------------------------------------------------------
// #[axiom_opaque]
// ---------------------------------------------------------------------

fn expand_opaque(item: Item, attr: cls::OpaqueAttr) -> Result<TokenStream2, syn::Error> {
    let (ident, generics) = match &item {
        Item::Struct(s) => (&s.ident, &s.generics),
        Item::Enum(e) => (&e.ident, &e.generics),
        other => {
            return Err(syn::Error::new_spanned(
                other,
                "`#[axiom_opaque]` goes on a `struct` or `enum` declaration: the type Axiom \
                 will hold as a handle",
            ))
        }
    };
    if !generics.params.is_empty() {
        return Err(syn::Error::new_spanned(
            generics,
            "an `#[axiom_opaque]` type must be monomorphic: its destructor is one exported \
             symbol, and a symbol cannot be generic",
        ));
    }
    let name = ident.to_string();
    let stem = cls::opaque_stem(&name, &attr);
    let drop_ident = format_ident!("{}", cls::drop_symbol(&stem));
    let drop_fn_ident = format_ident!("{}", cls::drop_fn_symbol(&stem));
    let drop_doc = format!(
        "The destructor Axiom's handle calls for `{name}` when its last reference dies \
         (or on an explicit close). Null-checked; answers 0."
    );
    let drop_fn_doc = format!("The address of `{}`, for `ffiHandleNew`.", cls::drop_symbol(&stem));
    let companion = companion(ident, quote! { @opaque #ident });
    Ok(quote! {
        #item

        impl ::axiom_ffi::AxiomOpaque for #ident {
            const STEM: &'static str = #stem;
            const DROP: unsafe extern "C" fn(::axiom_ffi::AxWord) -> ::axiom_ffi::AxWord = #drop_ident;
        }

        impl ::axiom_ffi::AxiomMarked for #ident {}

        #[doc = #drop_doc]
        ///
        /// # Safety
        /// `h` is 0 or a handle word this crate produced and has not freed.
        #[no_mangle]
        pub unsafe extern "C" fn #drop_ident(h: ::axiom_ffi::AxWord) -> ::axiom_ffi::AxWord {
            ::axiom_ffi::__private::drop_opaque::<#ident>(h)
        }

        #[doc = #drop_fn_doc]
        #[no_mangle]
        pub extern "C" fn #drop_fn_ident() -> ::axiom_ffi::AxWord {
            <#ident as ::axiom_ffi::AxiomOpaque>::DROP as usize as ::axiom_ffi::AxWord
        }

        #companion
    })
}

// ---------------------------------------------------------------------
// #[axiom_record]
// ---------------------------------------------------------------------

fn expand_record(item: Item) -> Result<TokenStream2, syn::Error> {
    let s: ItemStruct = match item {
        Item::Struct(s) => s,
        other => {
            return Err(syn::Error::new_spanned(
                other,
                "`#[axiom_record]` goes on a `struct` with named fields: the value that \
                 crosses as its fields (an `enum` or a type Axiom should hold as a handle \
                 takes `#[axiom_opaque]`)",
            ))
        }
    };
    if !s.generics.params.is_empty() {
        return Err(syn::Error::new_spanned(
            &s.generics,
            "an `#[axiom_record]` must be monomorphic: its fields are the words of one \
             fixed shim signature",
        ));
    }
    let named = match &s.fields {
        syn::Fields::Named(f) => &f.named,
        other => {
            return Err(syn::Error::new_spanned(
                other,
                "an `#[axiom_record]` needs named fields (`struct Point { x: i64, y: f64 }`): \
                 the names are the Axiom `data` field order and the abort messages",
            ))
        }
    };
    let pairs: Vec<(String, &Type)> = named
        .iter()
        .map(|f| (f.ident.as_ref().map(|i| i.to_string()).unwrap_or_default(), &f.ty))
        .collect();
    let fields = cls::classify_record_fields(pairs.iter().map(|(n, t)| (n.as_str(), *t)))
        .map_err(|m| {
            // Point at the offending field when the message names one.
            let span_on: &dyn quote::ToTokens = named
                .iter()
                .find(|f| {
                    f.ident
                        .as_ref()
                        .map(|i| m.starts_with(&format!("field `{i}:")))
                        .unwrap_or(false)
                })
                .map(|f| &f.ty as &dyn quote::ToTokens)
                .unwrap_or(&s.ident);
            syn::Error::new_spanned(span_on, m)
        })?;

    let ident = &s.ident;
    let name = ident.to_string();
    let arity = fields.len();
    let field_idents: Vec<Ident> = fields.iter().map(|f| format_ident!("{}", f.name)).collect();
    let field_types: Vec<&Type> = named.iter().map(|f| &f.ty).collect();
    let reads: Vec<TokenStream2> = fields
        .iter()
        .enumerate()
        .map(|(j, f)| {
            let fname = &f.name;
            match f.scalar {
                Scalar::I64 => quote! { words[#j] },
                Scalar::Bool => quote! { words[#j] != 0 },
                Scalar::F64 => quote! { f64::from_bits(words[#j] as u64) },
                Scalar::F32 => quote! { f64::from_bits(words[#j] as u64) as f32 },
                Scalar::Unit => unreachable!("classify_record_fields refuses ()"),
                narrow => {
                    let t = format_ident!("{}", narrow.rust_name());
                    quote! { ::axiom_ffi::__private::record_field::<#t>(words[#j], #name, #fname) }
                }
            }
        })
        .collect();
    let writes: Vec<TokenStream2> = fields
        .iter()
        .enumerate()
        .map(|(j, f)| {
            let fi = &field_idents[j];
            let w = scalar_to_word(f.scalar, quote! { self.#fi });
            quote! { out[#j] = #w; }
        })
        .collect();
    let payload = quote! { @record #ident { #(#field_idents: #field_types),* } };
    let companion = companion(ident, payload);
    let doc = format!(
        "`{name}` crosses the Axiom boundary as its {arity} field word{}, in declaration order.",
        if arity == 1 { "" } else { "s" }
    );
    Ok(quote! {
        #s

        #[doc = #doc]
        impl ::axiom_ffi::AxRecord for #ident {
            const ARITY: usize = #arity;

            fn from_words(words: &[::axiom_ffi::AxWord]) -> Self {
                #ident { #(#field_idents: #reads),* }
            }

            fn write_words(&self, out: &mut [::axiom_ffi::AxWord]) {
                #(#writes)*
            }
        }

        impl ::axiom_ffi::AxiomMarked for #ident {}

        #companion
    })
}

// ---------------------------------------------------------------------
// #[axiom_export]
// ---------------------------------------------------------------------

/// The first pass: validate the item, classify without any knowledge
/// of named types, and either expand directly or route through the
/// companions of the types the signature names.
fn expand_export_first(
    func: ItemFn,
    attr: cls::ExportAttr,
    metas: &Punctuated<Meta, Token![,]>,
) -> Result<TokenStream2, syn::Error> {
    let (params, ret) = classify_signature(&func, &cls::NoRecords)?;
    let named = cls::named_types(&params, &ret);
    if named.is_empty() {
        return expand_shim(func, attr, params, ret);
    }
    // `T1! { T2 ; .. ; ::axiom_ffi::__axiom_export_resolved ; [attr] fn .. }`:
    // each companion appends its payload and calls the next.
    let mut call = quote! { ::axiom_ffi::__axiom_export_resolved ; [#metas] #func };
    for ty in named.iter().skip(1).rev() {
        call = quote! { #ty ; #call };
    }
    let first = &named[0];
    // Asserted beside the chain so an unmarked type is reported as the
    // missing attribute, not only as the unresolvable companion.
    let asserts = named.iter().map(|ty| {
        quote! {
            const _: () = {
                fn __axiom_marked<T: ::axiom_ffi::AxiomMarked>() {}
                let _ = __axiom_marked::<#ty>;
            };
        }
    });
    Ok(quote! {
        #(#asserts)*
        #first ! { #call }
    })
}

/// The second pass (or the only one, when no named type is involved).
fn expand_export(
    func: ItemFn,
    attr: cls::ExportAttr,
    registry: &dyn Registry,
) -> Result<TokenStream2, syn::Error> {
    let (params, ret) = classify_signature(&func, registry)?;
    for (p, arg) in params.iter().zip(func.sig.inputs.iter()) {
        if let Param::Record(r) = p {
            if !r.is_resolved() {
                return Err(syn::Error::new_spanned(
                    arg,
                    format!(
                        "`{}` is taken by value but its companion macro answered nothing: \
                         is it marked `#[axiom_record]`?",
                        r.name
                    ),
                ));
            }
        }
    }
    expand_shim(func, attr, params, ret)
}

/// Validate the item and classify every parameter and the return.
fn classify_signature(
    func: &ItemFn,
    registry: &dyn Registry,
) -> Result<(Vec<Param>, Ret), syn::Error> {
    if !matches!(func.vis, syn::Visibility::Public(_)) {
        return Err(syn::Error::new_spanned(
            &func.sig.ident,
            "an `#[axiom_export]` function must be `pub`: its shim is a public symbol of \
             the crate, and axiom-bindgen binds only `pub` functions",
        ));
    }
    if func.sig.asyncness.is_some() {
        return Err(syn::Error::new_spanned(
            &func.sig,
            "an `async fn` cannot be exported: Axiom has no threads, no scheduler and no \
             async (MM-PAR-1). Export a blocking wrapper, or drive a runtime behind an \
             `#[axiom_opaque]` handle.",
        ));
    }
    if func.sig.unsafety.is_some() {
        return Err(syn::Error::new_spanned(
            &func.sig,
            "an `unsafe fn` cannot be exported: the generated shim is the only unsafe code \
             at the boundary. Wrap the unsafe body in a safe `pub fn` and export that.",
        ));
    }
    if !func.sig.generics.params.is_empty() {
        return Err(syn::Error::new_spanned(
            &func.sig.generics,
            "an exported function must be monomorphic: an Axiom `extern` may not be \
             polymorphic, because a polymorphic Axiom function grows a hidden trailing \
             evidence word (codegen.ax:3008-3021) that must never reach Rust.",
        ));
    }
    if func.sig.variadic.is_some() {
        return Err(syn::Error::new_spanned(
            &func.sig,
            "an exported function cannot be variadic: every Axiom call has a fixed arity",
        ));
    }

    let ret_ty: Option<&Type> = match &func.sig.output {
        ReturnType::Default => None,
        ReturnType::Type(_, t) => Some(&**t),
    };
    let ret = cls::classify_return_with(ret_ty, registry).map_err(|m| {
        let span_on: &dyn quote::ToTokens = match ret_ty {
            Some(t) => t,
            None => &func.sig,
        };
        syn::Error::new_spanned(span_on, m)
    })?;

    let mut params = Vec::new();
    for arg in &func.sig.inputs {
        let pt: &PatType = match arg {
            FnArg::Typed(pt) => pt,
            FnArg::Receiver(r) => {
                return Err(syn::Error::new_spanned(
                    r,
                    "an exported function may not take `self`; export a free function \
                     that takes `&Self` (an `#[axiom_opaque]` handle) as its first argument",
                ))
            }
        };
        let p = cls::classify_param_with(&pt.ty, registry)
            .map_err(|m| syn::Error::new_spanned(&pt.ty, m))?;
        params.push(p);
    }
    Ok((params, ret))
}

/// Generate the shim and its descriptor from a classified signature.
fn expand_shim(
    func: ItemFn,
    attr: cls::ExportAttr,
    params: Vec<Param>,
    ret: Ret,
) -> Result<TokenStream2, syn::Error> {
    let name = func.sig.ident.clone();
    let name_str = name.to_string();
    let shim = format_ident!("{}", cls::export_symbol(&name_str, &attr));
    let fallible = ret.is_result();
    let needs_cell = ret.needs_cell();

    // ---- parameters -------------------------------------------------
    let mut shim_params = Vec::new();
    let mut call_args = Vec::new();
    let mut prologue = Vec::new();

    for (i, (arg, param)) in func.sig.inputs.iter().zip(params.iter()).enumerate() {
        let FnArg::Typed(pt) = arg else { unreachable!("classify_signature refuses self") };
        let w = format_ident!("a{}", i);
        let idx = i + 1;
        let pname = match &*pt.pat {
            syn::Pat::Ident(id) => id.ident.to_string(),
            _ => format!("#{idx}"),
        };
        if let Param::Record(r) = param {
            // One shim word per field, rebuilt into the value.
            let words: Vec<Ident> = (0..r.arity()).map(|j| format_ident!("a{}_{}", i, j)).collect();
            let ty = &r.ty;
            shim_params.extend(words.iter().map(|w| quote! { #w: ::axiom_ffi::AxWord }));
            prologue.push(quote! {
                let #w: #ty = <#ty as ::axiom_ffi::AxRecord>::from_words(&[#(#words),*]);
            });
            call_args.push(quote! { #w });
            continue;
        }
        shim_params.push(quote! { #w: ::axiom_ffi::AxWord });

        match param {
            Param::Scalar(s) => match s {
                Scalar::I64 => call_args.push(quote! { #w }),
                Scalar::Bool => call_args.push(quote! { #w != 0 }),
                Scalar::F64 => call_args.push(quote! { f64::from_bits(#w as u64) }),
                Scalar::F32 => call_args.push(quote! { f64::from_bits(#w as u64) as f32 }),
                Scalar::Unit => unreachable!("classify_param refuses ()"),
                narrow => {
                    let t = format_ident!("{}", narrow.rust_name());
                    prologue.push(quote! {
                        let #w: #t = ::axiom_ffi::__private::narrow::<#t>(#w, #name_str, #idx, #pname);
                    });
                    call_args.push(quote! { #w });
                }
            },
            Param::Str => {
                match (attr.utf8(), fallible) {
                    (Utf8::Lossy, _) => prologue.push(quote! {
                        // SAFETY: the caller is generated Axiom glue, which
                        // holds the String live across the call.
                        let #w = unsafe { ::axiom_ffi::__private::str_lossy(#w) };
                        let #w: &str = &#w;
                    }),
                    (Utf8::Strict, true) => prologue.push(quote! {
                        let #w: &str = match unsafe {
                            ::axiom_ffi::__private::str_fallible(#w, #name_str, #idx)
                        } {
                            Ok(s) => s,
                            Err(m) => return ::axiom_ffi::__private::err_into(cell, m),
                        };
                    }),
                    (Utf8::Strict, false) => prologue.push(quote! {
                        let #w: &str = unsafe {
                            ::axiom_ffi::__private::str_strict(#w, #name_str, #idx)
                        };
                    }),
                }
                call_args.push(quote! { #w });
            }
            Param::Strs => {
                match (attr.utf8(), fallible) {
                    (Utf8::Lossy, _) => prologue.push(quote! {
                        let #w = unsafe {
                            ::axiom_ffi::__private::strs_lossy(#w, #name_str, #idx, #pname)
                        };
                        let #w: ::axiom_ffi::__private::Vec<&str> =
                            #w.iter().map(|s| s.as_str()).collect();
                        let #w: &[&str] = &#w;
                    }),
                    (Utf8::Strict, true) => prologue.push(quote! {
                        let #w = match unsafe {
                            ::axiom_ffi::__private::strs_fallible(#w, #name_str, #idx, #pname)
                        } {
                            Ok(v) => v,
                            Err(m) => return ::axiom_ffi::__private::err_into(cell, m),
                        };
                        let #w: &[&str] = &#w;
                    }),
                    (Utf8::Strict, false) => prologue.push(quote! {
                        let #w = unsafe {
                            ::axiom_ffi::__private::strs_strict(#w, #name_str, #idx, #pname)
                        };
                        let #w: &[&str] = &#w;
                    }),
                }
                call_args.push(quote! { #w });
            }
            Param::Bytes => {
                prologue.push(quote! {
                    let #w: &[u8] = unsafe { ::axiom_ffi::__private::bytes(#w) };
                });
                call_args.push(quote! { #w });
            }
            Param::Words(s) => {
                match s {
                    Scalar::I64 => prologue.push(quote! {
                        let #w: &[i64] = unsafe {
                            ::axiom_ffi::__private::words(#w, #name_str, #idx, #pname)
                        };
                    }),
                    Scalar::F64 => prologue.push(quote! {
                        let #w: &[f64] = unsafe {
                            ::axiom_ffi::__private::words_f64(#w, #name_str, #idx, #pname)
                        };
                    }),
                    Scalar::Unit => unreachable!("classify_param refuses &[()]"),
                    other => {
                        let t = format_ident!("{}", other.rust_name());
                        prologue.push(quote! {
                            let #w = unsafe {
                                ::axiom_ffi::__private::words_as::<#t>(#w, #name_str, #idx, #pname)
                            };
                            let #w: &[#t] = &#w;
                        });
                    }
                }
                call_args.push(quote! { #w });
            }
            Param::Callback(arity) => {
                let t = format_ident!("AxFn{}", arity);
                prologue.push(quote! {
                    let #w: ::axiom_ffi::#t = unsafe {
                        ::axiom_ffi::__private::callback::<::axiom_ffi::#t>(#w, #name_str, #idx, #pname)
                    };
                });
                call_args.push(quote! { #w });
            }
            Param::Opaque { ty, mutable } => {
                let base = &ty.ty;
                if *mutable {
                    call_args.push(quote! {
                        unsafe { ::axiom_ffi::__private::borrow_mut::<#base>(#w, #name_str) }
                    });
                } else {
                    call_args.push(quote! {
                        unsafe { ::axiom_ffi::__private::borrow::<#base>(#w, #name_str) }
                    });
                }
            }
            Param::Record(_) => unreachable!("handled above"),
        }
    }

    let body_call = quote! { #name(#(#call_args),*) };
    let doc = format!(
        "The Axiom-facing shim for [`{name_str}`]: all-`i64` C ABI, generated by \
         `#[axiom_export]`."
    );

    // The descriptor: a no-op whose name is the shape. Never called;
    // the driver reads it from the archive's symbol table.
    let sig = format_ident!("{}", cls::sig_symbol(&shim.to_string(), &params, &ret));
    let sig_doc = format!(
        "The signature descriptor of `{shim}`: its name encodes the shim's shape for the \
         Axiom driver's check. Never called."
    );
    let sig_fn = quote! {
        #[doc = #sig_doc]
        #[doc(hidden)]
        #[no_mangle]
        pub extern "C" fn #sig() -> ::axiom_ffi::AxWord {
            0
        }
    };

    let shim_fn = if needs_cell {
        let tail = match &ret {
            Ret::Bytes | Ret::Words(_) | Ret::Strs | Ret::Record(_) => {
                let store = store_payload(&direct_payload(&ret));
                quote! {
                    let v = #body_call;
                    #store
                    ::axiom_ffi::AX_OK
                }
            }
            Ret::Result(payload) => {
                let store = store_payload(payload);
                quote! {
                    match #body_call {
                        Ok(v) => { #store ::axiom_ffi::AX_OK }
                        Err(e) => {
                            let (p, n) = ::axiom_ffi::__private::error_bytes(&e);
                            cell.payload = p;
                            cell.extra = n;
                            ::axiom_ffi::AX_ERR
                        }
                    }
                }
            }
            Ret::Option(payload) => {
                let store = store_payload(payload);
                quote! {
                    match #body_call {
                        Some(v) => { #store ::axiom_ffi::AX_OK }
                        None => ::axiom_ffi::AX_NONE,
                    }
                }
            }
            Ret::Scalar(_) | Ret::Opaque(_) => unreachable!("no cell"),
        };
        // A record rides the raw `out` address (its cell is wider than
        // the two-word view); a direct or optional record result never
        // touches the view, so it is not bound.
        let uses_view = !matches!(&ret, Ret::Record(_) | Ret::Option(Payload::Record(_)));
        let view = uses_view.then(|| {
            quote! {
                // SAFETY: the out-cell is at least two words generated
                // Axiom glue allocated for this call.
                let cell = unsafe { ::axiom_ffi::AxOutCell::from_word(out) };
            }
        });
        quote! {
            #[doc = #doc]
            #[no_mangle]
            pub extern "C" fn #shim(#(#shim_params,)* out: ::axiom_ffi::AxWord)
                -> ::axiom_ffi::AxStatus
            {
                #view
                #(#prologue)*
                #tail
            }
        }
    } else {
        let conv = match &ret {
            Ret::Scalar(s) => scalar_to_word(*s, quote! { v }),
            Ret::Opaque(o) => {
                let t = &o.ty;
                quote! { ::axiom_ffi::__private::leak_opaque::<#t>(v) }
            }
            _ => unreachable!(),
        };
        quote! {
            #[doc = #doc]
            #[no_mangle]
            pub extern "C" fn #shim(#(#shim_params),*) -> ::axiom_ffi::AxWord {
                #(#prologue)*
                let v = #body_call;
                #conv
            }
        }
    };

    Ok(quote! { #func #shim_fn #sig_fn })
}

/// The payload a direct cell-carried return stores.
fn direct_payload(r: &Ret) -> Payload {
    match r {
        Ret::Bytes => Payload::Bytes,
        Ret::Words(s) => Payload::Words(*s),
        Ret::Strs => Payload::Strs,
        Ret::Record(r) => Payload::Record(r.clone()),
        _ => unreachable!("only the cell-carried shapes are direct payloads"),
    }
}

/// `v` (a scalar expression) to the word it crosses as.
fn scalar_to_word(s: Scalar, v: TokenStream2) -> TokenStream2 {
    match s {
        Scalar::Unit => quote! { { let () = #v; 0 } },
        Scalar::Bool => quote! { if #v { 1 } else { 0 } },
        Scalar::F64 => quote! { #v.to_bits() as ::axiom_ffi::AxWord },
        Scalar::F32 => quote! { (#v as f64).to_bits() as ::axiom_ffi::AxWord },
        _ => quote! { #v as ::axiom_ffi::AxWord },
    }
}

/// Store `v` (a payload) into the cell (`cell` for the two-word
/// protocols, the raw `out` word for a record, whose cell is wider).
fn store_payload(p: &Payload) -> TokenStream2 {
    match p {
        Payload::Scalar(s) => {
            let w = scalar_to_word(*s, quote! { v });
            quote! { cell.payload = #w; }
        }
        Payload::Bytes => quote! {
            let (p, n) = ::axiom_ffi::__private::leak_bytes(v.into());
            cell.payload = p;
            cell.extra = n;
        },
        Payload::Words(Scalar::I64) => quote! {
            let (p, n) = ::axiom_ffi::__private::leak_words(v);
            cell.payload = p;
            cell.extra = n;
        },
        Payload::Words(_) => quote! {
            let (p, n) = ::axiom_ffi::__private::leak_words(::axiom_ffi::__private::to_words(v));
            cell.payload = p;
            cell.extra = n;
        },
        Payload::Strs => quote! {
            let (p, n) = ::axiom_ffi::__private::leak_strs(v);
            cell.payload = p;
            cell.extra = n;
        },
        Payload::Opaque(o) => {
            let t = &o.ty;
            quote! { cell.payload = ::axiom_ffi::__private::leak_opaque::<#t>(v); }
        }
        Payload::Record(r) => record_store(r),
    }
}

/// Write a record payload: `ARITY` words from the cell's first word,
/// through the raw `out` address (the cell is `ffiCellNewN ARITY`,
/// wider than the two-word `AxOutCell` view).
fn record_store(r: &RecordTy) -> TokenStream2 {
    let t = &r.ty;
    quote! {
        // SAFETY: Axiom glue allocated a cell of at least ARITY words
        // for this call; `cell` is not read again on this path.
        unsafe { ::axiom_ffi::__private::write_record::<#t>(out, &v) };
    }
}
