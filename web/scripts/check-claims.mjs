/**
 * Hold the website's numbers to the repository they describe.
 *
 * The site states counts about this tree. Every one it has stated moved
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
const sections = [
  ...readdirSync(sectionsDir)
    .filter((f) => f.endsWith('.tsx'))
    .map((f) => new URL(f, sectionsDir)),
  // Card and FAQ prose lives in data, and says figures too.
  new URL('../src/data/content.ts', import.meta.url),
]

/** JSX to something close to what a reader sees. */
const rendered = (src) =>
  src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, ' ')
    .replace(/\$?\{stat\('([a-zA-Z]+)'\)\}/g, (_, k) => {
      const i = CLAIMS.findIndex((c) => c.key === k)
      return i < 0 ? '?' : CLAIMS[i].format(CLAIMS[i].derive())
    })
    .replace(/\{' '\}/g, ' ')
    .replace(/<\/?[^>]+>/g, '')
    .replace(/\s+/g, ' ')

let prose_seen = 0
for (const file of sections) {
  const text = rendered(readFileSync(file, 'utf8'))
  for (const claim of CLAIMS) {
    if (!claim.prose) continue
    const want = claim.format(claim.derive())
    for (const m of text.matchAll(claim.prose)) {
      prose_seen++
      if (m[1] !== want) {
        fail(
          `${file.pathname.split('/').pop()}: "${m[0].trim()}" says ${m[1]}, the tree says ${want}` +
            ` — write {stat('${claim.key}')} rather than the number`,
        )
      }
    }
  }
}

// A floor, for the reason every floor in this repository exists: a
// regex that has quietly stopped matching reports success. Two
// sentences carry a figure since the page was cut down (the pillars'
// line count and code count), so the floor is 2.
if (prose_seen < 2) {
  fail(
    `the prose sweep matched ${prose_seen} sentence(s) across ` +
      `${sections.length} file(s); the floor is 2 — the patterns no ` +
      'longer find the sentences they were written for',
  )
} else {
  console.log(`ok   ${prose_seen} prose repetitions of a figure, all matching`)
}

// THE LISTS, not only the counts. A count can agree while the list it
// counts has swapped a member; these are checked name for name.
const siteSrc = readFileSync(new URL('../src/data/site.ts', import.meta.url), 'utf8')
const contentSrc = readFileSync(new URL('../src/data/content.ts', import.meta.url), 'utf8')

// TARGETS: exactly README's "Supported:" sentence, as a set.
{
  const readme = readFileSync(new URL('../../README.md', import.meta.url), 'utf8')
  // The sentence wraps in the README, so read it to its full stop.
  const line = /^Supported: ([\s\S]*?)\./m.exec(readme)
  const want = line ? [...line[1].matchAll(/`([a-z0-9_-]+)`/g)].map((m) => m[1]).sort() : []
  const targets = /export const TARGETS[\s\S]*?\n\]/.exec(siteSrc)?.[0] ?? ''
  const got = [...targets.matchAll(/name: '([^']+)'/g)].map((m) => m[1]).sort()
  if (!want.length) fail("README.md has no 'Supported:' line; the targets check read nothing")
  else if (JSON.stringify(want) !== JSON.stringify(got)) {
    fail(`TARGETS in site.ts is not README's supported list\n     README: ${want.join(', ')}\n     site:   ${got.join(', ')}`)
  } else console.log(`ok   the ${got.length} targets on the page are README's supported list`)

  const sourceLine = /^Source-only: ([\s\S]*?)\./m.exec(readme)
  const sourceWant = sourceLine ? [...sourceLine[1].matchAll(/`([a-z0-9_-]+)`/g)].map((m) => m[1]).sort() : []
  const sourceEntries = /export const SOURCE_ONLY[\s\S]*?\n\]/.exec(siteSrc)?.[0] ?? ''
  const sourceGot = [...sourceEntries.matchAll(/'([a-z0-9_-]+)'/g)].map((m) => m[1]).sort()
  if (!sourceWant.length) fail("README.md has no 'Source-only:' line; the target check read nothing")
  else if (JSON.stringify(sourceWant) !== JSON.stringify(sourceGot)) {
    fail(`SOURCE_ONLY in site.ts is not README's source-only list\n     README: ${sourceWant.join(', ')}\n     site:   ${sourceGot.join(', ')}`)
  } else console.log(`ok   the ${sourceGot.length} source-only targets agree with README`)
}

// STATUS: every row's feature and status are docs/status.md's, exactly.
{
  const status = readFileSync(new URL('../../docs/status.md', import.meta.url), 'utf8')
  const table = new Map()
  for (const row of status.split('\n')) {
    const cells = row.split('|')
    if (cells.length < 4 || !row.startsWith('| ')) continue
    const bold = /^\s*\*\*(.*?)\*\*\s*$/.exec(cells[2] ?? '')
    if (bold) table.set(cells[1].trim(), bold[1])
  }
  const rows = [...contentSrc.matchAll(/\{ feature: '((?:[^'\\]|\\.)*)', status: '((?:[^'\\]|\\.)*)'/g)]
  let bad = 0
  for (const [, feature, st] of rows) {
    const have = table.get(feature)
    if (have === undefined) {
      fail(`status panel names '${feature}', which docs/status.md has no row for`)
      bad++
    } else if (have !== st) {
      fail(`status panel says '${feature}' is '${st}'; docs/status.md says '${have}'`)
      bad++
    }
  }
  if (rows.length < 15) fail(`read only ${rows.length} status rows from content.ts; the parse broke`)
  else if (!bad) console.log(`ok   all ${rows.length} status rows match docs/status.md word for word`)
}

if (failed) {
  console.log(
    `\n${failed} claim(s) no longer match the repository. Update src/data/site.ts` +
      ' or src/data/content.ts rather than this checker.',
  )
  process.exit(1)
}

console.log('\nPASS every number on the site matches the tree it describes')
