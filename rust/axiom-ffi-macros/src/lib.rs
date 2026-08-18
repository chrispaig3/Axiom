//! `#[axiom_export]` — turn an ordinary Rust function into one Axiom can
//! link against.
//!
//! The attribute generates a `#[no_mangle] pub extern "C"` shim whose
//! signature is entirely `i64`s, because that is Axiom's whole ABI: every
//! value is one 64-bit word and every emitted function is
//! `define i64 @name(i64, ...)` (`self_host/codegen.ax:3014-3018`).
//!
//! The shim is the only `unsafe` the crate author does not write. It
//! converts words to Rust types on the way in, calls the real function,
//! and converts back on the way out.
//!
//! # Shim shapes
//!
//! | Rust return | Shim signature | Meaning |
//! |---|---|---|
//! | scalar / opaque | `fn(args..) -> i64` | the value |
//! | `String` / `Vec<u8>` | `fn(args.., out: i64) -> i64` | status; `out` gets (ptr, len) |
//! | `Result<T, E>` | `fn(args.., out: i64) -> i64` | status; `out` gets payload or message |
//!
//! A byte return needs two words (pointer and length) and Axiom emits
//! `ret i64` for everything, so those shapes take an out-cell the Axiom
//! caller allocates. There is no wider return to reach for.

use proc_macro::TokenStream;
use quote::{format_ident, quote};
use syn::{
    parse_macro_input, FnArg, GenericArgument, ItemFn, PatType, PathArguments, ReturnType, Type,
};

/// How one Rust type crosses the boundary.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Wire {
    /// Passes as itself in an i64.
    Int,
    /// Travels as its IEEE-754 bits in an i64 — Axiom does the same
    /// (`self_host/codegen.ax:4793-4801`).
    Float,
    /// 0 or 1 in an i64.
    Bool,
    /// A borrowed `&str` view over Axiom's `{len, ptr, owner}` run.
    StrRef,
    /// A borrowed `&[u8]` view over the same.
    BytesRef,
    /// An opaque Rust value Axiom holds as one word.
    Opaque,
    /// Owned bytes returned through the out-cell.
    OwnedBytes,
    /// Nothing.
    Unit,
}

fn classify(ty: &Type) -> Result<Wire, String> {
    match ty {
        Type::Reference(r) => match &*r.elem {
            Type::Path(p) if p.path.is_ident("str") => Ok(Wire::StrRef),
            Type::Slice(s) => match &*s.elem {
                Type::Path(p) if p.path.is_ident("u8") => Ok(Wire::BytesRef),
                _ => Err("only `&[u8]` slices cross the boundary".into()),
            },
            // A reference to any other named type is an OPAQUE BORROW:
            // Axiom holds the handle word and hands it straight back.
            // This is the shape that makes `&Sha256`, `&Client`,
            // `&serde_json::Value` bindable without describing them.
            Type::Path(_) => Ok(Wire::Opaque),
            _ => Err("only `&str`, `&[u8]` and references to named types \
                      cross the boundary"
                .into()),
        },
        Type::Tuple(t) if t.elems.is_empty() => Ok(Wire::Unit),
        Type::Path(p) => {
            let seg = p.path.segments.last().ok_or("empty type path")?;
            let name = seg.ident.to_string();
            match name.as_str() {
                "i64" | "i32" | "isize" | "u32" | "usize" => Ok(Wire::Int),
                "f64" => Ok(Wire::Float),
                "bool" => Ok(Wire::Bool),
                "String" => Ok(Wire::OwnedBytes),
                "Vec" => {
                    if let PathArguments::AngleBracketed(a) = &seg.arguments {
                        if let Some(GenericArgument::Type(Type::Path(inner))) = a.args.first() {
                            if inner.path.is_ident("u8") {
                                return Ok(Wire::OwnedBytes);
                            }
                        }
                    }
                    Err("only `Vec<u8>` crosses directly; other collections \
                         must cross as an opaque handle or be serialised"
                        .into())
                }
                // Anything else is treated as an opaque handle. This is
                // deliberate: it is what makes wrapping an arbitrary crate
                // type possible without describing it to Axiom.
                _ => Ok(Wire::Opaque),
            }
        }
        _ => Err("unsupported type at the FFI boundary".into()),
    }
}

