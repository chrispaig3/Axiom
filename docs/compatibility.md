# Compatibility

What a version number promises, and what checks it.

This document is a policy, and like every other normative document here
each claim names the gate that holds it. A claim with no keeper is a
comment.

---

## 1. Why this exists

`scripts/check-version.sh` holds nineteen literals across sixteen files
to `VERSION`, each named with the count it must yield, plus the number
the built binary prints. That is a strong gate and it proves one thing:
the number is **stated** consistently.

It does not prove the number is **earned**. Before `0.3.2`, nothing in
this repository compared the public surface against what a PREVIOUS
release promised. One gate came close and is worth naming precisely,
because the difference is the whole point: `check-stdlib-api.sh`
regenerates `docs/stdlib-api.md` from the library and diffs it, so it
does see a name change type or stop existing — but it compares the
library against a document regenerated **from the same tree**, and it
has a bless path. A re-bless satisfies it by construction. It proves
the documentation matches the library; it cannot prove the library
matches a promise, because it has no memory of one.

So a consumer pinning `0.3.1` and moving to `0.3.2` had nothing but a
changelog entry somebody remembered to write.

`CHANGELOG.md`'s `0.2.0` release named the gap in its own Compatibility
section — *"a deprecation policy and a compatibility gate over the
symbol stream are the next release's work"*. This is that work.

---

## 2. What the public surface is

**COMPAT-1 (H).** The public surface of the standard library is every
name declared `pub` in one of the modules `compat/` covers, together
with its **type** and its **effect row**.

Both halves are load-bearing. A type says what a caller may pass and
what it gets back. An effect row says what the call may do — and since
`0.3.0` it is checked rather than claimed, so widening one is a real
change to what a caller can rely on.

*Kept by:* `scripts/check-compat.sh`, over
`axiom symbols --diagnostic-format=ai` joined with `pub` visibility
read from the source. Visibility is not in AXSYM, so the join is the
one `examples/axdoc/axdoc.ax` already makes for `docs/stdlib-api.md`;
the two must agree about what "public" means.

**COMPAT-2 (H).** A name's **identity** is its AXSYM `@nid`, and its
**contract** is everything else on the row.

This is measured, not assumed. The nid is location-independent — the
same hash comes back when a module is read from a different path — and
it is contract-independent: it did not move when a signature went from
`(Int -> Int)` to `(Int -> (Int -> Int))`. So a diff can separate *this
name is gone* from *this name changed* with no heuristic.

**COMPAT-3 (H, and the hole it recorded is CLOSED).** This rule used to
read: "Thirteen public names are outside the symbol stream: twelve
macros — `println` and `format` among them — and one effect
declaration. `self_host/symbols.ax` has no arm for `TAG_D_MACRO` and
none for `TAG_D_IMPL`, and its `TAG_D_EFFECT` arm registers the
effect's operations rather than the effect."

That was true until 2026-08-26, when `symbols.ax` gained a
`TAG_D_MACRO` arm and an arm recording an `(effect ...)` declaration's
own name. `compat/UNCOVERED` has been **empty** since, and says so in
its own header; `docs/diagnostics.md`'s KIND table now lists `M` and
`E` beside the other six. The rule below is what the emptiness is
worth.

The file is still **compared as a set**, not a count, and it stays in
the tree precisely because it is empty: an empty file is the assertion
that nothing has *left* the stream, which a deleted file could not
make. A count would let one name leave while another joined.

**What is deliberately NOT in the surface.** `#calls=` is the graph
*behind* the effect row, not part of the promise — a function may
reorganise its callees freely. `file:line:col` is not either: a
contract does not move when a declaration moves down its file.

---

## 3. What a version number promises

Axiom is `0.x`. SemVer's own §4 says that anything MAY change at any
time in `0.x`, and this project does not pretend otherwise: there is
one maintainer, no LTS branch, and `SECURITY.md` supports exactly the
newest release. So the version component is **not** what decides
whether a break is allowed.

**COMPAT-4 (H).** A breaking change is allowed at any bump, and only
when somebody wrote down that they meant it. `compat/BREAKING` names
each one against a version strictly newer than the baseline's — newer
rather than equal to `VERSION`, because a break lands *before* the
release carrying it is bumped, and a permit keyed on `VERSION` would
refuse every change the release exists to make until its last commit.

An undeclared break fails the gate. That is the whole enforcement, and
it is deliberately small: the gate does not decide whether a break is
wise, it decides that a break is **deliberate** — which is the part a
machine can check and the part that was missing.

| Change | Verdict |
|---|---|
| a public name is added | allowed, silently |
| an effect row narrows | allowed, silently |
| a public name is removed | allowed, **declared** |
| a signature changes | allowed, **declared** |
| a struct's fields are reordered or retyped | allowed, **declared** |
| a trait loses a method | allowed, **declared** |
| an effect row widens | allowed, **declared** |

