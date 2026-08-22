//! `#[axiom_export]` and `#[axiom_opaque]` — turn ordinary Rust into
//! something Axiom can link against.
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
//! its destructor pair.
//!
//! # Shim shapes
//!
//! | Rust return | Shim signature | Meaning |
//! |---|---|---|
//! | scalar / `()` / opaque `T` | `fn(args..) -> i64` | the value (an opaque `T` as its boxed address) |
//! | `String` / `Vec<u8>` | `fn(args.., out: i64) -> i64` | status 0; `out` gets (ptr, len) |
//! | `Result<T, E>` | `fn(args.., out: i64) -> i64` | 0: payload in `out`; 1: message (ptr, len) in `out` |
//! | `Option<T>` | `fn(args.., out: i64) -> i64` | 0: payload in `out`; 2: `None` |
//!
//! A byte return needs two words (pointer and length) and Axiom emits
//! `ret i64` for everything, so those shapes take an out-cell the Axiom
//! caller allocates. There is no wider return to reach for.
//!
//! # What the shim refuses at runtime
//!
//! Axiom cannot receive an error from an infallible call, so the shim
//! aborts (message on fd 2, exit 72) rather than answer wrongly when a
//! narrow integer is out of range, a `&str` argument is not UTF-8 (under
//! the default `utf8 = "strict"`; a `Result` function gets `Err`
//! instead), or a borrowed handle has been closed.
//!
//! The type table, the attribute grammar and every refusal message live
//! in `axiom-ffi-classify`, shared with `axiom-bindgen`.

use axiom_ffi_classify as cls;
use cls::{Param, Payload, Ret, Scalar, Utf8};
use proc_macro::TokenStream;
use proc_macro2::TokenStream as TokenStream2;
use quote::{format_ident, quote};
use syn::punctuated::Punctuated;
use syn::{parse_macro_input, FnArg, Item, ItemFn, Meta, PatType, ReturnType, Token, Type};

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
    let parsed = attr_metas(attr)
        .and_then(|metas| cls::parse_export_attr(metas.iter()).map_err(attr_error));
    match parsed.and_then(|a| expand_export(func, a)) {
        Ok(ts) => ts.into(),
        Err(e) => e.to_compile_error().into(),
    }
}

/// Mark a type Axiom holds as an opaque handle.
///
/// Generates `axffi_<stem>_drop(h) -> i64` (a null-checked
/// `Box::from_raw`) and `axffi_<stem>_drop_fn() -> i64` (its address),
/// where `<stem>` is the type name in snake_case or `symbol = "..."`.
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
    Ok(quote! {
        #item

        impl ::axiom_ffi::AxiomOpaque for #ident {
            const STEM: &'static str = #stem;
            const DROP: unsafe extern "C" fn(::axiom_ffi::AxWord) -> ::axiom_ffi::AxWord = #drop_ident;
        }

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
    })
}

fn expand_export(func: ItemFn, attr: cls::ExportAttr) -> Result<TokenStream2, syn::Error> {
    let name = func.sig.ident.clone();
    let name_str = name.to_string();
    let shim = format_ident!("{}", cls::export_symbol(&name_str, &attr));

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

    // ---- return (classified first: `&str` handling depends on it) ----
    let ret_ty: Option<&Type> = match &func.sig.output {
        ReturnType::Default => None,
        ReturnType::Type(_, t) => Some(&**t),
    };
    let ret = cls::classify_return(ret_ty).map_err(|m| {
        let span_on: &dyn quote::ToTokens = match ret_ty {
            Some(t) => t,
            None => &func.sig,
        };
        syn::Error::new_spanned(span_on, m)
    })?;
    let fallible = ret.is_result();
    let needs_cell = ret.needs_cell();

    // ---- parameters -------------------------------------------------
    let mut shim_params = Vec::new();
    let mut call_args = Vec::new();
    let mut prologue = Vec::new();

    for (i, arg) in func.sig.inputs.iter().enumerate() {
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
        let param = cls::classify_param(&pt.ty).map_err(|m| syn::Error::new_spanned(&pt.ty, m))?;
        let w = format_ident!("a{}", i);
        let idx = i + 1;
        let pname = match &*pt.pat {
            syn::Pat::Ident(id) => id.ident.to_string(),
            _ => format!("#{idx}"),
        };
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
            Param::Bytes => {
                prologue.push(quote! {
                    let #w: &[u8] = unsafe { ::axiom_ffi::__private::bytes(#w) };
                });
                call_args.push(quote! { #w });
            }
            Param::Opaque { ty, mutable } => {
                let base = &ty.ty;
                if mutable {
                    call_args.push(quote! {
                        unsafe { ::axiom_ffi::__private::borrow_mut::<#base>(#w, #name_str) }
                    });
                } else {
                    call_args.push(quote! {
                        unsafe { ::axiom_ffi::__private::borrow::<#base>(#w, #name_str) }
                    });
                }
            }
        }
    }

    let body_call = quote! { #name(#(#call_args),*) };
    let doc = format!(
        "The Axiom-facing shim for [`{name_str}`]: all-`i64` C ABI, generated by \
         `#[axiom_export]`."
    );

    let shim_fn = if needs_cell {
        let tail = match &ret {
            Ret::Bytes => quote! {
                let v = #body_call;
                let (p, n) = ::axiom_ffi::__private::leak_bytes(v.into());
                cell.payload = p;
                cell.extra = n;
                ::axiom_ffi::AX_OK
            },
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
            _ => unreachable!(),
        };
        quote! {
            #[doc = #doc]
            #[no_mangle]
            pub extern "C" fn #shim(#(#shim_params,)* out: ::axiom_ffi::AxWord)
                -> ::axiom_ffi::AxStatus
            {
                // SAFETY: the out-cell is two words generated Axiom glue
                // allocated for this call.
                let cell = unsafe { ::axiom_ffi::AxOutCell::from_word(out) };
                #(#prologue)*
                #tail
            }
        }
    } else {
        let conv = match &ret {
            Ret::Scalar(s) => scalar_to_word(*s),
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

    Ok(quote! { #func #shim_fn })
}

/// `v` (a scalar) to the word the shim returns.
fn scalar_to_word(s: Scalar) -> TokenStream2 {
    match s {
        Scalar::Unit => quote! { { let () = v; 0 } },
        Scalar::Bool => quote! { if v { 1 } else { 0 } },
        Scalar::F64 => quote! { v.to_bits() as ::axiom_ffi::AxWord },
        Scalar::F32 => quote! { (v as f64).to_bits() as ::axiom_ffi::AxWord },
        _ => quote! { v as ::axiom_ffi::AxWord },
    }
}

/// Store `v` (a payload) into `cell`.
fn store_payload(p: &Payload) -> TokenStream2 {
    match p {
        Payload::Scalar(s) => {
            let w = scalar_to_word(*s);
            quote! { cell.payload = #w; }
        }
        Payload::Bytes => quote! {
            let (p, n) = ::axiom_ffi::__private::leak_bytes(v.into());
            cell.payload = p;
            cell.extra = n;
        },
        Payload::Opaque(o) => {
            let t = &o.ty;
            quote! { cell.payload = ::axiom_ffi::__private::leak_opaque::<#t>(v); }
        }
    }
}
