# The agent harness

Use the compiler's diagnostic and symbol streams to inspect a program.
`axiom check` verifies it; `axiom symbols` reports what it declares.

```bash
axiom --diagnostic-format=ai check Main.ax
axiom --diagnostic-format=ai symbols Main.ax --calls
axiom --diagnostic-format=ai symbols Main.ax --mir --axir > Main.axir
```

AXDL is one line per diagnostic, with stable codes, spans and optional
byte-range fixes. AXSYM is one line per declaration, with its type,
stable node ID, tags, effects and optional call edges. See
[diagnostics](diagnostics.md) for the grammar and
[compiler inspection](compiler-guide.md#mir-and-axir) for AXIR.

## 1. Read compiler output

An AXTAG such as `;@axiom:agent:readonly` is recorded on a declaration.
`symbols` includes tags from imported modules and attributes them to
their declaring file. `Agent.Tags` parses all eight symbol kinds;
`symTag` reads an author's tag and `symEffects` the compiler's row.
The compiler stores `agent:*` tags but does not grant or enforce
permissions through them. Your tool decides what they mean.

`--calls` shows the edges used by effect inference. An unresolved
indirect call marks the row `#effects-incomplete`; it is a lower bound,
not a proof that an effect is absent. `--mir` adds region facts, with
`#mir-incomplete` or `#mir-truncated` when a summary is incomplete.
It forces a dataflow pass, so use it when those facts are needed.

Tested by `scripts/check-tools-selfhost.sh`,
`scripts/check-agent-calls.sh` and `scripts/check-mir-projection.sh`.

## 2. Decide what a warning means

A refuted effect or restriction claim is an error (`AX3010` or
`AX3049`). When a call through a stored function makes the claim
unverifiable, the compiler reports a warning. Add `strict` to a
restriction when an unknown answer must refuse the build.

`tests/diagnostics/severity.policy` is the checked allowlist of codes
permitted to render as warnings: `AX3037`, `AX3038`, `AX3039`,
`AX3043`, `AX3045`, `AX3046`, `AX3048`, `AX3051`, `AX3053` and
`AX3074`.

The same file records why each warning remains one. Diagnostic
severity and the policy gate are separate: a warning can still fail
your own gate. A diagnostic always keeps its code and span across
the human, AXDL and JSON renderings.

Tested by `scripts/check-diagnostics.sh` and
`scripts/check-doc-drift.sh`.

## 3. Choose a safe boundary

The checked Axiom AST is an internal set of word records. There is no
stable, typed public AST façade. A program can import compiler modules
with `AXIOM_PATH=self_host`, but those record layouts are internal.
For a stable read-only view, use AXSYM and AXIR.

### 3.4 Agent.Policy

`scripts/check-agent-policy.sh` compares the standard library's
derived effect rows with `tests/agent/stdlib-effects.allow`. It
rejects an unlisted effect or an incomplete row unless that row has a
recorded exception. The gate also plants changes to prove its checks
can fail. A project can use the same method with its own allowlist;
there is no `--agent-harness` compiler mode.

AXSYM can contain absolute paths. Normalise them before storing a
policy artifact for use in another checkout. Pin `AXIOM_PATH`,
`AXIOM_STDLIB`, compiler build ID and target when comparing runs.

### 3.5 Body and call views

`#calls=` names resolved declarations, including builtins. A bare
function reference counts as an edge because effect inference also
counts it. `symbols --axir --mir` can include a verified SSA body for
a function the MIR lowering supports. A record without a body gives
no body-level claim. Native compilation still uses the checked AST
backend.

Tested by `scripts/check-agent-calls.sh` and
`scripts/check-mir-roundtrip.sh`.

## 4. Check a generated edit

Apply an AXDL `~>` fix as a byte-range edit, then run `axiom check`
on the resulting source. Run `axiom fmt --check` when formatting
matters. An agent-written `effect`, `restrict` or `precondition` tag
has the same compiler checks as a human-written one. A string in an
`agent:*` tag alone supplies no permission or safety proof.

## 5. Macro expansion

Macros rewrite syntax during compilation; they do not run arbitrary
program code. The `syntax/*` query vocabulary is closed. Expansion
has depth, size and declaration-count limits. Generated declaration
names can still collide with written ones and report `AX3006`.
See the [macro rules](macro-system.md) and
`tests/diagnostics/401-decl-macro-size-limit.ax`.

## 6. Limits

- Effects through function values stored in memory may be unknown.
  `#effects-incomplete`, `AX3037` and `AX3038` expose that boundary.
- `Agent.Tags` reads metadata; it does not validate a policy by itself.
- AXSYM and AXIR do not turn the internal AST into a stable plugin API.
- The emitted runtime carries no harness telemetry. Measure in a build
  gate or an application-specific test instead.

## 7. Checks

| Claim | Gate |
|---|---|
| Tags survive formatting, import and AXSYM | `scripts/check-tools-selfhost.sh` |
| False effect claims fail and unknown ones warn | `scripts/check-diagnostics.sh` |
| The stdlib effect allowlist catches a planted change | `scripts/check-agent-policy.sh` |
| Calls explain derived effect rows | `scripts/check-agent-calls.sh` |
| Region summaries and AXIR records agree with their source | `scripts/check-mir-projection.sh`, `scripts/check-mir-roundtrip.sh` |

See also: [language reference](reference.md),
[diagnostics](diagnostics.md) and [compiler inspection](compiler-guide.md).
