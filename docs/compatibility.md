# Compatibility

This page says what an Axiom version number promises about the
standard library, and how `scripts/check-compat.sh` checks each
promise. Every rule names the check that keeps it.

In short:

- Adding a public name is always allowed.
- Removing or changing a public name is allowed at any version, as long
  as `compat/BREAKING` declares it.
- A name that shipped with a deprecation notice in an earlier release
  can be removed without a declaration.

<a id="1-why-this-exists"></a>
## How the check works

`scripts/check-version.sh` checks that the version number is stated
consistently. `scripts/check-stdlib-api.sh` checks that
`docs/stdlib-api.md` matches the library. Neither remembers a previous
release: the second compares the library against a page regenerated
from the same tree, and a re-bless satisfies it.

`scripts/check-compat.sh` compares the standard library's public
surface against a baseline from the last release, stored as
`compat/<X.Y.Z>.axsym`. It classifies every difference, and a breaking
difference fails unless it is declared.

<a id="2-what-the-public-surface-is"></a>
## What the public surface is

**COMPAT-1 (H).** The public surface of the standard library is every
name declared `pub` in one of the modules `compat/` covers, together
with its type and its effect row.

Both parts matter. The type says what a caller can pass and what comes
back. The effect row says what the call may do, and the compiler checks
it, so widening one changes what a caller can rely on.

*Kept by:* `scripts/check-compat.sh`, which reads
`axiom symbols --diagnostic-format=ai` and joins it with `pub`
visibility read from the source. AXSYM doesn't carry visibility, so the
check makes the same join `examples/axdoc/axdoc.ax` makes for
`docs/stdlib-api.md`. The two must agree about what "public" means.

**COMPAT-2 (H).** A name's identity is its AXSYM `@nid`, and its
contract is everything else on the row.

The nid doesn't depend on location: reading a module from a different
path gives the same hash. It doesn't depend on the contract either: it
stays the same when a signature changes from `(Int -> Int)` to
`(Int -> (Int -> Int))`. So a diff can tell "this name is gone" from
"this name changed" without guessing.

The nid is unique within one comparison, not across modules, so a tool
that joins two streams must not assume it is unique. It is FNV-1a 64
over `DKind:name`, using the bare name, so two modules that declare the
same unmangled name get the same nid. For example,
`axiom symbols self_host/main.ax --builtins --diagnostic-format ai`
gives two different functions named `die`, one in `stdlib/IO.ax` and
one in `self_host/main.ax`, the same nid, `@52fb9ccad9feab1b`. The same
happens to `jsonHexDigit` in `self_host/render.ax` and `stdlib/Json.ax`.

That doesn't weaken this rule, because `check-compat.sh` compares one
library against a baseline of the same library. It does matter to
anything that joins AXSYM to another stream. [MIR design](mir-design.md)
§3 joins `.axir` records to AXSYM rows on the whole header tuple (name,
location, quoted type and nid) for this reason.
`scripts/check-mir-projection.sh` checks that the two tuple sequences
are equal, in order, instead of looking the nid up.

**COMPAT-3 (H).** Every public name has a row in the symbol stream,
macros and effect declarations included. `self_host/symbols.ax`
records each macro and each `(effect ...)` declaration's own name, and
[diagnostics.md](diagnostics.md) lists their AXSYM kinds, `M` and `E`.

`compat/UNCOVERED` lists public names the stream doesn't carry, and it
is empty. The file stays, and the check compares it as a set, not a
count. An empty file asserts that no name has left the stream, which a
deleted file couldn't. A count would let one name leave while another
joined.

### What isn't part of the surface

- **`#calls=`** is the call graph behind the effect row. A function can
  reorganise its callees freely.
- **`file:line:col`** isn't either. A contract doesn't change when a
  declaration moves down its file.
- **Any `#mir-*` key.** `CONTRACT_META` in
  `tests/compat/verify-compat.py` is an explicit allowlist, and `#mir-`
  isn't on it, so a dataflow summary that widens or narrows isn't a
  compatibility event. That's the right default while the facts behind
  it are a lower bound with two sentinels on it ([MIR
  design](mir-design.md) §4.1). Whether `#mir-escapes=` should become
  contract, as `#effects=` is, is a later decision, and it needs the
  round-cap fix first.

<a id="3-what-a-version-number-promises"></a>
## What a version number promises

Axiom is `0.x`. SemVer §4 says anything may change at any time in
`0.x`, and we don't pretend otherwise. There is one maintainer and no
LTS branch, and [SECURITY.md](../SECURITY.md) supports one minor line
at a time, the newest. So the version component doesn't decide whether
a break is allowed. A declaration does.

**COMPAT-4 (H).** A breaking change is allowed at any bump, but only
when someone wrote down that they meant it. `compat/BREAKING` names
each break against a version strictly newer than the baseline's.

The version is compared with the baseline's, not with `VERSION`,
because a break lands before the release that carries it is bumped. A
permit keyed on `VERSION` would refuse every change the release exists
to make until its last commit.

An undeclared break fails the check. The check doesn't judge whether a
break is wise. It checks that the break was intended.

| Change | Verdict |
|---|---|
| a public name is added | allowed, silently |
| an effect row narrows | allowed, silently |
| a public name is removed | allowed, **declared** |
| a signature changes | allowed, **declared** |
| a struct's fields are reordered or retyped | allowed, **declared** |
| an effect row widens | allowed, **declared** |

### Declare a breaking change

Add one line to `compat/BREAKING`, with whitespace between the fields:

```text
<version>  <kind-letter>  <name>  <why>
```

