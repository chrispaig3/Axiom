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
import { BLOB, DOCS, REPO } from './site.ts'

const REF = `${DOCS}/reference.md`

/* ------------------------------------------------------------------ *
 * Why Axiom: six properties, each with the thing that holds it.
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
    title: 'A binary, not a runtime',
    body: 'No VM and no garbage collector. The allocator is emitted into your executable and the standard library talks to the kernel with raw syscalls, so a program calls no C function to print or to allocate.',
    proof: 'scripts/check-freestanding.sh',
    href: `${BLOB}/scripts/check-freestanding.sh`,
  },
  {
    icon: 'shield',
    title: 'Effects the compiler proves',
    body: 'I/O is inferred through every call. Declare it, promise its absence with `restrict(no-io)`, or say nothing, which is itself a claim. A false one is an error that traces the path to the syscall.',
    proof: ';@axiom:restrict(no-io)',
    href: `${REF}#restrict---what-a-declaration-does-not-do`,
  },
  {
    icon: 'terminal',
    title: 'A compiler that argues well',
    body: 'Exhaustive matching, no silent coercions, and errors that quote both spans, explain themselves with `axiom explain`, and carry fixes a tool can apply.',
    proof: 'axiom explain AX3005',
    href: `${DOCS}/diagnostics.md`,
  },
  {
    icon: 'bot',
    title: 'Legible to people and agents',
    body: 'One syntactic form with no precedence to guess. One line per diagnostic and one per symbol, with ids that survive edits, so a tool reads facts instead of scraping prose.',
    proof: '--diagnostic-format=ai',
    href: `${DOCS}/agent-harness.md`,
  },
  {
    icon: 'loop',
    title: 'It builds itself',
    body: 'The compiler is written in Axiom and bootstraps from committed LLVM IR with nothing but `llc` and a C linker, until two generations are byte-identical.',
    proof: 'scripts/bootstrap-from-seed.sh',
    href: `${BLOB}/scripts/bootstrap-from-seed.sh`,
  },
  {
    icon: 'link',
    title: 'Rust when you need it',
    body: 'An `extern` block names symbols in a static archive, and `--crate` builds the crate and links it. Handles drop the Rust value when the last Axiom reference goes.',
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
  { feature: 'Syscalls', status: 'Complete', note: 'Six targets, no libc between you and the kernel.' },
  { feature: 'Module visibility', status: 'Complete', note: 'Only `pub` leaves a module.' },
  { feature: 'Self-hosting', status: 'Done', note: 'The Rust compiler it replaced has been deleted.' },
]

export const STATUS_LIMITS: StatusRow[] = [
  { feature: 'Effects', status: 'Enforced; two limits stated', note: 'Two inference gaps, both stated: unresolvable calls are marked incomplete, and constructor allocation is not counted.' },
  { feature: 'Macros', status: 'Partial', note: 'A template cannot generate `import` or a nested `macro`, or test two binders for sameness.' },
  { feature: 'Concurrency', status: 'Language form, two lowerings', note: '`parallel` only: no async, no scheduler.' },
  { feature: 'Region syntax', status: 'Checked scope, and annotated signatures with the escape rule', note: 'Scalars leave a region; typed promotion is planned.' },
  { feature: 'FFI', status: 'Functional', note: 'Rust through `extern` blocks and generated bindings.' },
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
      'It is 0.x, and it says exactly how far each piece has got. The core language (types, matching, structs, loops, modules) is complete; the FFI, the standard library and editor support are functional; macros are partial. Every row of the status table names the test that holds it.',
      'If you need a mature ecosystem, a package index or green threads, those are not here yet. If you want a small, explicit language whose compiler you can reason about, it is built for that today.',
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
      'No. Effects are inferred transitively. Only I/O must be declared, because it is the one effect a caller cannot learn without opening the callee; allocation and mutation are inferred and reported but never demanded. (The one other requirement is local: a function that calls a raw-memory primitive says `effect(unsafe)`.) `restrict(...)` and `pure` are optional, stronger claims you add where they matter.',
    ],
    link: { label: 'Effects in the reference', href: `${REF}#effects` },
  },
  {
    q: 'Which platforms does it run on?',
    a: [
      'Six targets are supported, and in this project that word has a definition: a CI job executes what the compiler emits there. Prebuilt archives exist for Apple silicon and Linux on arm64; everywhere else, one script builds the compiler from the committed seed with `llc` and a C compiler. Windows executables are cross-compiled from Linux or macOS.',
    ],
    link: { label: 'Targets in the README', href: `${REPO}#targets` },
  },
  {
    q: 'Can I call Rust or C?',
    a: [
      'Rust, directly: mark functions `#[axiom_export]`, and `axiom-bindgen` writes the Axiom module. Strings, `Vec`s, `Result`s, callbacks and owned handles cross the boundary, and the other direction works too: a Rust program can host an Axiom static library. C is reachable through the same `extern` block.',
    ],
    link: { label: 'The FFI guide', href: `${DOCS}/ffi.md` },
  },
  {
    q: 'How does concurrency work?',
    a: [
      'One form, `parallel`, runs its bindings beside the caller and joins them in the order written: as child processes by default, whose isolation is true by construction, or as threads under `--threads`. Only a machine word crosses a join, and a binding that captures a reference the parent holds is refused. There is no async and no scheduler; `stdlib/Par.ax` is a bounded pool over the same primitives.',
    ],
    link: { label: 'parallel in the reference', href: `${REF}#parallel--bindings-that-run-beside-the-caller` },
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
      'Because more and more code is written by agents, and an agent reading English error prose is guessing. `--diagnostic-format=ai` prints one dense line per diagnostic with exact spans and applicable fixes, and `axiom symbols` prints one line per declaration with a content-derived id, so a tool can ask what a file provides without reading it again. The human report is built from the same structured diagnostic, so the two can never disagree.',
    ],
    link: { label: 'Diagnostics and AXSYM', href: `${DOCS}/diagnostics.md` },
  },
]

/* ------------------------------------------------------------------ *
 * Built for: the kinds of work where the design pays off. Each point
 * is sourced: the stdlib names are `docs/reference.md` (Standard
 * Library); regions per request are MM-ALLOC-22 in
 * `docs/memory-model.md`; `restrict(...)` is `docs/reference.md`
 * (AXTAG Keys); the agent surface is `docs/agent-harness.md`.
 * ------------------------------------------------------------------ */

