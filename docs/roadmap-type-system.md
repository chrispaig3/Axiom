# Type-system roadmap

Selected milestones are implemented and gated; the rest stay here
with their behavior, components, compatibility, and acceptance
specified — not in the implementation. No item here is claimed as
done. Ordering is value versus risk, re-derived from the 2026-09-27
refusal probes.

## §1. Type-constructor arity refusal (next)

**Behavior.** `(Option Int String)`, a bare `Vec`, `(Box Int Int Int)`
are refused at the declaration that writes them, with a new error
beside `AX3002` naming the expected and given counts. Only a *use*
fails today, as `AX3004` (`expected Option Int String, found Option
Int`).

**Components.** `self_host/typecheck.ax`: an arity table from entity
word 3 (type parameters) for `data`/`struct`, plus alias parameter
counts; one walker over `TAG_T_CON` nodes called from signature
validation (`tcCheckSigTypeOf`), struct/data field validation, alias
bodies, and extern items. New code (next free `AX3076`), `explain`
entry, `severity.policy` untouched (error). Primitives from
`typeKeywordCanon` have arity 0; `(Int String)` already parses as a
tuple and is unaffected.

**Compatibility.** Breaking only for programs that are wrong today:
nothing can inhabit `(Option Int String)`. Every current use-site
`AX3004` becomes a declaration-site error with a better span.

**Acceptance.** Fixture refused in all four positions; a correct
generic use (`(Vec Int)`, nested `(Option (Vec Int))`) still checks;
`check-diagnostics`, `check-self-host`, `check-stdlib-selfhost` green.

## §2. Custom effects escape to an outer handler

**Behavior.** A custom effect the body performs but the handle list
does not name stays in the form's residual row and dispatches to the
next enclosing handler. Built-ins keep the must-name rule. `AX3053`
still fires at `main`. Today no spelling handles a body performing
two custom effects: naming both is `AX3017`, nesting draws `AX3011`.

**Components.** `self_host/typecheck.ax` (`checkUnhandled`: skip the
`AX3011` emit for declared custom effects, keep them residual);
`docs/reference.md` Handling Effects; `explain AX3011`/`AX3017`;
fixtures 310/320 re-bless. No codegen change: hiding the call behind
a field already dispatches outward and returns the outer handler's
answer (33).

**Compatibility.** Strictly more programs accepted; every previously
refused two-effect body now compiles to the already-demonstrated
runtime behavior.

**Acceptance.** Nested two-effect body returns 33; single-effect
handlers unchanged; unhandled custom effect still refused at `main`;
effect gates (`check-effect-fixpoint`, agent-calls) green.

## §3. Implicit eta-expansion

**Behavior.** A top-level function of arity n referenced with k < n
arguments and no hole denotes `(f a1..ak _ … _)` — the lambda
`expandAppOrHole` already builds for holes. Same rule for
constructors (`AX3009`/`AX3067` arms) and effect operations
(`AX3017` arm c). `(vecSortBy v strCmp)` and `(vecMap v Some)` check.

**Components.** `self_host/expand.ax` (reuse `expandAppOrHole` with a
declaration-arity table) or typecheck rewrite at the five sites; the
effect walk reads the reference as a *possible* effect; `symbols`
`#calls=` and LSP spans; `docs/reference.md` Partial Application;
`explain AX3013/AX3009/AX3067/AX3017`; `stdlib/Vec.ax` comment;
fixtures 110/120/130/450/310. No codegen change.

**Compatibility.** Strictly more programs accepted; the hole
spellings keep their meaning exactly.

**Acceptance.** Each refused probe now checks and runs; hole controls
unchanged; effect rows of expanded references verified; no new
`AX3037` on previously precise rows.

## §4. Parameterised aliases

**Behavior.** `(Pairs T)` expands to `(Vec T)` by substitution at
every position unparameterised aliases already reach (signature,
struct field, data field, `fldClass`), or the declaration is refused
until that exists. Today every use is `AX3004`: no value can have the
type without a `cast`.

**Components.** Typecheck alias expansion, codegen `fldClass` flags,
`symbols` rendering, `docs/reference.md` Type Aliases (including the
`[String]` example, which currently draws `AX2003`).

**Compatibility.** Revives a dead feature; unparameterised aliases
unaffected.

**Acceptance.** Round-trip use checks and runs; recursive and
higher-order aliases behave like their expansions.

## §5. Guarded field reads (future; the refusal stands)

**Behavior.** `x.f` accepted when every constructor declaring `f`
puts it at the same word and type; the load checks block-ness and
tag, trapping with a dedicated status otherwise. Needs a new runtime
trap and status row. Until the guard exists, the extended refusal is
the sound rule.

## §6. Captured-`mut` auto-boxing (future)

**Behavior.** A `mut` local assigned inside a capturing lambda is
allocated as a one-field mutable cell; all reads and writes go
through it (the hand-written struct-cell shape, built by the
compiler). Touches closure conversion, reference counting of the
cell, region and parallel checks, `MM-MUT-1a`/`MM-VAL-16`, fixture
466.

## §7. Smaller relaxations (in order)

Nullary-lambda thunks (type-directed `(t)` application; the `(f)`≡`f`
rule is language-wide, so medium risk for low value); scalar stores
into regions (ignore `Int`/`Bool`/`Char`/`Float`/`Unit` in the escape
check, as `AX3059` already does — low risk); multi-effect and
multi-operation handlers (new evidence-record layout and syntax —
high risk); qualified constructors (`(Mod::T …)` in expression
position — low risk); macro depth 128→1024 or shrinking-only rounds
(`AX3024` still guards); `AX3033`/`AX3066` to warnings; region-name
shadowing as lexical shadowing; nested ellipsis (Scheme depth-n).

## §8. Deferred or declined

Region allocation into `@r` (needs design stage S4); generic
rendering (no runtime type information — prefer a library capability
record); FreeBSD threads (needs `libthr` and a CI leg); record and
evidence capacities (widest real declarations are 37 fields and 4
type variables; widening changes the shape-word ABI);
`AX3040`'s uncalled-callback arm (documented, negligible).
