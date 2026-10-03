//! Raw wire errors are refused before references or deallocations are formed.

use axiom_ffi::{axiom_export, axiom_opaque, AxVecRepr, AxWord};

#[axiom_export]
/// Add a shared vector's first word to a disjoint mutable vector.
pub fn mix_words(a: &mut [i64], b: &[i64]) -> i64 {
    a[0] += b[0];
    a[0]
}

#[axiom_export]
/// Write both disjoint mutable vectors.
pub fn mix_mut_words(a: &mut [i64], b: &mut [i64]) -> i64 {
    a[0] += b[0];
    b[0] += 1;
    a[0]
}

#[axiom_export]
/// Read a nested vector while updating a disjoint vector.
pub fn mix_nested_words(a: &mut [i64], b: &[&[i64]]) -> i64 {
    a[0] += b[0][0];
    a[0]
}

#[axiom_opaque]
/// An opaque value used by the aliasing probes.
pub struct Number(i64);

#[axiom_export]
/// Read one opaque value while updating another.
pub fn mix_handles(a: &mut Number, b: &Number) -> i64 {
    a.0 += b.0;
    a.0
}

fn vec_repr(words: &[i64]) -> AxVecRepr {
    AxVecRepr {
        len: words.len() as i64,
        cap: words.len() as i64,
        data: words.as_ptr(),
    }
}

fn vec_word(repr: &AxVecRepr) -> AxWord {
    repr as *const AxVecRepr as AxWord
}

fn mut_vec_repr(words: &mut [i64]) -> AxVecRepr {
    AxVecRepr {
        len: words.len() as i64,
        cap: words.len() as i64,
        data: words.as_mut_ptr(),
    }
}

#[test]
fn accept_disjoint_wire_borrows() {
    let mut a = [2i64];
    let b = [3i64];
    let ar = mut_vec_repr(&mut a);
    let br = vec_repr(&b);
    // SAFETY: each representation and its disjoint backing storage live
    // through the call. No Rust reference accesses `a` during the call.
    assert_eq!(unsafe { axffi_mix_words(vec_word(&ar), vec_word(&br)) }, 5);
    assert_eq!(a[0], 5);
    a[0] = 8;
    let ar = mut_vec_repr(&mut a);

    let outer = [vec_word(&br)];
    let outer_repr = vec_repr(&outer);
    // SAFETY: as above; the outer vector also keeps `br` live.
    let observed = unsafe { axffi_mix_nested_words(vec_word(&ar), vec_word(&outer_repr)) };
    assert_eq!(observed, 11);
    assert_eq!(a[0], 11);

    let mut x = Number(4);
    let y = Number(6);
    // SAFETY: the two opaque values are live and disjoint for the call.
    let observed = unsafe {
        axffi_mix_handles(
            &mut x as *mut Number as AxWord,
            &y as *const Number as AxWord,
        )
    };
    assert_eq!(observed, 10);

    let (ptr, n) = axiom_ffi::__private::leak_words(vec![1, 2]);
    // SAFETY: return exactly the allocation pair once.
    let observed = unsafe { axiom_ffi::axffi_free_words(ptr as *mut i64, n) };
    assert_eq!(observed, 0);
    // SAFETY: an empty buffer has no allocation to return.
    let observed = unsafe { axiom_ffi::axffi_free_bytes(core::ptr::null_mut(), 0) };
    assert_eq!(observed, 0);
}

#[test]
fn reject_invalid_wire_borrows() {
    if let Ok(case) = std::env::var("AXIOM_FFI_CONTRACT_CASE") {
        let words = [2i64, 3, 4];
        let a = vec_repr(&words);
        let same = vec_repr(&words);
        let overlapping = vec_repr(&words[1..]);
        let outer = [vec_word(&a)];
        let nested = vec_repr(&outer);
        let mut x = Number(1);
        let xword = &mut x as *mut Number as AxWord;
        // SAFETY: fault injection targets checks that must abort before
        // constructing an invalid reference or deallocating a buffer.
        // All headers inspected by the alias checks remain live.
        unsafe {
            match case.as_str() {
                "same_vec" => {
                    axffi_mix_words(vec_word(&a), vec_word(&a));
                }
                "same_storage" => {
                    axffi_mix_words(vec_word(&a), vec_word(&same));
                }
                "overlap" => {
                    axffi_mix_words(vec_word(&a), vec_word(&overlapping));
                }
                "two_mutable" => {
                    axffi_mix_mut_words(vec_word(&a), vec_word(&a));
                }
                "nested" => {
                    axffi_mix_nested_words(vec_word(&a), vec_word(&nested));
                }
                "opaque" => {
                    axffi_mix_handles(xword, xword);
                }
                "negative_bytes" => {
                    axiom_ffi::axffi_free_bytes(core::ptr::null_mut(), -1);
                }
                "negative_words" => {
                    axiom_ffi::axffi_free_words(core::ptr::null_mut(), -1);
                }
                "null_words" => {
                    axiom_ffi::axffi_free_words(core::ptr::null_mut(), 1);
                }
                "huge_words" => {
                    axiom_ffi::axffi_free_words(core::ptr::dangling_mut(), i64::MAX);
                }
                "huge_strings" => {
                    axiom_ffi::axffi_free_str_list(core::ptr::dangling_mut(), i64::MAX);
                }
                "huge_lists" => {
                    axiom_ffi::axffi_free_word_lists(core::ptr::dangling_mut(), i64::MAX);
                }
                "negative_lists" => {
                    axiom_ffi::axffi_free_word_lists(core::ptr::null_mut(), -1);
                }
                _ => panic!("unknown fault injection case"),
            }
        }
        panic!("fault injection was accepted: {case}");
    }
    for (case, message) in [
        ("same_vec", "alias mutable Vec words"),
        ("same_storage", "alias mutable Vec words"),
        ("overlap", "alias mutable Vec words"),
        ("two_mutable", "alias mutable Vec words"),
        ("nested", "alias mutable Vec words"),
        ("opaque", "alias a mutable handle"),
        ("negative_bytes", "buffer length is negative"),
        ("negative_words", "buffer length is negative"),
        ("null_words", "invalid buffer address or alignment"),
        ("huge_words", "buffer length exceeds the address space"),
        ("huge_strings", "buffer length exceeds the address space"),
        ("huge_lists", "buffer length exceeds the address space"),
        ("negative_lists", "buffer length is negative"),
    ] {
        let out = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "reject_invalid_wire_borrows", "--nocapture"])
            .env("AXIOM_FFI_CONTRACT_CASE", case)
            .output()
            .unwrap();
        assert_eq!(out.status.code(), Some(73), "{case}: {out:?}");
        assert!(
            String::from_utf8_lossy(&out.stderr).contains(message),
            "{case}: {out:?}"
        );
    }
}
