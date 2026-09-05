export const VERSION = '0.7.5'
export const REPO = 'https://github.com/chrispaig3/Axiom'
export const DOCS = `${REPO}/blob/trunk/docs`
export const BLOB = `${REPO}/blob/trunk`

/** README.md, "Install a release". */
export const INSTALL_CMD =
  'curl -fsSL https://raw.githubusercontent.com/chrispaig3/axiom/trunk/scripts/install.sh | bash'

export const PATH_CMD = 'export PATH="$HOME/.axiom/bin:$PATH"'

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
    n: '102,952',
    label: 'lines of Axiom in the compiler that compiles Axiom',
    evidence: 'cat self_host/*.ax | wc -l',
  },
  {
    key: 'axfiles',
    n: '634',
    label: '.ax files in the tree, every one parsed by the grammar gate',
    evidence: "git ls-files '*.ax' | wc -l",
  },
  {
    key: 'codes',
    n: '79',
    label: 'diagnostic codes, each with a written explanation',
    evidence: 'axiom explain --list',
  },
  {
    key: 'gates',
    n: '80',
    label: 'gate scripts in the battery that runs before a push',
    evidence: "ls scripts/check-*.sh | wc -l",
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
    n: '23',
    label: 'LSP requests the server answers',
    evidence:
      "every JSON-RPC method self_host/lsp.ax names, minus the four notifications",
  },
]

/**
 * The figure behind a key, for a SENTENCE that repeats one of the four.
 *
 * Three sentences used to spell their number out, and all three had
 * drifted: the hero read `87,494` lines while the stat block on the same
 * page read `96,950`, and two sections said `68` diagnostic codes where
 * `axiom explain --list` prints 77. `check-claims.mjs` held the four
 * `n:` values to the tree and never looked at the prose beside them.
 *
 * A number written twice is a second copy of the fact with no gate on
 * it - `scripts/lib/version-sites.sh` makes the same argument and
 * refuses to write its own count down at all. So prose calls this
 * instead of spelling the number, and `check-claims.mjs` now sweeps
 * every section for a literal that equals one of these and fails
 * naming it. There is one copy again.
 */
export function stat(key: string): string {
  const found = STATS.find((s) => s.key === key) ?? FACTS.find((s) => s.key === key)
  if (!found) throw new Error(`site.ts: no STATS or FACTS entry keyed '${key}'`)
  return found.n
}

export interface DocLink {
  name: string
  desc: string
  href: string
}

/** The five a newcomer actually needs; the rest are one link away. */
export const DOC_LINKS: DocLink[] = [
  {
    name: 'reference.md',
    desc: 'The language: syntax, types, pattern matching, effects, modules, operators, the standard library and the compiler pipeline.',
    href: `${DOCS}/reference.md`,
  },
  {
    name: 'diagnostics.md',
    desc: 'The code ranges, the stable slugs, and the agent-facing output formats in full.',
    href: `${DOCS}/diagnostics.md`,
  },
  {
    name: 'memory-model.md',
    desc: 'The normative specification. Each rule is marked Holds, Planned, Refused or Withdrawn, and every Holds names its probe.',
    href: `${DOCS}/memory-model.md`,
  },
  {
    name: 'error-model.md',
    desc: 'How failure is represented: Result, Option, and the rules for which to use.',
    href: `${DOCS}/error-model.md`,
  },
  {
    name: 'compatibility.md',
    desc: 'What the compat gates promise across releases — and, said out loud, what is not promised.',
    href: `${DOCS}/compatibility.md`,
  },
  {
    name: 'CHANGELOG.md',
    desc: 'What actually shipped. Its own rule: every claim carries the gate that holds it, and a claim without one is a comment.',
    href: `${BLOB}/CHANGELOG.md`,
  },
]