/// Peel a leading `&`/`&mut` off a type, answering the pointee and
/// whether the borrow was mutable. Axiom has no threads (MM-PAR-1), so a
/// `&mut` handle cannot be aliased across a thread; the only aliasing
/// risk is passing the same handle twice in one call.
fn peel(ty: &Type) -> (&Type, bool) {
    match ty {
        Type::Reference(r) => (&*r.elem, r.mutability.is_some()),
        other => (other, false),
    }
}

/// `Result<T, E>` is detected structurally so the shim can pick the
/// fallible shape.
fn result_ok_type(ty: &Type) -> Option<&Type> {
    if let Type::Path(p) = ty {
        let seg = p.path.segments.last()?;
        if seg.ident == "Result" {
            if let PathArguments::AngleBracketed(a) = &seg.arguments {
                if let Some(GenericArgument::Type(t)) = a.args.first() {
                    return Some(t);
                }
            }
        }
    }
    None
}

#[proc_macro_attribute]
pub fn axiom_export(_attr: TokenStream, item: TokenStream) -> TokenStream {
    let func = parse_macro_input!(item as ItemFn);
    match expand(func) {
        Ok(ts) => ts,
        Err(e) => e.to_compile_error().into(),
    }
}

fn expand(func: ItemFn) -> Result<TokenStream, syn::Error> {
    let name = func.sig.ident.clone();
    let shim = format_ident!("axffi_{}", name);

    if func.sig.asyncness.is_some() {
        return Err(syn::Error::new_spanned(
            &func.sig,
            "an `async fn` cannot be exported: Axiom has no threads, no \
             scheduler and no async (MM-PAR-1). Export a blocking wrapper, \
             or drive a runtime behind an opaque handle.",
        ));
    }
    if !func.sig.generics.params.is_empty() {
        return Err(syn::Error::new_spanned(
            &func.sig.generics,
            "an exported function must be monomorphic: an Axiom `extern` \
             may not be polymorphic, because a polymorphic Axiom function \
             grows a hidden trailing evidence word (codegen.ax:3008-3021) \
             that must never reach Rust.",
        ));
    }

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
                    "an exported function may not take `self`; export a free \
                     function that takes the handle as its first argument",
                ))
            }
        };
        let wire = classify(&pt.ty)
            .map_err(|m| syn::Error::new_spanned(&pt.ty, m))?;
        let w = format_ident!("a{}", i);
        shim_params.push(quote! { #w: ::axiom_ffi::AxWord });

        let ty = &pt.ty;
        match wire {
            Wire::Int => {
                call_args.push(quote! { #w as _ });
            }
            Wire::Float => {
                call_args.push(quote! { f64::from_bits(#w as u64) });
            }
            Wire::Bool => {
                call_args.push(quote! { #w != 0 });
            }
            Wire::StrRef => {
                let v = format_ident!("s{}", i);
                prologue.push(quote! {
                    // SAFETY: the caller is generated Axiom glue, which
                    // holds the String live across the call.
                    let #v = unsafe { ::axiom_ffi::AxStr::from_raw(#w) };
                    let #v = match #v.as_str() {
                        Ok(s) => s,
                        Err(_) => return ::axiom_ffi::AX_ERR,
                    };
                });
                call_args.push(quote! { #v });
            }
            Wire::BytesRef => {
                let v = format_ident!("s{}", i);
                prologue.push(quote! {
                    let #v = unsafe { ::axiom_ffi::AxStr::from_raw(#w) }.as_bytes();
                });
                call_args.push(quote! { #v });
            }
            Wire::Opaque => {
                // `AxOpaque::<T>` needs the POINTEE, so peel the `&`.
                let (base, is_mut) = peel(ty);
                if is_mut {
                    call_args.push(quote! {
                        unsafe { ::axiom_ffi::AxOpaque::<#base>::borrow_mut(#w) }
                    });
                } else {
                    call_args.push(quote! {
                        unsafe { ::axiom_ffi::AxOpaque::<#base>::borrow(#w) }
                    });
                }
            }
            Wire::OwnedBytes | Wire::Unit => {
                return Err(syn::Error::new_spanned(
                    ty,
                    "this type may not appear in argument position; pass \
                     `&str` or `&[u8]` instead",
                ))
            }
        }
    }

    // ---- return -----------------------------------------------------
    let ret_ty: Option<&Type> = match &func.sig.output {
        ReturnType::Default => None,
        ReturnType::Type(_, t) => Some(&**t),
    };

    let fallible = ret_ty.and_then(result_ok_type);
    let effective = fallible.or(ret_ty);
    let wire = match effective {
        None => Wire::Unit,
        Some(t) => classify(t).map_err(|m| syn::Error::new_spanned(t, m))?,
    };

    let vis = &func.vis;
    let body_call = quote! { #name(#(#call_args),*) };

    let shim_fn = if fallible.is_some() {
        // status in the return, payload in the out-cell
        let store_ok = store_payload(wire);
        quote! {
            #[no_mangle]
            #vis extern "C" fn #shim(#(#shim_params,)* out: ::axiom_ffi::AxWord)
                -> ::axiom_ffi::AxStatus
            {
                #(#prologue)*
                let cell = unsafe { ::axiom_ffi::AxOutCell::from_word(out) };
                match #body_call {
                    Ok(v) => { #store_ok ::axiom_ffi::AX_OK }
                    Err(e) => {
                        let msg = ::axiom_ffi::__private::error_bytes(&e);
                        cell.payload = msg.0;
                        cell.extra = msg.1;
                        ::axiom_ffi::AX_ERR
                    }
                }
            }
        }
    } else if wire == Wire::OwnedBytes {
        quote! {
            #[no_mangle]
            #vis extern "C" fn #shim(#(#shim_params,)* out: ::axiom_ffi::AxWord)
                -> ::axiom_ffi::AxStatus
            {
                #(#prologue)*
                let cell = unsafe { ::axiom_ffi::AxOutCell::from_word(out) };
                let v = #body_call;
                let (p, n) = ::axiom_ffi::__private::leak_bytes(v.into());
                cell.payload = p;
                cell.extra = n;
                ::axiom_ffi::AX_OK
            }
        }
    } else {
        let conv = return_conv(wire);
        quote! {
            #[no_mangle]
            #vis extern "C" fn #shim(#(#shim_params),*) -> ::axiom_ffi::AxWord {
                #(#prologue)*
                let v = #body_call;
                #conv
            }
        }
    };

    Ok(quote! { #func #shim_fn }.into())
}

fn return_conv(w: Wire) -> proc_macro2::TokenStream {
    match w {
        Wire::Int => quote! { v as ::axiom_ffi::AxWord },
        Wire::Float => quote! { v.to_bits() as ::axiom_ffi::AxWord },
        Wire::Bool => quote! { if v { 1 } else { 0 } },
        Wire::Opaque => quote! { ::axiom_ffi::__private::leak_opaque(v) },
        Wire::Unit => quote! { { let _ = v; 0 } },
        _ => quote! { compile_error!("unreachable return shape") },
    }
}

fn store_payload(w: Wire) -> proc_macro2::TokenStream {
    match w {
        Wire::Int => quote! { cell.payload = v as ::axiom_ffi::AxWord; },
        Wire::Float => quote! { cell.payload = v.to_bits() as ::axiom_ffi::AxWord; },
        Wire::Bool => quote! { cell.payload = if v { 1 } else { 0 }; },
        Wire::Opaque => quote! { cell.payload = ::axiom_ffi::__private::leak_opaque(v); },
        Wire::Unit => quote! { cell.payload = 0; },
        Wire::OwnedBytes => quote! {
            let (p, n) = ::axiom_ffi::__private::leak_bytes(v.into());
            cell.payload = p;
            cell.extra = n;
        },
        Wire::StrRef | Wire::BytesRef => quote! {
            compile_error!("a borrowed view may not be returned");
        },
    }
}
