# The restricted profile and the resource report

Status: **implemented and verified by `scripts/check-report.sh`** on the
hosted configurations (H1–H3 in [assurance/configurations.md](assurance/configurations.md)),
with the stack half read from AArch64 and x86-64 ELF objects. It is a
qualification-readiness input, not a qualified tool: nothing here is
approved for any application ([assurance/plan.md](assurance/plan.md)
keeps those words apart).

`scripts/axiom-report.py` answers three questions about one program:

1. **What does each reachable function do?** Allocate, perform IO, call
   an Unsafe primitive directly, call an `extern` item, sit on a
   call-graph cycle, make a call the graph cannot follow, spawn or join
   a binding, enter the kernel, end the process with a trap status, or
   wait on another party.
2. **Does the program keep the restricted profile?** A fixed set of
   refusals, RP-1 to RP-9, over everything reachable from the program's
   roots.
3. **How much stack can it use?** A bound computed from the machine
   code `llc` emits, or the precise reason there is none.

```
python3 scripts/axiom-report.py FILE.ax                          # the report
python3 scripts/axiom-report.py --profile restricted FILE.ax     # + refusals, exit 1 if any
python3 scripts/axiom-report.py --profile restricted \
    --target baremetal-aarch64 --stack --stack-budget 8192 FILE.ax
python3 scripts/axiom-report.py --format json ...                # the same, as JSON
```

