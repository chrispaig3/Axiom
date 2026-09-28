# Type-system roadmap

The type-system changes we plan, ranked by value against risk from
the refusal probes recorded in the [refusal ledger](refusal-ledger.md).
Each item specifies its behaviour, components, compatibility and
acceptance. Implemented milestones leave this page, so nothing here
is done yet.

## §1. Type-constructor arity refusal (next)

**Behaviour.** The compiler rejects `(Option Int String)`, a bare
`Vec` and `(Box Int Int Int)` at the declaration that writes them. A
new error beside `AX3002` names the expected and given counts. Today
only a *use* fails, as `AX3004` (`expected Option Int String, found
Option Int`).

**Components.** `self_host/typecheck.ax` gets an arity table from
entity word 3 (type parameters) for `data` and `struct`, plus alias
parameter counts. One walker over `TAG_T_CON` nodes is called from
signature validation (`tcCheckSigTypeOf`), struct and data field
validation, alias bodies and extern items. The error takes the next
free code, `AX3076`, with an `explain` entry, and `severity.policy`
is untouched. Primitives from `typeKeywordCanon` have arity 0.
`(Int String)` already parses as a tuple and is unaffected.

**Compatibility.** This breaks only programs that are already wrong,
since nothing can inhabit `(Option Int String)`. Every current use-site
`AX3004` becomes a declaration-site error with a better span.

**Acceptance.** A fixture is refused in all four positions. A correct
generic use, such as `(Vec Int)` or nested `(Option (Vec Int))`, still
checks. `check-diagnostics`, `check-self-host` and
`check-stdlib-selfhost` pass.

## §2. Custom effects escape to an outer handler

**Behaviour.** When a body performs a custom effect that the handle
list doesn't name, the effect stays in the form's residual row and
dispatches to the next enclosing handler. Built-in effects keep the
must-name rule, and `AX3053` still fires at `main`. Today no spelling
handles a body that performs two custom effects: naming both draws
`AX3017`, and nesting draws `AX3011`.

**Components.** `self_host/typecheck.ax`: `checkUnhandled` skips the
`AX3011` emit for declared custom effects and keeps them residual.
The change also touches the [effects](reference.md#effects) section of
the reference and `explain AX3011` and `AX3017`, and re-blesses
fixtures 310 and 320.
Codegen doesn't change: hiding the call behind a field already
dispatches outward and returns the outer handler's answer (33).

**Compatibility.** Strictly more programs are accepted. Every
two-effect body that is refused today compiles to the runtime
behaviour already demonstrated.

**Acceptance.** The nested two-effect body returns 33. Single-effect
handlers are unchanged. An unhandled custom effect is still refused at
`main`. The effect gates (`check-effect-fixpoint`, agent-calls) pass.

## §3. Implicit eta-expansion

**Behaviour.** A top-level function of arity n, referenced with k < n
arguments and no hole, means `(f a1..ak _ … _)`. That is the lambda
`expandAppOrHole` already builds for holes. The same rule covers
constructors (the `AX3009` and `AX3067` arms) and effect operations
(`AX3017` arm c). `(vecSortBy v strCmp)` and `(vecMap v Some)` then
check.

**Components.**

- `self_host/expand.ax`, reusing `expandAppOrHole` with a
  declaration-arity table, or a typecheck rewrite at the five sites;
- the effect walk, which reads the reference as a *possible* effect;
- `symbols` `#calls=` and LSP spans;
- [partial application](reference.md#partial-application) in the
  reference, `explain AX3013`, `AX3009`, `AX3067` and `AX3017`, and
  the comment in `stdlib/Vec.ax`;
- fixtures 110, 120, 130, 450 and 310.

Codegen doesn't change.

**Compatibility.** Strictly more programs are accepted. The hole
spellings keep exactly their current meaning.

**Acceptance.** Each refused probe now checks and runs. The hole
controls are unchanged. Effect rows of expanded references are
verified. No new `AX3037` appears on rows that were precise before.

## §4. Parameterised aliases

**Behaviour.** `(Pairs T)` expands to `(Vec T)` by substitution at
every position that unparameterised aliases already reach: signature,
struct field, data field and `fldClass`. The alternative is to refuse
the declaration until that expansion exists. Today every use is `AX3004`, so no
value can have the type without a `cast`.

**Components.** Typecheck alias expansion, the codegen `fldClass`
flags, `symbols` rendering, and
[type aliases](reference.md#type-aliases) in the reference. That
section's `[String]` example currently draws `AX2003`.

**Compatibility.** Revives a dead feature. Unparameterised aliases are
unaffected.

**Acceptance.** A round-trip use checks and runs. Recursive and
higher-order aliases behave like their expansions.

## §5. Guarded field reads (future; the refusal stands)

**Behaviour.** `x.f` is accepted when every constructor that declares
`f` puts it at the same word with the same type. The load checks
block-ness and tag, and traps with a dedicated status otherwise. This
needs a new runtime trap and status row. Until the guard exists, the
extended refusal is the sound rule.

## §6. Captured-`mut` auto-boxing (future)

**Behaviour.** A `mut` local assigned inside a capturing lambda is
allocated as a one-field mutable cell, and every read and write goes
through it. This is the struct-cell shape people write by hand, built
by the compiler instead. It touches closure conversion, reference
counting of the cell, region and parallel checks,
`MM-MUT-1a`/`MM-VAL-16`, and fixture 466.

## §7. Smaller relaxations (in order)

1. Nullary-lambda thunks: type-directed `(t)` application. The
   `(f)`≡`f` rule is language-wide, so this is medium risk for low
   value.
2. Scalar stores into regions: ignore `Int`, `Bool`, `Char`, `Float`
   and `Unit` in the escape check, as `AX3059` already does. Low risk.
3. Multi-effect and multi-operation handlers: a new evidence-record
   layout and syntax. High risk.
4. Qualified constructors: `(Mod::T …)` in expression position. Low
   risk.
5. Macro depth 128→1024, or shrinking-only rounds. `AX3024` still
   guards.
6. `AX3033` and `AX3066` become warnings.
7. Region-name shadowing as lexical shadowing.
8. Nested ellipsis (Scheme depth-n).

## §8. Deferred or declined

- Region allocation into `@r`: needs design stage S4.
- Generic rendering: there is no runtime type information. Prefer a
  library capability record.
- FreeBSD threads: needs `libthr` and a CI leg.
- Record and evidence capacities: the widest real declarations are 37
  fields and 4 type variables, and widening changes the shape-word
  ABI.
- `AX3040`'s uncalled-callback arm: documented and negligible.
