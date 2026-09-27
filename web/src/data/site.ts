export const VERSION = '0.7.6'
export const REPO = 'https://github.com/chrispaig3/Axiom'
export const DOCS = `${REPO}/blob/trunk/docs`
export const BLOB = `${REPO}/blob/trunk`
export const RELEASES = `${REPO}/releases`

/** README.md, "Install". */
export const INSTALL_CMD =
  'curl -fsSL https://raw.githubusercontent.com/chrispaig3/axiom/trunk/scripts/install.sh | bash'

export const PATH_CMD = 'export PATH="$HOME/.axiom/bin:$PATH"'

/** README.md, "Install": building from a checkout needs no compiler. */
export const CLONE_CMD = 'git clone https://github.com/chrispaig3/Axiom.git && cd Axiom'
export const BOOTSTRAP_CMD = './scripts/bootstrap-from-seed.sh --install .axiom-bin'

/**
 * Every number on this page, with the command that establishes it. A
 * figure that cannot be produced by running something against the
 * repository does not belong here.
 */
export interface Stat {
  /** How prose asks for this figure: `stat('lines')`. */
  key: string
  n: string
  label: string
  evidence: string
}

export const STATS: Stat[] = [
  {
    key: 'lines',
    n: '105,513',
    label: 'lines of Axiom in the compiler that compiles Axiom',
    evidence: 'cat self_host/*.ax | wc -l',
  },
  {
    key: 'axfiles',
    n: '720',
    label: '.ax files in the tree, every one parsed by the grammar gate',
    evidence: "git ls-files '*.ax' | wc -l",
  },
  {
    key: 'codes',
    n: '92',
    label: 'diagnostic codes, each with a written explanation',
    evidence: 'axiom explain --list',
  },
  {
    key: 'gates',
    n: '98',
    label: 'gate scripts in the battery that runs before a push',
    evidence: 'ls scripts/check-*.sh | wc -l',
  },
]

/**
 * Figures the prose states that are not on the ticker. Same rule, same
 * checker: `check-claims.mjs` derives each one from the tree on every
 * build, in the order this file declares them after STATS.
 */
export const FACTS: Stat[] = [
  {
    key: 'lspRequests',
    n: '26',
    label: 'LSP requests the server answers',
    evidence:
      'every JSON-RPC method self_host/lsp.ax names, minus the four notifications',
  },
  {
    key: 'commands',
    n: '13',
    label: 'subcommands in one binary',
    evidence: 'the COMMANDS block of `axiom --help`, minus `help` itself',
  },
]

/**
 * The figure behind a key, for a SENTENCE that repeats one of them.
 *
 * Three sentences used to spell their number out, and all three had
 * drifted: the hero read `87,494` lines while the stat block on the same
 * page read `96,950`, and two sections said `68` diagnostic codes where
 * `axiom explain --list` printed 77. A number written twice is a second
 * copy of the fact with no gate on it, so prose calls this instead of
 * spelling the number, and `check-claims.mjs` sweeps every section for
 * a literal that equals one of these and fails naming it.
 */
export function stat(key: string): string {
  const found = STATS.find((s) => s.key === key) ?? FACTS.find((s) => s.key === key)
  if (!found) throw new Error(`site.ts: no STATS or FACTS entry keyed '${key}'`)
  return found.n
}

/**
 * The toolchain, one entry per subcommand, in `axiom --help`'s order and
 * with its words. `check-claims.mjs` reads the COMMANDS block out of
 * `self_host/driver.ax` and requires this list to be it, name for name
 * and description for description, minus `help`. The page used to say
 * "eleven subcommands" by hand, and `new` and `fetch` shipped past it.
 */
export interface Subcommand {
  name: string
  desc: string
}

export const COMMANDS: Subcommand[] = [
  { name: 'build', desc: 'compile a source file to an executable' },
  { name: 'check', desc: 'check syntax and types, emitting no code' },
  { name: 'run', desc: 'compile a source file and run it, forwarding any further ARGS' },
  { name: 'new', desc: 'start a new project: Main.ax and axiom.pkg in a new directory' },
  { name: 'fetch', desc: "check out the project's registry dependencies" },
  { name: 'test', desc: 'run every `test`-named function in a file or directory' },
  { name: 'emit-llvm', desc: 'print the generated LLVM IR' },
  { name: 'fmt', desc: 'format a source file in place (--check to only report)' },
  { name: 'explain', desc: 'describe a diagnostic code (--list for all codes)' },
  {
    name: 'symbols',
    desc: 'list every top-level symbol in AXSYM (--builtins, --calls, --mir, --axir too)',
  },
  { name: 'repl', desc: 'start the interactive read-eval-print loop' },
  { name: 'lsp', desc: 'run the language server on stdin/stdout (JSON-RPC)' },
  { name: 'version', desc: 'print the version' },
]

