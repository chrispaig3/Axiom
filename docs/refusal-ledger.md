# Refusal ledger

Every error the compiler reports, classified by the invariant it
protects, and the decisions taken on the refusals in question.
`explain --list` reports 92 codes: 81 errors and 11 warnings. The
classes come from probing the compiler, not from reading the code.
The probes are in the audit work in this file's history, and each
decided case names the test that pins it.

- **S**: required for soundness, memory safety or valid semantics. 66
  codes, all retained.
- **T**: a real target or ABI limitation. 4 codes, all retained:
  `AX3026` (runtime symbol reservation), `AX3036` (one-word FFI
  boundary), `AX4003` (toolchain ran) and `AX4006` (thread lowering).
- **M**: a missing implementation. 7 codes plus 9 secondary arms.
  Each names a real program that is refused today.
- **O**: obsolete or over-broad. 4 codes plus 9 secondary arms. Each
  names a real program refused without a soundness reason.

## Decided

Items marked *specified* are designed in the
[type-system roadmap](roadmap-type-system.md) but not yet implemented.

| Refusal | Decision | Code and fixtures |
|---|---|---|
| Field read on a `data` value whose constructors don't all declare the field at the same word and type | Refuse, with `AX3070` extended on 2026-09-27. Three probed shapes misread at run time: another constructor's slot (answered 7), past a shorter block (SIGSEGV, exit 139), and a same-named field at different words (answered 7). The nullary arm is unchanged. | `self_host/typecheck.ax` (`checkField`, `dataAgreedFieldTy`); `tests/diagnostics/480-field-on-mixed-data.ax`, `tests/diagnostics/484-field-on-partial-data.ax`, `tests/selfhost/1003-data-field-agree.ax`; `docs/memory-model.md` MM-VAL-9a/11 |
| Bare `Vec`, `(Option Int String)` and other wrong-arity type constructors, in any position | Refuse at type resolution, with a new error beside `AX3002`. Today only a *use* fails, as `AX3004`. Specified. | Roadmap §1 |
| A custom effect escaping to an outer handler (a `handle` body performs two custom effects) | Accept by propagation. An unnamed custom effect stays in the residual row and dispatches outward, and `AX3053` still fires at `main`. The runtime already does this: hiding the call behind a field resolves to warnings and returns the outer handler's answer. Specified. | Roadmap §2 |
| Partial application, bare constructors and bare effect operations (`AX3013`, the `AX3009`/`AX3067` expression arms, `AX3017` arm c) | Accept as implicit eta-expansion to trailing holes. That is exactly the lambda `expandAppOrHole` already builds for `_`. Specified. | Roadmap §3 |
| Parameterised aliases (`(type Pairs (a) = (Vec a))`, unusable without `cast`) | Expand by substitution wherever unparameterised aliases already expand, or refuse the declaration. Specified. | Roadmap §4 |
| Nullary lambdas, scalar stores into regions, multi-effect and multi-operation handlers, qualified constructors, macro depth, dead-rule and literal lints, region shadowing, nested ellipsis, region allocation, generic rendering, capacity limits | Ranked by value and risk in Roadmap §§5–8. No change. | Roadmap |

## Retained without change

- `AX3045` stays a warning, because a program whose recursion is
  bounded is still correct.
- `AX2004`'s 13 removed spellings each have a supported replacement.
- These stay refused: `AX3047` (lowercase primitive names are type
  variables), `AX3036` (word-sized FFI), `AX3072` (`__addr` of a
  literal; `strData` covers the rest), `AX3040`'s uncalled-callback
  arm (a documented over-approximation), `AX4006`/`AX4007` target
  behaviour, and `AX3025` generic rendering (there is no runtime type
  information to spend).

We never count a warning downgrade, a suppressed error, an unchecked
cast or a permissive fallback type as support.
