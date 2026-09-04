/**
 * Hold the website's numbers to the repository they describe.
 *
 * The site states four counts about this tree. Every one of them moved
 * the first time trunk advanced under it — 580 `.ax` files became 581,
 * 87,373 lines became 87,494, 61 gates became 62 — and nothing on the
 * page would have noticed. A number that no longer matches the thing it
 * counts is exactly the defect this repository calls a claim without a
 * check, so the claims carry one.
 *
 * This runs as part of `npm run build`, which is what the Pages workflow
 * runs, so a drifted figure fails the DEPLOY. It is deliberately not a
 * gate in `scripts/`: the compiler's battery should not go red because a
 * sentence on a website is stale, and a website should not ship a false
 * number because the battery is busy.
 *
 *   node scripts/check-claims.mjs
 */
import { execSync } from 'node:child_process'
import { readdirSync, readFileSync } from 'node:fs'

const repo = new URL('../..', import.meta.url).pathname
const sh = (cmd) => execSync(cmd, { cwd: repo, encoding: 'utf8' }).trim()

/** Each claim, with the command that establishes it. */
const CLAIMS = [
  {
    key: 'lines',
    what: 'lines of Axiom in the compiler',
    prose: /(\d[\d,]*)\s+lines of Axiom/g,
    derive: () => sh("cat self_host/*.ax | wc -l"),
    format: (n) => Number(n).toLocaleString('en-US'),
  },
  {
    key: 'axfiles',
    what: '.ax files in the tree',
    prose: /all (\d[\d,]*)\s+\.ax files/g,
    // `.claude/worktrees/` MUST be excluded and this checker did not.
    // Each agent worktree is a full checkout, so with twenty of them
    // present the count read 12,621 against a real 587 - a number the
    // build would then have demanded the site publish. A claim checker
    // that fails the build over its own miscount is worse than none,
    // because the obvious way to make it pass is to write its answer
    // into the page. `node_modules` is excluded for the same reason it
    // is excluded from the Linux harness's tar: a nested copy of
    // somebody else's tree is not this tree.
    derive: () =>
      sh(
        "find . -name '*.ax' -not -path './.git/*'" +
          " -not -path './.claude/*' -not -path '*/node_modules/*' | wc -l",
      ),
    format: (n) => String(Number(n)),
  },
  {
    key: 'codes',
    what: 'diagnostic codes',
    prose: /(?:all|one of the)\s+(\d[\d,]*)\s+(?:diagnostic )?codes?\b/g,
    // The registry `axiom explain --list` prints, read from its source so
    // this needs no built compiler.
    derive: () =>
      String(
        new Set(
          (sh("sed -n '22p' self_host/explain.ax").match(/AX\d{4}/g) ?? []),
        ).size,
      ),
    format: (n) => String(Number(n)),
  },
  {
    key: 'gates',
    what: 'gate scripts',
    prose: /(\d[\d,]*)\s+gate scripts?\b/g,
    derive: () => sh("ls scripts/ | grep -c '^check-.*\\.sh$'"),
    format: (n) => String(Number(n)),
  },
  // After STATS in site.ts come the FACTS: figures the prose repeats
  // that the ticker does not show. Same order here as there.
  {
    key: 'lspRequests',
    what: 'LSP requests the server answers',
    prose: /answers\s+(\d[\d,]*)\s+requests\b/g,
    // Every JSON-RPC method the server names, minus the four that are
    // notifications rather than requests (three from the client, one
    // the server sends). `axiom/expandMacro`, the one request that is
    // this server's own, counts. The page said "twenty-four" until
    // 2026-09-04, spelled out where no checker could read it; the
    // server answered twenty-three.
    derive: () => {
      const all = sh(
        "grep -o '\"\\(textDocument\\|workspace\\|callHierarchy\\|completionItem\\|axiom\\)/[A-Za-z/]*\"' self_host/lsp.ax | sort -u",
      )
        .split('\n')
        .filter(Boolean)
      const notifications = new Set([
        '"textDocument/didOpen"',
        '"textDocument/didChange"',
        '"textDocument/didClose"',
        '"textDocument/publishDiagnostics"',
      ])
      return String(all.filter((m) => !notifications.has(m)).length)
    },
    format: (n) => String(Number(n)),
  },
]