export type UseCaseIcon = 'terminal' | 'globe' | 'shield' | 'bot'

export interface UseCase {
  icon: UseCaseIcon
  kicker: string
  title: string
  body: string
  points: string[]
  link: { label: string; href: string }
}

export const USE_CASES: UseCase[] = [
  {
    icon: 'terminal',
    kicker: 'Command-line tools',
    title: 'Ship one file that starts instantly.',
    body: '`axiom build` writes a native executable with its allocator and its syscalls inside it. There is no runtime to install beside it and nothing to warm up.',
    points: [
      'Arguments, environment, files, pipes and child processes, all from a standard library written in Axiom.',
      '`--target` emits for any of six targets from any host.',
      '`axiom new` gives you a project; `axiom build` names the binary after it.',
    ],
    link: { label: 'The standard library', href: `${REF}#standard-library` },
  },
  {
    icon: 'globe',
    kicker: 'Services',
    title: 'Serve requests in flat memory.',
    body: 'Sockets and readiness polling are raw syscalls, `Http` parses and routes requests, and a `region` per request reclaims everything it built in a single pointer move.',
    points: [
      'Reference counting frees what dies early; the region takes the rest at the end of the request.',
      'A pre-forked server is measured flat across ten thousand connections, against an unscoped run that must grow.',
      'Numeric addresses only: name resolution lives in libc, and Axiom does not call libc.',
    ],
    link: { label: 'Regions in the reference', href: `${REF}#regions` },
  },
  {
    icon: 'shield',
    kicker: 'Security-sensitive code',
    title: 'Say what a function may not do. Have it checked.',
    body: '`;@axiom:restrict(no-io,no-alloc,no-foreign)` is not a comment. It is a claim tested against the effect row and the call graph, and a failure names the path of calls to where the effect enters.',
    points: [
      'Silence is a checked claim: a function that performs I/O and does not declare it is an error, not a lint.',
      'The program calls no C library function, so there is no libc call for anyone to interpose on.',
      'Exploits first, codes second: an attack was measured working before it became a diagnostic and a fixture.',
    ],
    link: { label: 'The security policy', href: `${BLOB}/SECURITY.md` },
  },
  {
    icon: 'bot',
    kicker: 'Code written by agents',
    title: 'Let the machine read facts, not prose.',
    body: 'One line per diagnostic and one per symbol, so an agent can ask what a file provides and what went wrong without paying to read it all again.',
    points: [
      'Fixes arrive as a span and a replacement, applied by substitution rather than by parsing English.',
      'Every function, type and struct carries an id that survives reordering and reformatting.',
      'One syntactic form: no precedence to guess, no parse ambiguity to get wrong.',
    ],
    link: { label: 'The agent harness', href: `${DOCS}/agent-harness.md` },
  },
]

/* ------------------------------------------------------------------ *
 * Built with Axiom: the programs this repository runs every day that
 * are written in the language. Real users of a 0.x language are the
 * ones you can check, and every one of these is gated in CI.
 * ------------------------------------------------------------------ */

export interface Built {
  name: string
  path: string
  body: string
}

export const BUILT: Built[] = [
  {
    name: 'The compiler',
    path: 'self_host/',
    body: 'Lexer, parser, macro expander, type and effect checker, LLVM emitter and driver. CI rebuilds it from the committed seed on every run.',
  },
  {
    name: 'The language server',
    path: 'self_host/lsp.ax',
    body: 'Navigation, hover, completion, rename, call hierarchy, code actions and macro expansion, over JSON-RPC framed by the standard library.',
  },
  {
    name: 'The standard library',
    path: 'stdlib/',
    body: 'Strings, UTF-8, vectors, maps, JSON, HTTP, processes, sockets and a line editor. None of it calls C.',
  },
  {
    name: 'The API reference generator',
    path: 'examples/axdoc/axdoc.ax',
    body: 'Reads the library\'s source and its AXSYM stream and writes stdlib-api.md; CI requires the output byte-identical.',
  },
  {
    name: 'A million-record batch job',
    path: 'examples/batch-fallible/batch-fallible.ax',
    body: 'Malformed records handled by an effect six calls down, with no unwinding and no bytes allocated per record.',
  },
  {
    name: 'The REPL and the formatter',
    path: 'self_host/repl.ax',
    body: 'An interactive session that compiles each line to native code, and the one canonical layout, in the same binary.',
  },
]
