/**
 * The page's prose that is not code: pillars, the comparison, the
 * status panel and the FAQ.
 *
 * The same rule as everywhere else on this site: a sentence here is a
 * claim, and a claim names where it is held. The status rows are read
 * back against `docs/status.md` by `scripts/check-claims.mjs`, feature
 * name and status word both; the rest cite the document that is the
 * one copy of the fact, so a reader can check it and so can the next
 * person to edit this file.
 */
import { BLOB, DOCS, stat } from './site.ts'

const REF = `${DOCS}/reference.md`

/* ------------------------------------------------------------------ *
 * Why Axiom: six design decisions, each linked to what enforces it.
 * ------------------------------------------------------------------ */

export type PillarIcon = 'box' | 'shield' | 'terminal' | 'bot' | 'loop' | 'link'

export interface Pillar {
  icon: PillarIcon
  title: string
  body: string
  /** A short, checkable token: a command, a tag, a file. */
  proof: string
  href: string
}

export const PILLARS: Pillar[] = [
  {
    icon: 'box',
    title: 'Ship the binary. That’s it.',
    body: 'Your program compiles to a native executable, with its allocator included and direct calls to the kernel. No VM to provision. No garbage collector to tune.',
    proof: 'scripts/check-freestanding.sh',
    href: `${BLOB}/scripts/check-freestanding.sh`,
  },
  {
    icon: 'shield',
    title: 'Make side effects explicit.',
    body: 'Keep computation separate from I/O. The compiler infers effects, checks `restrict(no-io)`, and requires functions that perform I/O to declare it.',
    proof: ';@axiom:restrict(no-io)',
    href: `${REF}#restrict-what-a-function-never-does`,
  },
  {
    icon: 'terminal',
    title: 'Find the problem. Keep moving.',
    body: `Get a precise location, a stable error code, and often a fix your tools can apply. \`axiom explain\` has a page for each one of the ${stat('codes')} codes.`,
    proof: 'axiom explain AX3005',
    href: `${DOCS}/diagnostics.md`,
  },
  {
    icon: 'bot',
    title: 'Built for you. And your agents.',
    body: 'Uniform syntax keeps code generation predictable. Structured diagnostics, exact spans, and stable symbol IDs give your tools the same facts you use to review their work.',
    proof: '--diagnostic-format=ai',
    href: `${DOCS}/agent-harness.md`,
  },
  {
    icon: 'loop',
    title: 'Read the compiler. In Axiom.',
    body: `The compiler is ${stat('lines')} lines of Axiom. A clean checkout rebuilds it from committed LLVM IR with \`llc\` and a C linker, and stops unless two generations are byte-identical.`,
    proof: 'scripts/bootstrap-from-seed.sh',
    href: `${BLOB}/scripts/bootstrap-from-seed.sh`,
  },
  {
    icon: 'link',
    title: 'Bring Rust along.',
    body: 'Keep useful Rust code within reach. Declare functions in an `extern` block; `--crate` builds and links the crate. Rust values are dropped when their last Axiom reference goes.',
    proof: 'axiom build --crate DIR',
    href: `${DOCS}/ffi.md`,
  },
]

/* ------------------------------------------------------------------ *
 * The comparison. A design comparison, not a benchmark, and nothing
 * here scores anybody.
 *
 * Every Axiom cell is sourced: memory is `docs/reference.md` (Choosing
 * a Memory Manager) and `docs/memory-model.md`; the runtime row is
 * `scripts/check-freestanding.sh`; effects are `docs/reference.md`
 * (Effects); macros are `docs/reference.md` (Macros); the build row is
 * `docs/reference.md` (Packages). The other columns are restricted to
 * facts that are not in dispute: that Go and GHC ship a garbage
 * collector and a runtime system, that a Rust binary using `std` links
 * the platform C library, that neither Rust nor Go tracks effects.
 * ------------------------------------------------------------------ */

export interface CompareRow {
  k: string
  axiom: string
  rust: string
  go: string
  haskell: string
}