// The site's figures, in the order STATS declares them.
const src = readFileSync(new URL('../src/data/site.ts', import.meta.url), 'utf8')
const stated = [...src.matchAll(/^\s*n: '([^']+)',$/gm)].map((m) => m[1])

let failed = 0
const fail = (msg) => {
  console.log(`FAIL ${msg}`)
  failed++
}

if (stated.length !== CLAIMS.length) {
  console.log(
    `FAIL read ${stated.length} figure(s) out of STATS, expected ${CLAIMS.length}` +
      ' — the parse broke and this check is verifying almost nothing',
  )
  process.exit(1)
}

for (const [i, claim] of CLAIMS.entries()) {
  const want = claim.format(claim.derive())
  const got = stated[i]
  if (want !== got) {
    console.log(`FAIL ${claim.what}: the site says ${got}, the tree says ${want}`)
    failed++
  } else {
    console.log(`ok   ${claim.what}: ${got}`)
  }
}

// THE PROSE SWEEP, over every section rather than one sentence in one
// file.
//
// Three sentences repeated a figure and all three had drifted by
// 2026-09-03: the hero read `87,494` lines of Axiom while the stat
// block on the SAME PAGE read `96,950`, and two sections said `68`
// diagnostic codes where `axiom explain --list` prints 77. The four
// `n:` values were checked against the tree on every build; the prose
// beside them was not, except for one hardcoded sentence in
// Editors.tsx that this replaces.
//
// The sections now call `stat('key')` instead of spelling a number,
// so the copies are gone rather than merely re-synchronised. This
// still sweeps, for two reasons: a new sentence can always spell a
// number out again, and a sweep that finds NOTHING has to say so.
// `{stat('key')}` is substituted before matching, so a converted
// sentence is checked exactly like a literal one - the check does not
// reward the conversion by looking away from it.
const sectionsDir = new URL('../src/sections/', import.meta.url)
const sections = readdirSync(sectionsDir).filter((f) => f.endsWith('.tsx'))

/** JSX to something close to what a reader sees. */
const rendered = (src) =>
  src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, ' ')
    .replace(/\{stat\('([a-zA-Z]+)'\)\}/g, (_, k) => {
      const i = CLAIMS.findIndex((c) => c.key === k)
      return i < 0 ? '?' : CLAIMS[i].format(CLAIMS[i].derive())
    })
    .replace(/\{' '\}/g, ' ')
    .replace(/<\/?[^>]+>/g, '')
    .replace(/\s+/g, ' ')

let prose_seen = 0
for (const file of sections) {
  const text = rendered(readFileSync(new URL(file, sectionsDir), 'utf8'))
  for (const claim of CLAIMS) {
    if (!claim.prose) continue
    const want = claim.format(claim.derive())
    for (const m of text.matchAll(claim.prose)) {
      prose_seen++
      if (m[1] !== want) {
        fail(
          `${file}: "${m[0].trim()}" says ${m[1]}, the tree says ${want}` +
            ` — write {stat('${claim.key}')} rather than the number`,
        )
      }
    }
  }
}

// A floor, for the reason every floor in this repository exists: a
// regex that has quietly stopped matching reports success. Four
// sentences carry a figure today (hero lines, explain codes, agents
// codes, the LSP request count) plus the tree-sitter .ax count = 5.
if (prose_seen < 5) {
  fail(
    `the prose sweep matched ${prose_seen} sentence(s) across ` +
      `${sections.length} section(s); the floor is 5 — the patterns no ` +
      'longer find the sentences they were written for',
  )
} else {
  console.log(`ok   ${prose_seen} prose repetitions of a figure, all matching`)
}

if (failed) {
  console.log(
    `\n${failed} claim(s) no longer match the repository. Update src/data/site.ts` +
      ' (and the sentence in Editors.tsx) rather than this checker.',
  )
  process.exit(1)
}

console.log('\nPASS every number on the site matches the tree it describes')
