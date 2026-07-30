# Conway's Game of Life, in Axiom

The largest pure-Axiom program in the tree, and the one that answers a
question the unit tests cannot: can Axiom, as it exists today, express
arbitrary computation?

Life is Turing-complete, so a working implementation settles that. What
makes it interesting here is *how* it has to be written. Axiom currently
has no loop form, no mutable local bindings, no runtime representation
for the built-in list type, and no closures that survive code generation.
Everything below therefore runs on recursion over immutable algebraic
data and nothing else — which is both the proof and the measurement.

```
game_of_life/
├── Life.ax              pure core: List/Cell types, the rule, the digest
├── Render.ax            board → text
├── main.ax              blinker + glider, checked against expected.out
├── stress.ax            sized to measure, not to look at
├── expected.out         golden output for main.ax
└── stress.expected.out  golden output for stress.ax
```

## Running it

```bash
AXIOM_STDLIB=stdlib axiom --diagnostic-format=ai run game_of_life/main.ax
./scripts/check-game-of-life.sh        # both cases, at -O0 and --opt 2
```

## What it establishes

**The simulation is correct, verified against an independent
implementation.** `stress.ax` prints a position-sensitive digest of the
board before and after twenty generations, and both values match a
reference implementation written separately in Python:

| | Axiom | Python reference |
|---|---|---|
| `pop0` | 200 | 200 |
| `popN` | 200 | 200 |
| `hash0` | 977834815 | 977834815 |
| `hashN` | 277440489 | 277440489 |

The digest is the load-bearing part. On this seed the population is
constant at 200 across all twenty generations *while the board changes
every generation*, so a population check would pass for a `step` that did
nothing at all. Two bugs during development were caught by exactly this:

- The first seed function, a textbook LCG `((r*31+c) * 1103515245 +
  12345) mod 3`, seeded **every** cell alive, because both constants are
  divisible by 3 and the expression is identically zero in that modulus.
  The simulation then behaved correctly — a completely full board dies out
  in two generations, which is what it did — so nothing about the
  *evolution* was suspicious. Only the reported starting population was.
  `stress.ax` prints `pop0` for that reason.
- `main.ax` uses a blinker and a glider rather than one pattern, because
  they fail differently. A blinker catches a wrong survival rule; a glider
  catches an off-by-one in the neighbour offsets or in the border
  condition, because a glider is the only one of the two that moves.

**The language features it exercises, end to end and not merely
type-checked:** polymorphic recursive `data` nested two levels deep
(`List (List Cell)`), exhaustive `match` on every single access,
multi-argument recursion carrying its own indices, multi-module imports,
transitive effect inference (`Life.ax` is verified effect-free by
`axiom symbols`, which is a gate in `check-game-of-life.sh`), and
iteration as recursion at both `-O0` and `--opt 2`.

## What it measures

### Allocation is unbounded, and the number is large

Every generation allocates a completely fresh board and frees nothing;
the allocator is a bump pointer over `mmap` with no reclamation. The
consequence is not subtle. Peak RSS for a 24×24 board, `--opt 2`, on
macOS/arm64:

| Generations | Peak RSS | Live set |
|---:|---:|---:|
| 10 | 5.2 MiB | ~10 KiB |
| 20 | 9.0 MiB | ~10 KiB |
| 40 | 16.6 MiB | ~10 KiB |
| 80 | 31.8 MiB | ~10 KiB |
| 400 | 150 MiB | ~10 KiB |
| 2000 | 744 MiB | ~10 KiB |

Growth is linear in generations and flat in live data: ~380 KiB per
generation for a board that is ~10 KiB. At 2000 generations the program
holds 76,000× its live set. The live set never changes, because only one
board is reachable at a time.

This is the measurement that motivates the memory-model work rather than
a design opinion about it. A bump allocator is the right choice for a
single-shot compiler process, which is what it was built for. It is the
wrong choice for anything that iterates, and *iteration is the normal
case* — a compiler pass over a large file has the same shape as this loop.
What is needed is not a garbage collector and not manual `free`: it is for
the compiler to know that the previous generation is dead at the point
`advance` recurses, which is a static fact about this program that nothing
in the language can currently express.

### The costs are in the data structures, not the semantics

Two of them are visible in the source and both are the language's fault,
not the program's:

- `nth` is O(i) on a linked list, so `neighbours` is O(width) and a
  generation is O(n²) in the board dimensions. A growable array would fix
  it and does not exist yet (`B3` in [docs/self-hosting.md](../docs/self-hosting.md)).
- `renderRow` builds a row by `strConcat`, allocating one throwaway string
  per cell, which is quadratic in row width. A string builder needs either
  a growable buffer or mutable state; Axiom has neither, so this is what
  the language currently forces.

Neither is worked around here. The demo is more useful as an honest
account of what writing Axiom is like today than as a showcase of what it
could look like after the fixes.

### Recursion depth still depends on an optimisation flag

`stepRow` is not tail recursive — the `Cons` wraps the recursive call — so
it costs one stack frame per column at every optimisation level. The
generation loop in `stress.ax` *is* tail recursive, so it costs one frame
per generation at `-O0` and none at `--opt 2`. Both cases are in the CI
gate at both levels precisely because that difference exists; correctness
depending on `--opt` is tracked as `B2` in
[docs/self-hosting.md](../docs/self-hosting.md).

## Deliberately not used

- **Built-in list syntax `[a]`** — type-checks, no runtime
  representation. Lists here are a `data` declaration.
- **`lambda`** — type-checks, no closure codegen, so every traversal is a
  named recursive function threading its own index instead of a fold.
- **`linear` / `consume`** — parsed only. The ownership fact that would
  let the previous generation be reclaimed is exactly what these are for,
  and exactly what cannot be stated yet.
