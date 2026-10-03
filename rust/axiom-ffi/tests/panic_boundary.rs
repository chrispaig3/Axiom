//! A panic must terminate the process before a wire status reaches Axiom.

use axiom_ffi::{axiom_export, axiom_opaque, AxOutCell, AxWord};

#[axiom_export]
/// Panic from a scalar-returning export.
pub fn panicking_scalar() -> i64 {
    panic!("panic boundary probe: scalar")
}

#[axiom_export]
/// A fallible return does not turn a panic into an error status.
pub fn panicking_result() -> Result<i64, String> {
    panic!("panic boundary probe: result")
}

#[axiom_opaque]
/// A destructor also runs inside an abort-on-unwind boundary.
pub struct PanickingDrop;

impl Drop for PanickingDrop {
    fn drop(&mut self) {
        panic!("panic boundary probe: drop")
    }
}

#[test]
fn panics_cannot_return_or_unwind() {
    if let Ok(case) = std::env::var("AXIOM_FFI_PANIC_CASE") {
        // If a shim were changed to C-unwind, this catcher would return
        // and the child would exit successfully, failing the parent.
        let _ = std::panic::catch_unwind(|| match case.as_str() {
            "scalar" => {
                axffi_panicking_scalar();
            }
            "result" => {
                let mut cell = AxOutCell {
                    payload: -1,
                    extra: -1,
                };
                // SAFETY: this cell is aligned, writable and exclusive
                // for the call, with the two words this result requires.
                unsafe { axffi_panicking_result(&mut cell as *mut AxOutCell as AxWord) };
            }
            "drop" => {
                let word = axiom_ffi::__private::leak_opaque(PanickingDrop);
                // SAFETY: return the pointer from leak_opaque exactly once.
                unsafe { axffi_panicking_drop_drop(word) };
            }
            _ => panic!("unknown panic probe"),
        });
        return;
    }
    for case in ["scalar", "result", "drop"] {
        let output = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "panics_cannot_return_or_unwind", "--nocapture"])
            .env("AXIOM_FFI_PANIC_CASE", case)
            .output()
            .unwrap();
        assert!(
            !output.status.success(),
            "panic returned through {case}: {output:?}"
        );
        assert!(
            String::from_utf8_lossy(&output.stderr).contains("panic boundary probe"),
            "{case}: {output:?}"
        );
    }
}
