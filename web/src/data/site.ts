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
 * Every figure the page states, with the command that establishes it.
 * `check-claims.mjs` re-derives each from the tree on every build. A
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
    n: '108,651',
    label: 'lines of Axiom in the compiler that compiles Axiom',
    evidence: 'cat self_host/*.ax | wc -l',
  },
  {
    key: 'codes',
    n: '98',
    label: 'diagnostic codes, each with a written explanation',
    evidence: 'axiom explain --list',
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
  const found = STATS.find((s) => s.key === key)
  if (!found) throw new Error(`site.ts: no STATS entry keyed '${key}'`)
  return found.n
}

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