`--axiom PATH` (or `$AXIOM`) names the compiler; `--opt N` the level the
stack half builds at (default 1, the driver's default). Exit status: 0
no refusal, 1 refusals, 2 the tool could not answer - a program that
does not check, a compiler or `llc` failure, an object it cannot read.
It never exits 0 for an answer it did not compute.

## What it reads

Nothing it has to guess. The source half is the compiler's own call
graph and effect rows, `axiom --diagnostic-format=ai [--target T]
symbols --calls --builtins FILE`: per function, `#effects=` (the
transitive effect row, a fixpoint the checker computes), `#calls=`
(the resolved call edges), `#effect-params=` (a body that calls one of
its own parameters), `#effects-incomplete` and `#effects-possible=`
(the row's admissions that it is a bound), `#effect=` (declared
effects - `#effect=unsafe` is `AX3073`'s checked marker of a body that
performs an unsafe operation itself, and `#unsafe=` says whether it is
a trusted encapsulation or a precondition interface), `#isr`,
`#restrict=`, and `#extern`, which `symbols` prints on an `extern`
item since this profile landed: without it an extern row is a function
with no calls and `#effects=IO`, which is also what a body writing one
syscall looks like.

The stack half is the object `llc` writes for the same IR at the same
`--opt`, with `-stack-size-section -function-sections` added: each
function's static frame from `.stack_sizes`, and its direct calls and
tail calls from the relocations `llc` had to leave for them
(`R_AARCH64_CALL26`, `R_AARCH64_JUMP26`). Where a function's address
escapes, which indirect calls exist, and which functions hold a
dynamically sized `alloca` or inline assembly are read from the
post-`opt` IR, which can tell an escape from a comparison.

## The profile

The roots are `main`, every `;@axiom:isr` function of the root file,
and any `--root NAME`. Everything reachable from them is held to:

| Rule | Refuses | Why |
|---|---|---|
| RP-1 | a call-graph cycle (recursion, direct or mutual) | a cycle's stack is bounded by its input, not by its depth. With `--stack`, a cycle the machine code shows holds no frame across it - LLVM made it a loop, or every edge is a tail call - is admitted and listed as an obligation instead: the stack is bounded, termination stays the program's |
| RP-2 | a call the graph cannot follow: a body calling a parameter, a row that admits it is a bound, `__call_word` | an edge nobody can name is an edge nothing below can check |
| RP-3 | an `extern` item, except those named by `--allow-foreign` | foreign code carries none of the facts above |
| RP-4 | a spawn or join primitive | the profile is one thread of control plus interrupt handlers |
| RP-5 | allocation reachable from a steady root: every `isr`, every declaration claiming `restrict(no-alloc)`, every `--steady NAME` | "no allocation after initialisation" is a property of the steady-state code, so it is stated by naming that code |
| RP-6 | a `#calls=` edge that resolves to no row | fail closed: an edge this tool cannot resolve is a refusal, never a silent leaf |
| RP-7 | with `--stack`: no bound (a non-tail cycle, a dynamic `alloca`, a call into code with no frame size), or a bound over `--stack-budget` counting one interrupt's worth of stack | a stack is either bounded or it is not; "usually small" is not a bound |
| RP-8 | a call that may block, reachable from an `isr` or from a `--nonblocking NAME` root: a join, or a body passing a blocking syscall number (read, write, open, a child wait, accept, connect, a poll wait, a futex or ulock wait) | an interrupt handler that waits can wait for ever, and "nonblocking" is a claim the graph can check |
| RP-9 | an `asm` form, except in a function named by `--allow-asm` | the tool can't see whether the instructions allocate, block, trap or use stack, so each one is a reviewed exception ([memory-model.md](memory-model.md) `MM-FFI-9`) |

And it lists, without refusing, the obligations that are the explicit
trusted boundary rather than defects: every reachable function that
calls an Unsafe primitive directly (their preconditions are stated in
[memory-model.md](memory-model.md) `MM-EXEC-9c`), every function holding
an `asm` form, allowed or not, every kernel entry
(`__syscallN`; on `baremetal-aarch64` the compiler lowers these to the
no-syscall trap, status 74), and the stack analysis's own assumptions.

It also lists, for each root, the trap statuses a call from it can end
the process with, and whether it may block, with the path. Every
function using an operator undefined on part of its domain (`<<` and
`>>` on an amount outside 0 to 63, `INT_MIN / -1`) is listed too.

### Traps

Each function's trap set is closed over the call graph, with the
statuses of [memory-model.md](memory-model.md) `MM-EXEC-16`:

| Status | Source in the graph |
|---|---|
| 70 | `Alloc` in the function's row: out of memory |
| 71 | a declared effect in the row, unless a caller handles it |
| 72 | `/` or `%`: a zero divisor |
| 75, 76 | `__axiom_arena_reset`: a bad mark, or a mark past a live handle |
| 77 | `__indexTrap`: `vecGet`'s range check |
| 78 | a spawn or join |
| 80 | `__contract`: a violated `pre` or `post` |
| 82 | an atomic: a misaligned address |

### How it relates to `restrict(...)`

`restrict(...)` is a per-declaration claim the **compiler** refuses as
`AX3049` ([reference.md](reference.md), "`restrict(...)` - what a
declaration does NOT do"). The profile is a whole-program claim this
**tool** refuses, over the same facts. They compose: the profile reads
a `restrict(no-alloc)` claim as a steady root, so a step function
written

```scheme
(:: step (-> Int Int Int))
;@axiom:restrict(no-alloc, no-recursion, strict)
(fn (step buf i) ...)
```

is checked by the compiler on every build and by the profile on every
report. `tests/profile/ok-periodic.ax` is that shape.

### How it differs from general Axiom

A program in the profile does not recurse (unless the machine code
shows a loop), does not pass functions as values into calls it cannot
resolve, does not call foreign code unless named, does not use
`parallel` or the task pools, and allocates only outside its steady
roots. Everything else - the type system, effects, regions, the
standard library - is the language as it is. The profile adds no
syntax, and a program outside it still compiles; the refusal is the
report's, not the compiler's.

## The stack bound

For a call graph with two kinds of edge - a CALL keeps the caller's
frame beneath the callee, a TAIL call (a branch) replaces it -

```
v(f) = max( frame(f),
            frame(f) + v(g)   for each call g,
            v(h)              for each tail call h )
```

On x86-64 a call pushes an 8-byte return address that `.stack_sizes`
doesn't count, so each frame is charged 8 bytes more. A call and a
tail jump are told apart by the opcode byte before the relocated
displacement: `E8` is a call, and `E9` or a conditional `0F 8x` is a
tail jump.

A strongly connected component with a call edge between two of its
members grows without bound. One whose members are joined by tail
calls only is a loop, and all its members share one value, the
largest local contribution in it. Components are valued sinks first;
a node with no frame (code outside the object) or a recorded problem
is unbounded, and so is everything that reaches it.

An indirect call site may reach any function whose address escapes in
the IR. Two shapes name a function without letting its address flow
anywhere a call could read it and are not escapes: an `icmp` (the
backtracer asks "is this return address `main`?") and a
`blockaddress` (a label's address, for the line table). The backtrace
symbol table `@__axiom_symtab` holds every function's address and is
excluded by name, under a checked condition: only while every function
that reads it holds no indirect call site.

Measured with `llc` 23.1.2 at `--opt 1` on darwin-aarch64 (H3), for
`baremetal-aarch64`:

| Program | Bound from `_start` | Worst path |
|---|---|---|
| `tests/embedded/blink.ax` | 304 bytes | `_start` → `main` → `__axiom_user_main` → `Fmt$fmtInt` → `Str$strAlloc` → `axiom_alloc` → `__axiom_out_of_memory` → `__axiom_backtrace` |
| `tests/profile/ok-periodic.ax` | 192 bytes | `_start` → `main` (tail) → `__axiom_user_main` → `axiom_alloc` → `__axiom_out_of_memory` → `__axiom_backtrace` |

Both worst paths end in the out-of-memory trap's backtrace, which is
the point of reading machine code: the deepest stack either program
can reach is on its failure path, in code the source never mentions.
The linker script reserves 8 KiB of stack (`baremetalLinkScript`,
`self_host/driver.ax`).

### What the bound assumes

- Frames are `.stack_sizes` of the analysis object, built with two
  extra `llc` flags that change section placement, not frames; the
  driver's own object is not the one read.
- No code pointer is forged from an integer. `__call_word` of an
  arbitrary word breaks that, and `__call_word` is Unsafe.
- Inline assembly, the compiler's own (the trap exits, the recovery
  point, `_start`) and a program's `asm` forms, uses no stack beyond
  its function's frame. Each such function is named in the report.
- An interrupt adds one handler's bound on top of the interrupted
  code's (no nesting); the vector stub's register save area is not in
  the object and is not counted.
- The C runtime (hosted targets) and anything before `_start` are
  outside the object.

## What it does not do

- **No time bound.** A bounded stack is not a bounded latency, no loop
  is proven to terminate, and nothing here is a WCET analysis.
  Measured maximum latency and a justified worst-case bound are
  different claims ([assurance/plan.md](assurance/plan.md) milestone D).
- **Some traps have no edge in the graph.** Count exhaustion from the
  retains the compiler emits, stack exhaustion, and a CPU fault from an
  Unsafe access aren't in any function's trap set. The report names
  them every time.
- **"May block" comes from the syscall number, not the descriptor.** A
  `read` or `write` of a regular file is marked too, because the graph
  can't tell a file from a pipe.
- **The stack half reads ELF only**, for AArch64 and x86-64
  (`baremetal-aarch64`, the Linux and FreeBSD targets), not Mach-O or
  PE. On x86-64, indirect call sites come from the IR alone, because
  variable-length code can't be scanned for them without decoding.
- **The source graph is the checker's.** Code the compiler emits
  without a source call - retain, release, the allocator, trap exits -
  is visible only to `--stack`, which is what `--stack` is for.
- **It is a tool over compiler output, not a compiler mode.** The
  compiler does not refuse a program outside the profile; a build
  system that wants the profile enforced runs the report and honours
  its exit status.

## Evidence

`scripts/check-report.sh` holds the tool to five sections:

1. `--selftest`: the bound on ten hand-answered graphs - a chain, a
   diamond, tail calls, a tail loop entered from two roots, call
   cycles, code outside the object.
2. Facts: the marks of a program with one of everything, compared
   exactly; `#extern` on the extern item and nowhere else; the trap
   statuses and undefined operators of a program with one source of
   each, compared exactly.
3. The profile: `tests/profile/ok-periodic.ax` passes; each
   `tests/profile/rpN-*.ax` is refused by exactly RP-N; `--allow-foreign`,
   `--allow-asm` and a missing `--steady` each lift their refusal.
4. The stack: `ok-periodic.ax` and `blink.ax` bounded under 8 KiB; tree
   recursion (`rp1-recursion.ax`) unbounded; a 64-byte budget refused;
   each bound equal to the sum of the frames on its own path; and the
   tool's `.stack_sizes` reader agreeing with `llvm-readobj
   --stack-sizes`, an independent parser, on every function.
5. Ablations: each of RP-1..RP-5, RP-8 and RP-9 disabled in a copy of the
   tool lets its own fixture through. With no trap leaves, the trap
   statuses come out wrong. With no blocking kernel entry,
   `tests/profile/rp8-blocking.ax` passes. With the bound's cycle check
   removed, three selftest cases fail and tree recursion comes out
   bounded.
