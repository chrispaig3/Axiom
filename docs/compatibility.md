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

It does not prove the number is **earned**. Before `0.4.0`, every gate
in this repository stayed green while a public name changed its type,
widened its effect row, or stopped existing. A consumer pinning
`0.3.1` and moving to `0.3.2` had nothing but a changelog entry
somebody remembered to write.

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

**COMPAT-3 (H, with a recorded hole).** Thirteen public names are
outside the symbol stream: twelve macros — `println` and `format` among
them — and one effect declaration. `self_host/symbols.ax` has no arm
for `TAG_D_MACRO` and none for `TAG_D_IMPL`, and its `TAG_D_EFFECT` arm
registers the effect's operations rather than the effect.

They are listed in `compat/UNCOVERED` and compared as a **set**, not a
count: a fourteenth invisible name fails the gate, and closing the hole
is that file becoming empty. A count would let one name leave the
stream while another joined it.

**What is deliberately NOT in the surface.** `#calls=` is the graph
*behind* the effect row, not part of the promise — a function may
reorganise its callees freely. `file:line:col` is not either: a
contract does not move when a declaration moves down its file.

---

## 3. What a version number promises

Axiom is `0.x`, and says what that means rather than leaving it to
convention.

| Change | Patch `0.3.1 → 0.3.2` | Minor `0.3.x → 0.4.0` |
|---|---|---|
| a public name is added | allowed | allowed |
| an effect row narrows | allowed | allowed |
| a public name is removed | **refused** | allowed, **declared** |
| a signature changes | **refused** | allowed, **declared** |
| an effect row widens | **refused** | allowed, **declared** |

**COMPAT-4 (H).** A breaking change is allowed, and only when somebody
wrote down that they meant it. `compat/BREAKING` names each one against
the version that makes it; an undeclared one fails the gate.

That is the whole enforcement, and it is deliberately small. The gate
does not decide whether a break is wise. It decides that a break is
**deliberate**, which is the part a machine can check and the part that
was missing.

**COMPAT-5 (H).** Adding a public name is not a breaking change, and
the gate has a probe that must stay green to prove it. A gate that
reddens on every difference is a freeze, not a contract — it would make
adding a function to the standard library a breaking change.

---

## 4. What is not promised

Said out loud rather than left unstated:

- **The compiler's own internals.** `self_host/` is not a library.
  Nothing in `compat/` covers it.
- **The IR.** Emitted LLVM text is not a function of source and flags
  alone (`docs/agent-harness.md`), and nothing pins its shape.
- **`Sys/Platform` per-target values.** The three platform files
  declare the same names, and the baseline folds them to one entry, so
  the surface is identical on all three CI legs. The *values* behind
  those names are a target's, not a promise.
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

The gate compares against the **newest** baseline under `compat/`, and
refuses one that is modified in the working tree — a baseline
regenerated by the run that checks it agrees with itself by
construction, which is no check at all.
