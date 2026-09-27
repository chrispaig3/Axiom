# Refusal ledger

`explain --list` reports 92 codes: 81 errors, 11 warnings. Each error
below is classified by the invariant it protects, established by
probing the compiler in September 2026 rather than by reading the
code. Probes live beside this file's history in the 2026-09-27 audit
work; the fixtures column names the repo test that pins each decided
case.

- **S** — required for soundness, memory safety, or valid semantics.
  66 codes. Retained.
- **T** — a real target or ABI limitation. 4 codes: `AX3026`
  (runtime symbol reservation), `AX3036` (one-word FFI boundary),
  `AX4003` (toolchain ran), `AX4006` (thread lowering). Retained.
- **M** — a missing implementation. 7 codes plus 9 secondary arms.
  Each names a real program that is refused today.
- **O** — obsolete or over-broad. 4 codes plus 9 secondary arms.
  Each names a real program refused without a soundness reason.

## Decided

| Refusal | Decision | Code and fixtures |
|---|---|---|
| Field read on a `data` value whose constructors do not all declare the field at the same word and type | Refuse (`AX3070`, extended 2026-09-27). Three probed shapes misread at run time: another constructor's slot (answered 7), past a shorter block (SIGSEGV, exit 139), and a same-named field at different words (answered 7). The nullary arm is unchanged. | `self_host/typecheck.ax` (`checkField`, `dataAgreedFieldTy`); `tests/diagnostics/480-field-on-mixed-data.ax`, `tests/diagnostics/484-field-on-partial-data.ax`, `tests/selfhost/1003-data-field-agree.ax`; `docs/memory-model.md` MM-VAL-9a/11 |
| Bare `Vec`, `(Option Int String)`, wrong-arity type constructors in any position | Refuse at type resolution (new error beside `AX3002`). Today only a *use* fails, as `AX3004`. Specified, not yet implemented — see Roadmap. | Roadmap §1 |
| Custom effect escaping to an outer handler (`handle` body performs two custom effects) | Accept by propagation: an unnamed custom effect stays in the residual row and dispatches outward; `AX3053` still fires at `main`. The runtime already does this (hiding the call behind a field resolves to warnings and returns the outer handler's answer). Specified, not yet implemented — see Roadmap. | Roadmap §2 |
| Partial application / bare constructors / bare effect operations (`AX3013`, `AX3009`/`AX3067` expression arms, `AX3017` arm c) | Accept as implicit eta-expansion to trailing holes — the exact lambda `expandAppOrHole` already builds for `_`. Specified, not yet implemented — see Roadmap. | Roadmap §3 |
| Parameterised aliases (`(type Pairs (a) = (Vec a))`, unusable without `cast`) | Expand by substitution wherever unparameterised aliases already expand, or refuse the declaration. Specified, not yet implemented — see Roadmap. | Roadmap §4 |
| Nullary lambdas, scalar stores into regions, multi-effect/multi-operation handlers, qualified constructors, macro depth, dead-rule/literal lints, region shadowing, nested ellipsis, region allocation, generic rendering, capacity limits | Roadmap §§5–8 with value/risk rankings. No change. | Roadmap |

## Retained without change

`AX3045` is a warning (correct by bounded recursion). `AX2004`'s 13
removed spellings each have a supported replacement. `AX3047`
(lowercase primitive names are type variables), `AX3036` (word-sized
FFI), `AX3072` (`__addr` of a literal; `strData` covers the rest),
`AX3040`'s uncalled-callback arm (documented over-approximation),
`AX4006`/`AX4007` target behavior, and `AX3025` generic rendering
(no runtime type information to spend) all stay refused.

A warning downgrade, a suppressed error, an unchecked cast, or a
permissive fallback type is never counted as support. That rule is
what keeps this file honest.
