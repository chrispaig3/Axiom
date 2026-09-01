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
import { readFileSync } from 'node:fs'

const repo = new URL('../..', import.meta.url).pathname
const sh = (cmd) => execSync(cmd, { cwd: repo, encoding: 'utf8' }).trim()

/** Each claim, with the command that establishes it. */
const CLAIMS = [
  {
    what: 'lines of Axiom in the compiler',
    derive: () => sh("cat self_host/*.ax | wc -l"),
    format: (n) => Number(n).toLocaleString('en-US'),
  },
  {
    what: '.ax files in the tree',
    derive: () => sh("find . -name '*.ax' -not -path './.git/*' | wc -l"),
    format: (n) => String(Number(n)),
  },
  {
    what: 'diagnostic codes',
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
    what: 'gate scripts',
    derive: () => sh("ls scripts/ | grep -c '^check-.*\\.sh$'"),
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

// One prose claim repeats the file count, and prose drifts the same way.
// Matched against the sentence's TEXT rather than its JSX: the first
// version of this keyed on the literal `all 581{' '}` and failed the
// build when the surrounding markup was reworked — a checker reporting
// on itself rather than on the claim.
const editorsSrc = readFileSync(
  new URL('../src/sections/Editors.tsx', import.meta.url),
  'utf8',
)
const editorsText = editorsSrc
  .replace(/\{' '\}/g, ' ')
  .replace(/<\/?[^>]+>/g, '')
  .replace(/\s+/g, ' ')

const axFiles = CLAIMS[1].format(CLAIMS[1].derive())
const said = /all (\d[\d,]*) \.ax files/.exec(editorsText)
if (!said) {
  fail(
    'Editors.tsx: no "all <N> .ax files" sentence found — the grammar-gate' +
      ' claim was reworded, so this check no longer reads it',
  )
} else if (said[1] !== axFiles) {
  fail(
    `Editors.tsx: the grammar-gate sentence says ${said[1]}, the tree says ${axFiles}`,
  )
} else {
  console.log(`ok   Editors.tsx repeats the .ax count as ${axFiles}`)
}

if (failed) {
  console.log(
    `\n${failed} claim(s) no longer match the repository. Update src/data/site.ts` +
      ' (and the sentence in Editors.tsx) rather than this checker.',
  )
  process.exit(1)
}

console.log('\nPASS every number on the site matches the tree it describes')