The kind letter is the row's AXSYM `KIND`, such as `F` for a function
or `M` for a macro. [diagnostics.md](diagnostics.md) lists them all.
This line declared one of the `0.3.3` breaks:

```text
0.3.3  F  writeFile   -errno -> (Result Int Error): the failure is in the type
```

### What the version component signals

This is guidance. The check compares the declared version with the
baseline's and doesn't look at which component moved.

- **Patch:** the surface is unchanged, or a break is small enough that
  its line in `compat/BREAKING` is the whole migration note.
- **Minor:** the surface changed in a way a consumer must read about
  before upgrading. The changelog entry is the migration note.

### Adding names

**COMPAT-5 (H).** Adding a public name is not a breaking change. A
check that failed on every difference would freeze the library, and
adding a function to it would count as a break.

*Kept by:* a probe in `scripts/check-compat.sh` that adds a public name
and must see it reported `ADDED`, not breaking.

### Retire a name gracefully

**COMPAT-7 (H).** You can retire a name gracefully, with no line in
`compat/BREAKING`. First, mark it deprecated and ship a release:

```scheme
;@axiom:deprecated(use vecLen instead)
(pub :: oldLen (-> Int Int))
(pub fn (oldLen v)
  0)

(:: main Int)
(fn (main)
  (oldLen 7))
```

Callers still compile, and each use draws warning `AX3048`, quoting the
tag's text:

```text
warning[AX3048]: `oldLen` is deprecated
 --> retire.ax:8:4
  |
8 |   (oldLen 7))
  |    ^^^^^^ declared `;@axiom:deprecated(use vecLen instead)`
```

In a later release, you can remove the name outright. The removal is
allowed when the baseline row carried `#deprecated=`, which means the
notice shipped in an earlier release. The check reports it as `RETIRED`
instead of `REMOVED`, and it isn't breaking. Deprecating and removing
in the same release doesn't qualify: the baseline is the last release,
so a notice added this cycle isn't in it.

The check needs no compiler change to see the notice. The AXTAG key
namespace is open: an unknown key parses, is recorded and is re-emitted
on the AXSYM line, so `;@axiom:deprecated(...)` arrives as
`#deprecated=`. The check adds the reading.

The annotation isn't part of the contract. If it were, adding a notice
would look like a signature change and be refused as breaking, which
would forbid the graceful path. The baseline row carries it, and the
check strips it before comparing.

*Kept by:* the deprecation probe in `scripts/check-compat.sh`. It plants
one removal and compares it against two baselines that differ only in
the notice. With the notice, the result is `RETIRED` with nothing
breaking. Without it, the result is `REMOVED`.

`AX3048` is a warning by design, not a step towards an error. The
release that announces a removal is the one release in which callers
must still build, and making it an error would make deprecation and
removal the same event. The notice reaches callers when they use the
name, and reaches the check when someone removes it.
`tests/diagnostics/severity.policy` records this reasoning beside the
code.

Tested by `tests/diagnostics/497-deprecated-name.ax`.

### At 1.0

**COMPAT-6 (P).** At `1.0`, the version component becomes enforceable:
a break declared against a version whose minor didn't move should fail.
It is one comparison beside `declared_newer` in
`scripts/check-compat.sh`. It's planned, not built, because under `0.x`
it would refuse releases we intend to make.

<a id="4-what-is-not-promised"></a>
## What isn't promised

- **The compiler's internals.** `self_host/` is not a library, and
  nothing in `compat/` covers it.
- **The IR.** Emitted LLVM text isn't a function of source and flags
  alone ([agent harness](agent-harness.md)), and nothing pins its shape.
- **`Sys/Platform` per-target values.** The per-target
  `Sys/Platform` files declare the same names, and the baseline folds
  them into one entry, so the surface is the same on every target. The
  values behind those names belong to each target and aren't promised.
- **A registry, a lockfile or version constraints.** A dependency is a
  path on your machine (`self_host/pkg.ax` states this), and so is a
  `crate`, a native dependency. This policy doesn't change that. A
  lockfile isn't a step towards a fetcher either: over a path you
  already control, a digest protects nothing and changes on every edit
  of your own code.
- **Windows as a host.** The compiler doesn't run on Windows, although
  `windows-x86_64` is a supported target.

<a id="5-cutting-a-release"></a>
## Cut a release

[Cutting a release](../CONTRIBUTING.md#cutting-a-release) in
CONTRIBUTING.md is the full procedure. Compatibility adds step 3:

1. Land the work on `trunk` and let CI go green.
2. Run `scripts/bump-version.sh <X.Y.Z>`.
3. Generate the new baseline and commit it beside the old ones:

   ```bash
   python3 tests/compat/verify-compat.py generate \
       ./.axiom-bin/axiom "$(mktemp -d)" ./stdlib > compat/<X.Y.Z>.axsym
   ```

   Keep the previous baselines. They are what a consumer moving between
   two versions diffs.
4. Write the `CHANGELOG.md` entry, run the test battery, push and tag.

The check compares against the newest baseline under `compat/`. Once
step 3 lands, the baseline is the version you just released, and no
break can be declared until the next bump. Bump first, then break.

The check also refuses a baseline that is modified in the working tree.
A baseline regenerated by the run that checks it always agrees with
itself, so it would check nothing.

## See also

- [compat/README.md](../compat/README.md): the baselines and the
  files the check reads.
- [diagnostics.md](diagnostics.md): the AXSYM format.
- [stdlib-api.md](stdlib-api.md): the standard library's public names.