**What the component signals**, which is guidance and not a gate:

- **patch** — the surface is unchanged, or a break is small enough that
  the declaration in `compat/BREAKING` is the whole migration note.
- **minor** — the surface changed in a way a consumer must read about
  before upgrading. The changelog entry is the migration note.

> **This section was wrong when it was written, and the correction is
> recorded rather than made quietly.** Its first version carried a
> table saying a *patch* bump **refuses** a breaking change and only a
> *minor* permits one. `scripts/check-compat.sh` never checked that,
> and could not have: it compares the declared version against the
> baseline's and has no notion of which component moved. So the
> document claimed a rule the gate did not hold — which is the exact
> defect this whole release exists to remove, in the one document
> describing it. The rule above is the one the gate actually enforces.

**COMPAT-5 (H).** Adding a public name is not a breaking change, and
the gate has a probe that must stay green to prove it. A gate that
reddens on every difference is a freeze, not a contract — it would make
adding a function to the standard library a breaking change.

**COMPAT-7 (H).** A name may be retired **gracefully**, and that path
needs no line in `compat/BREAKING`:

```
;@axiom:deprecated(use vecLen instead)
(pub :: oldLen (-> Int Int))
```

Removing a name is permitted outright when **the baseline row carried
`#deprecated=`** — that is, when the notice shipped in a previous
release. Such a difference is reported `RETIRED` rather than `REMOVED`
and is not breaking. Deprecating and removing in the same release does
**not** qualify, and the rule gets that right for free: the baseline
*is* the last release, so a notice added this cycle is not in it.

This costs no compiler change. The AXTAG key namespace is open by
design — an unknown key already parses, is recorded, and is re-emitted
on the AXSYM line, so `;@axiom:deprecated(...)` arrives as
`#deprecated=` with nothing to build. What the gate adds is the
reading.

The annotation is deliberately **not** contract. If it were, adding a
deprecation notice would read as a signature change and be refused as
breaking — which would make the graceful path the forbidden one. It is
carried in the baseline row and stripped before comparison.

*Kept by:* `scripts/check-compat.sh`'s deprecation probe, which plants
one removal and compares it against two baselines differing only in the
notice: with it `RETIRED` and zero breaking, without it `REMOVED`.

**The other half is a diagnostic.** A reference to a deprecated name
draws `AX3048`, a **warning**, quoting the tag's own text. So the
notice reaches a caller at the moment they use the name, and reaches
this gate at the moment someone removes it.

It is a warning by design and not as a staging step: the release that
*announces* a removal is the one release in which the callers must
still build. Promoting it would make deprecation and removal the same
event, which is the distinction the notice exists to draw.
`tests/diagnostics/severity.policy` records that reasoning beside the
code, and `497-deprecated-name.ax` is the fixture.

**COMPAT-6 (P).** At `1.0`, the component becomes enforceable: a break
declared against a version whose MINOR did not move should fail. The
arm is one comparison beside `declared_newer` in
`scripts/check-compat.sh`, and it is planned rather than built because
under `0.x` it would refuse releases this project intends to make.

---

## 4. What is not promised

Said out loud rather than left unstated:

- **The compiler's own internals.** `self_host/` is not a library.
  Nothing in `compat/` covers it.
- **The IR.** Emitted LLVM text is not a function of source and flags
  alone (`docs/agent-harness.md`), and nothing pins its shape.
- **`Sys/Platform` per-target values.** The four platform files
  (darwin, linux-x86_64, linux-aarch64, freebsd) declare the same
  names, and the baseline folds them to one entry, so the surface is
  identical on all three CI legs. The *values* behind those names are
  a target's, not a promise.
- **A registry, a lockfile, or version constraints.** A dependency is
  a path on this machine (`self_host/pkg.ax` states this deliberately).
  Nothing here changes that.
- **Windows.** Explicitly out until a customer needs it.

---

## 5. Cutting a release

`CONTRIBUTING.md` § *Cutting a release* is the procedure; this adds one
step to it.

1. Land the work on `trunk` and let CI go green.
2. `scripts/bump-version.sh <X.Y.Z>`.
3. **Generate the new baseline** and commit it beside the old one:

   ```bash
   python3 tests/compat/verify-compat.py generate \
       ./.axiom-bin/axiom "$(mktemp -d)" ./stdlib > compat/<X.Y.Z>.axsym
   ```

   The previous baseline stays. The history is the point: it is what a
   consumer moving between two versions actually diffs.
4. Write the `CHANGELOG.md` entry, run the battery, push, tag.

The gate compares against the **newest** baseline under `compat/`. So
the moment step 3 lands, the baseline becomes the version just
released, and no break can be declared until the next bump — you must
bump before you may break. That is the rule, not an accident of
ordering.

It also refuses a baseline that is modified in the working tree — a baseline
regenerated by the run that checks it agrees with itself by
construction, which is no check at all.