export const COMPARE: CompareRow[] = [
  {
    k: 'Memory',
    axiom: 'Bump allocation, reference counting, and regions when you choose the moment. No tracing collector, no borrow checker.',
    rust: 'Ownership and borrowing',
    go: 'Tracing GC',
    haskell: 'Tracing GC',
  },
  {
    k: 'Inside the binary',
    axiom: 'Your code, its allocator and raw syscalls. No C library function is called.',
    rust: 'std links the C library',
    go: 'GC and scheduler runtime',
    haskell: 'The GHC runtime system',
  },
  {
    k: 'Side effects',
    axiom: 'Inferred per function; declared or restricted with a tag the compiler checks.',
    rust: 'Not tracked',
    go: 'Not tracked',
    haskell: 'Tracked in types, by hand',
  },
  {
    k: 'Macros',
    axiom: 'Rewrite the program tree before type checking; hygienic.',
    rust: 'Token streams',
    go: 'None',
    haskell: 'Template Haskell',
  },
  {
    k: 'Build and run',
    axiom: '`axiom run f.ax`: one step, no build file needed.',
    rust: 'cargo',
    go: 'go build',
    haskell: 'cabal or stack',
  },
]

/* ------------------------------------------------------------------ *
 * Status, held to docs/status.md. `feature` is that table's first
 * column exactly, `status` its bold second column exactly;
 * `check-claims.mjs` reads the table and fails on any row that does
 * not match, so this panel cannot promote a feature the table has not.
 * ------------------------------------------------------------------ */

export interface StatusRow {
  feature: string
  status: string
  /** What a reader needs in one line. */
  note: string
}

export const STATUS_SOLID: StatusRow[] = [
  { feature: 'Functions & types', status: 'Complete', note: 'Curried signatures, rigid type variables, exact return types.' },
  { feature: 'ADTs / data types', status: 'Complete', note: 'Sums with positional or named fields.' },
  { feature: 'Pattern matching (`match`)', status: 'Complete', note: 'Nested, exhaustive, checked in every function.' },
  { feature: 'Structs', status: 'Complete', note: 'Per-field `mut`, generic parameters, automatic rendering.' },
  { feature: 'Lambda / function values', status: 'Complete', note: 'Closures, partial application, `_` holes.' },
  { feature: 'Loops', status: 'Complete', note: '`for` over ranges and containers, `while`.' },
  { feature: 'Syscalls', status: 'Complete', note: 'Eight targets, no libc between you and the kernel.' },
  { feature: 'Module visibility', status: 'Complete', note: 'Only `pub` leaves a module.' },
  { feature: 'Self-hosting', status: 'Done', note: 'The Rust compiler it replaced has been deleted.' },
]

export const STATUS_LIMITS: StatusRow[] = [
  { feature: 'Effects', status: 'Enforced; two limits stated', note: 'Two inference gaps, both stated: unresolvable calls are marked incomplete, and constructor allocation is not counted.' },
  { feature: 'Macros', status: 'Partial', note: 'A template cannot generate `import` or a nested `macro`, or test two binders for sameness.' },
  { feature: 'Concurrency', status: 'Language form, two lowerings', note: '`parallel`, channels, a mutex and task pools; a binding may borrow a `String`. No async, no scheduler.' },
  { feature: 'Region syntax', status: 'Checked scope, and annotated signatures with the escape rule', note: 'Scalars leave a region; typed promotion is planned.' },
  { feature: 'FFI', status: 'Functional', note: 'Rust through `extern` blocks and generated bindings.' },
  { feature: 'Standard library', status: 'Functional', note: 'Collections, cryptography, dates, JSON, networking and an embedded database.' },
  { feature: 'Error handling', status: 'Functional; adopted at the syscall seam', note: '`Result`, the `try` form, and handlers that skip a bad record without unwinding.' },
  { feature: 'Editor support', status: 'Functional', note: 'Language server plus a tree-sitter grammar.' },
]

export const STATUS_REMOVED: StatusRow[] = [
  { feature: 'Type classes', status: 'Replaced', note: 'By capability records: an interface is a struct of functions.' },
  { feature: 'Lists', status: 'Removed', note: 'Sequences are `(Vec T)`.' },
  { feature: 'Tuples', status: 'Removed', note: 'Products are `struct`, sums are `data`.' },
  { feature: 'Linear types', status: 'Removed', note: 'Deterministic reclamation is reference counting\'s job.' },
]