/**
 * README.md, "Targets", is the one copy of the supported list and of the
 * rule that defines *supported*: a CI leg executes what the compiler
 * emits there. `check-claims.mjs` holds the names below to that
 * sentence. `archive` is whether `scripts/install.sh` has a prebuilt
 * release to download; the others build from the committed seed.
 */
export interface Target {
  name: string
  archive: boolean
  note: string
}

export const TARGETS: Target[] = [
  { name: 'darwin-aarch64', archive: true, note: 'Apple silicon. Prebuilt archive.' },
  { name: 'linux-aarch64', archive: true, note: 'Prebuilt archive.' },
  {
    name: 'linux-x86_64',
    archive: false,
    note: 'Its CI leg runs the whole battery. Build from source.',
  },
  { name: 'freebsd-x86_64', archive: false, note: 'Executed in CI. Build from source.' },
  {
    name: 'windows-x86_64',
    archive: false,
    note: 'A cross-compile target: build the .exe from Linux or macOS.',
  },
  {
    name: 'darwin-x86_64',
    archive: false,
    note: 'Predates the rule; no runner executes it, so it ships nothing.',
  },
]

export interface DocLink {
  name: string
  desc: string
  href: string
}

export interface DocGroup {
  title: string
  links: DocLink[]
}

/** The documentation, grouped by what a reader is trying to do. */
export const DOC_GROUPS: DocGroup[] = [
  {
    title: 'Learn the language',
    links: [
      {
        name: 'Language reference',
        desc: 'The whole language, section by section: syntax, types, matching, effects, modules, macros, the standard library and the CLI.',
        href: `${DOCS}/reference.md`,
      },
      {
        name: 'Standard library API',
        desc: 'Every public name with its type and effects, generated from the source and gated against it.',
        href: `${DOCS}/stdlib-api.md`,
      },
      {
        name: 'Examples',
        desc: 'Worked programs the repository actually runs: a batch job over a million records and the API-reference generator.',
        href: `${BLOB}/examples/README.md`,
      },
    ],
  },
  {
    title: 'Understand the guarantees',
    links: [
      {
        name: 'Memory model',
        desc: 'The allocator, reference counting and regions. Every rule is marked Holds, Planned, Refused or Withdrawn, and every Holds names its probe.',
        href: `${DOCS}/memory-model.md`,
      },
      {
        name: 'Error model',
        desc: 'How failure is represented, propagated and recovered from: Result, Option, and when to use which.',
        href: `${DOCS}/error-model.md`,
      },
      {
        name: 'Implementation status',
        desc: 'What is complete, functional or partial, with the fixture that proves each row.',
        href: `${DOCS}/status.md`,
      },
      {
        name: 'Compatibility',
        desc: 'What the compat gates promise across releases, and, said out loud, what is not promised.',
        href: `${DOCS}/compatibility.md`,
      },
    ],
  },
  {
    title: 'Tools and integration',
    links: [
      {
        name: 'Diagnostics',
        desc: 'AXDL, AXSYM, NIDs and the JSON stream: the machine-readable surface, in full.',
        href: `${DOCS}/diagnostics.md`,
      },
      {
        name: 'Calling Rust',
        desc: 'The FFI: extern blocks, axiom-bindgen, handles, callbacks, and Rust hosting Axiom.',
        href: `${DOCS}/ffi.md`,
      },
      {
        name: 'Editor setup',
        desc: 'The language server and the tree-sitter grammar, with configurations for Neovim, Helix, Emacs and VS Code.',
        href: `${DOCS}/lsp.md`,
      },
      {
        name: 'Agent harness',
        desc: 'How an agent reads, checks and rewrites Axiom programs, and what the compiler guarantees while it does.',
        href: `${DOCS}/agent-harness.md`,
      },
    ],
  },
  {
    title: 'The project',
    links: [
      {
        name: 'Contributing',
        desc: 'Building, testing, the gate battery, and the rule every change is held to: if you claim it, gate it.',
        href: `${BLOB}/CONTRIBUTING.md`,
      },
      {
        name: 'Changelog',
        desc: 'What actually shipped. Every claim carries the gate that holds it; a claim without one is a comment.',
        href: `${BLOB}/CHANGELOG.md`,
      },
      {
        name: 'Security',
        desc: 'The supported release, the threat model, and how to report a vulnerability.',
        href: `${BLOB}/SECURITY.md`,
      },
    ],
  },
]
