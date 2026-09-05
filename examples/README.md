# Examples

Two programs. Each one is a real thing the repository uses rather than a
toy, and each one is the load-bearing artefact of a gate — which is the only
reason both still compile and still answer correctly across every compiler
change since they were written. An example CI does not run is an example
that has already rotted and has not been told.

`scripts/check-examples.sh` holds this table and the directory to each other
in both directions, so a third program cannot land without a row here and a
row cannot outlive its program. The count in the line above is part of the
table.

Run every command from the repository root.

| Example | What it teaches | Run it | Pinned by |
| --- | --- | --- | --- |
| [`examples/batch-fallible/batch-fallible.ax`](batch-fallible/batch-fallible.ax) | The `Fallible` effect: a parser six calls down performs `fallibleMalformed`, and the **loop** decides what happens — `fallibleSkip`, `(fallibleDefault d)`, or a counting handler around either — with no unwinding and **0 bytes a record** | `axiom run examples/batch-fallible/batch-fallible.ax [N [k]]` — defaults `1000000 7`; the three numbers it prints are checkable by the arithmetic in its own header | [`scripts/check-steady-state.sh`](../scripts/check-steady-state.sh) |
| [`examples/axdoc/axdoc.ax`](axdoc/axdoc.ax) | Reading a program's own public surface: `(pub :: …)` heads parsed out of the **source** (visibility is written nowhere else) joined against `axiom symbols` AXSYM rows for the **effect** column. It is also the program that writes [`docs/stdlib-api.md`](../docs/stdlib-api.md) | `axdoc <axsym-file> <module.ax>…`, where the AXSYM file is one concatenated `axiom --diagnostic-format=ai symbols` stream — the gate assembles both; see its header | [`scripts/check-stdlib-api.sh`](../scripts/check-stdlib-api.sh) |

Every one of those headers is longer than this table and says *why* the
program is written the way it is. Read the header before the code.

## What was here and is not

A templated web server, `server.ax` under `examples/web` — `Html` and
`Http`, a pre-forked worker pool, escaping in text and in attribute
position, and the request handler as an arena scope (`docs/memory-model.md`
MM-ALLOC-22) — was deleted on 2026-09-04, together with `stdlib/Html.ax`,
the DSL it was the one program for, and `scripts/check-web.sh`, the gate
that served its pages byte for byte and held its memory flat across ten
thousand requests. MM-ALLOC-22 is still measured, by `scripts/check-net.sh`
over `tests/net/echo-server.ax`, and `Http` is exercised by the
`tests/stdlib/` cases numbered 430 to 432; what no gate measures any more is
a page rendered per request. `git log -- examples/web` has the program. (The
path is not spelled out above on purpose: the gate reads every
`examples/…​.ax` this file names as a table row and requires it to exist.)

## What these do NOT show

Counted across the two sources on 2026-09-04: `region` 0, `parallel` 0,
`simd` 0, and `;@axiom:restrict` 0. Four features that shipped in the
0.5–0.7 window have no worked example here, and their own gates
(`check-region-scope.sh`, `check-parallel.sh`, `check-simd.sh`,
`check-restrictions.sh`) pin them against fixtures under `tests/` instead.
That is a real gap in this directory and it is written down rather than
left for a reader to discover by grepping.

## The rule for adding one

An example here must be something a gate runs. `scripts/check-examples.sh`
also sweeps this directory and refuses any tracked file that is not `.ax` or
`.md`, and any file tracked executable — `axiom run` builds
`axiom_temp_output.<pid>` into the working directory, one such binary was
committed here in `d1e4a71` and lived in the tree until 2026-09-03 with
every gate green. The web example's stylesheet and script were the only
`.css` and `.js` here, and the allowance for them went with them. Adding a
legitimate new asset type is a deliberate edit to `ex_allowed` in that gate
and to the table above, in that order.