/* ------------------------------------------------------------------ *
 * FAQ. Each answer cites the document that holds the fact. Rendered as
 * <details> so it works with no JavaScript, and emitted as FAQPage
 * structured data by `scripts/prerender.mjs`.
 * ------------------------------------------------------------------ */

export interface Faq {
  q: string
  /** Paragraphs. Backticks become <code>. */
  a: string[]
  link?: { label: string; href: string }
}

export const FAQS: Faq[] = [
  {
    q: 'Is Axiom ready for production?',
    a: [
      'Not for most teams yet. It is 0.x: the core language (types, matching, structs, loops, modules) is complete, the FFI, standard library and editor support are functional, and macros are partial. Every row of the status table names the test behind it.',
      'There is no package index and no green threads. What is here is a small language whose compiler you can read and whose claims are tested.',
    ],
    link: { label: 'Implementation status', href: `${DOCS}/status.md` },
  },
  {
    q: 'Does it have a garbage collector?',
    a: [
      'No tracing collector. Memory comes from a bump allocator over `mmap`, and every heap block carries a reference count, so a value is freed the moment its last reference dies, with nothing written in the source. When you want reclamation at a point of your choosing, `(region r body)` rolls the allocator back in one step.',
    ],
    link: { label: 'The memory model', href: `${DOCS}/memory-model.md` },
  },
  {
    q: 'What does "no libc" actually mean?',
    a: [
      'The code Axiom generates, and its standard library, reach the kernel through raw syscalls: printing, allocation, files, processes and sockets included. `scripts/check-freestanding.sh` fails the build if the generated IR calls a C library function or the executable imports one.',
      'The final link is done by your system C compiler, which on Linux adds the C runtime\'s startup code; on macOS arm64, `nm -u` on a compiled program is empty. An `extern` block to Rust is the one deliberate door, and a `no_std` crate adds no C library function through it.',
    ],
    link: { label: 'The freestanding gate', href: `${BLOB}/scripts/check-freestanding.sh` },
  },
  {
    q: 'Why S-expressions?',
    a: [
      'Because the program is already a tree. There is no operator precedence to memorise, no ambiguous parse, and macros operate on the same structure the compiler checks. That uniformity is also what makes the language easy for a tool or an agent to generate correctly.',
      'The editor side is covered: a tree-sitter grammar colours by syntactic role with rainbow brackets, and `axiom fmt` settles layout.',
    ],
  },
  {
    q: 'Do I have to annotate every function\'s effects?',
    a: [
      'No. Four effects must be declared through the call chain: `effect(io)`, `effect(entropy)`, `effect(spawn)` and `effect(block)`. Allocation and mutation are inferred and reported. A function that performs a raw operation, calls a precondition interface or casts a value into an unrelated reference type declares `effect(unsafe)`. A trusted wrapper contains that obligation for its callers. `restrict(...)` and `pure` add stronger checks where you need them.',
    ],
    link: { label: 'Effects in the reference', href: `${REF}#effects` },
  },
  {
    q: 'Are there traits or type classes?',
    a: [
      'They were replaced by capability records. An interface is a parameterised struct holding functions, and an instance is an ordinary value of it, passed where it is needed. Dispatch is application: no table, no resolution rules, and a function generic over an interface can call its methods.',
    ],
    link: { label: 'Capability records', href: `${REF}#capability-records` },
  },
  {
    q: 'Is there a package manager?',
    a: [
      'A project is an `axiom.pkg` file: `axiom new` writes one. A `depend` line names a directory of modules or a git URL, `axiom fetch` clones the URLs, and two dependencies may never provide the same module. There is no central index and no version pinning yet, and the compiler never fetches or runs another project\'s build on its own.',
    ],
    link: { label: 'Packages in the reference', href: `${REF}#packages` },
  },
  {
    q: 'Why does the compiler have an "ai" output format?',
    a: [
      'For agents and other tools. `--diagnostic-format=ai` prints one line per diagnostic with exact spans and any fix that applies, and `axiom symbols` prints one line per declaration with an id that survives reformatting, so a tool can learn what a file provides without reading it again. The human report is rendered from the same diagnostic, so the two cannot disagree.',
    ],
    link: { label: 'Diagnostics and AXSYM', href: `${DOCS}/diagnostics.md` },
  },
]
