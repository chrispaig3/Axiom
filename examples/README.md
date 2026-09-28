# Examples

Complete programs you can read, run and borrow from. Each one is real
code this repository depends on, and CI runs every one of them, so they
keep working as the compiler changes.

Run the commands from the repository root. Each program opens with a
header comment that explains why it's written the way it is, and it's
worth reading before the code.

## batch-fallible

[`examples/batch-fallible/batch-fallible.ax`](batch-fallible/batch-fallible.ax)
processes a million records and shows the `Fallible` effect at work. A
parser six calls down reports a bad record with `fallibleMalformed`,
and the loop at the top decides what happens next:

- skip the record, with `fallibleSkip`;
- use a default value, with `(fallibleDefault d)`;
- or count the failures, with a handler around either.

Nothing unwinds, and handling a bad record allocates nothing: 0 bytes
per record.

```bash
axiom run examples/batch-fallible/batch-fallible.ax [N [k]]
```

`N` and `k` default to `1000000` and `7`. The header shows the
arithmetic behind the three numbers it prints, so you can check them.

Tested by `scripts/check-steady-state.sh`.

## axdoc

[`examples/axdoc/axdoc.ax`](axdoc/axdoc.ax) reads a program's public
surface and writes a reference page for it. It's the program that
writes [`docs/stdlib-api.md`](../docs/stdlib-api.md).

It reads the `(pub :: …)` declarations from the source, because that's
the only place visibility is written. It then joins them with the rows
`axiom symbols` prints, which supply the effects column.

```bash
axdoc <axsym-file> <module.ax>…
```

The AXSYM file is the output of `axiom --diagnostic-format=ai symbols`
for every module, concatenated. `scripts/check-stdlib-api.sh` builds
both inputs and runs the whole pipeline, so it's the place to look for
a working command line.

Tested by `scripts/check-stdlib-api.sh`.

## concurrency/pipeline

[`examples/concurrency/pipeline.ax`](concurrency/pipeline.ax) is a
bounded producer/consumer pipeline over `Chan`: three `parallel`
stages joined by two four-word channels. The producer pauses partway
through, and the worker waits it out with `chanRecvTimeout`, counting
each timeout as an idle tick. Sends wait at most a second, and the
stream ends when the producer closes the channel.

```bash
axiom run examples/concurrency/pipeline.ax [N]
```

It checks the sum of squares of 1..N and that the worker idled at
least once. The last line it prints is `ok`.

Tested by `scripts/check-task.sh` §7, in both lowerings.

## concurrency/typed-tasks

[`examples/concurrency/typed-tasks.ax`](concurrency/typed-tasks.ax)
carries typed results across the process boundary with `Task`. Each
forked task encodes a `struct` holding a `Vec` as JSON, the bytes come
back under a 4 KiB per-task limit, and the parent decodes them and
compares against the sequential answer.

```bash
axiom run examples/concurrency/typed-tasks.ax [N [W]]
```

`N` and `W` default to `24` and `4`. The last line it prints is `ok`.

Tested by `scripts/check-task.sh` §7, in both lowerings.

## concurrency/cancel

[`examples/concurrency/cancel.ax`](concurrency/cancel.ax) cancels and
fails tasks while they work. A sharded search runs three shards: one
fails, one ignores the cancellation token and is killed after the
grace period, and the shard that finds the needle cancels its own pool
through the token.

```bash
axiom run examples/concurrency/cancel.ax
```

It checks every shard's outcome and that no shard process survives.
The last line it prints is `ok`.

Tested by `scripts/check-task.sh` §7, in both lowerings.

## Not covered here yet

Regions, SIMD and `;@axiom:restrict` don't have a worked example in
this directory yet. The language reference covers each one:
[Regions](../docs/reference.md#regions),
[Concurrency](../docs/reference.md#concurrency) and
[Effects](../docs/reference.md#effects). Their CI checks show them in
use: `scripts/check-region-scope.sh`, `scripts/check-simd.sh` and
`scripts/check-restrictions.sh`.

## Adding an example

An example must be something CI runs. Add a gate that runs it, or
extend an existing one, and give it a section here.

`scripts/check-examples.sh` keeps this page and the directory in step.
It fails when a program here has no section, or when a section names a
program that doesn't exist. It also rejects any tracked file that isn't
`.ax` or `.md`, and any file tracked as executable. That catches the
`axiom_temp_output.<pid>` binary that `axiom run` writes into the
working directory. To allow a new kind of file, add its extension to
`ex_allowed` in that script, and describe it here.
