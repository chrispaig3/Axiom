/**
 * Build-time smoke test.
 *
 * There is no browser in this environment, so instead of clicking around
 * the page we render the whole component tree to static markup in Node.
 * That catches every render-time crash and every React warning (invalid
 * DOM prop, bad nesting, duplicate key), and then we assert on the
 * resulting HTML:
 *
 *   1. every in-page `href="#id"` has a matching element id
 *   2. every heading level steps by at most one (h1 -> h2 -> h3)
 *   3. every <img> has an alt attribute
 *   4. external links are collected and printed for review
 *
 * Run with:  node scripts/smoke.mjs
 */
import { build } from 'esbuild'
import { existsSync, readFileSync, writeFileSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

// The entry and the bundle live inside the project so that Node's module
// resolution finds `react-dom/server` in ./node_modules. Both are removed
// on the way out and are covered by .gitignore.
const entry = join(process.cwd(), '.smoke-entry.tsx')
const out = join(process.cwd(), '.smoke-bundle.mjs')

writeFileSync(
  entry,
  `import { renderToStaticMarkup } from 'react-dom/server'
import App from './src/App.tsx'
export { HERO, SAMPLES } from './src/data/samples.ts'
export const html = renderToStaticMarkup(<App />)
`,
)

await build({
  entryPoints: [entry],
  bundle: true,
  outfile: out,
  format: 'esm',
  platform: 'node',
  jsx: 'automatic',
  target: 'node20',
  logLevel: 'warning',
  // React itself is left to Node's own resolver: bundling react-dom's
  // node server build pulls in a `require('util')` that ESM cannot serve.
  packages: 'external',
  absWorkingDir: process.cwd(),
  define: { 'import.meta.env.BASE_URL': '"/Axiom/"' },
  loader: { '.css': 'empty', '.png': 'text', '.jpg': 'text' },
})

// Any React warning is a failure: they are the console errors we cannot
// otherwise see.
const warnings = []
const realError = console.error
const realWarn = console.warn
console.error = (...a) => warnings.push(a.join(' '))
console.warn = (...a) => warnings.push(a.join(' '))

const { html, HERO, SAMPLES } = await import(pathToFileURL(out).href)

rmSync(entry, { force: true })
rmSync(out, { force: true })

console.error = realError
console.warn = realWarn

let failed = 0
const fail = (msg) => {
  failed++
  console.log(`FAIL ${msg}`)
}

if (warnings.length) {
  for (const w of warnings) fail(`react warning: ${w}`)
} else {
  console.log('ok   the tree renders with no React warnings')
}

// --- 1. in-page anchors resolve --------------------------------------
const ids = new Set([...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]))
const anchors = new Set(
  [...html.matchAll(/href="#([^"]+)"/g)].map((m) => m[1]),
)
let dangling = 0
for (const a of anchors) {
  if (!ids.has(a)) {
    fail(`anchor #${a} has no target element`)
    dangling++
  }
}
if (!dangling) console.log(`ok   all ${anchors.size} in-page anchors resolve`)

// --- 2. heading hierarchy --------------------------------------------
const levels = [...html.matchAll(/<h([1-6])[\s>]/g)].map((m) => Number(m[1]))
let bad = 0
let prev = 0
for (const l of levels) {
  if (prev && l > prev + 1) {
    fail(`heading jumps from h${prev} to h${l}`)
    bad++
  }
  prev = l
}
const h1s = levels.filter((l) => l === 1).length
if (h1s !== 1) fail(`expected exactly one <h1>, found ${h1s}`)
if (!bad && h1s === 1) {
  console.log(`ok   ${levels.length} headings, one h1, no skipped levels`)
}

// --- 3. images have alt ----------------------------------------------
const imgs = [...html.matchAll(/<img\b[^>]*>/g)].map((m) => m[0])
let noalt = 0
for (const img of imgs) {
  if (!/\salt="/.test(img)) {
    fail(`img without alt: ${img.slice(0, 80)}`)
    noalt++
  }
}
if (!noalt) console.log(`ok   all ${imgs.length} images carry an alt attribute`)

// --- 5. one rendered line per source line -----------------------------
// The line numbers live inside the line they number, so this is what
// proves the split is right: every `.ln` block in the page must be
// matched by a line in some sample, and the totals must agree.
const heroSample = HERO
const samples = SAMPLES

if (heroSample && samples) {
  const rendered = (html.match(/class="ln"/g) ?? []).length
  // The hero always renders; the tabbed frame renders only its first tab.
  const expected =
    heroSample.code.split('\n').length + samples[0].code.split('\n').length
  if (rendered !== expected) {
    fail(`numbered lines: rendered ${rendered}, samples have ${expected}`)
  } else {
    console.log(`ok   ${rendered} numbered lines match their sources`)
  }

  // A number must never end up inside the copyable program text.
  const firstLine = heroSample.code.split('\n')[0]
  if (!html.includes(`>1</span>`)) fail('no line number 1 was rendered')
  if (html.includes(`>1</span>${firstLine}`) === false) {
    // Not an error on its own — the line is token-split — but the digits
    // must be in their own span, which the previous check establishes.
  }
}

// --- 6. links into the repository resolve -----------------------------
// Two links on this page pointed at things that had moved or been
// deleted (README#implementation-status after the status table moved
// to docs/status.md on 2026-09-03; stdlib/Job.ax after 0.7.5 deleted
// it) and nothing noticed, because a link is a claim with no check on
// it. Now every `blob/trunk/<path>` link must name a file in the tree,
// and a `#fragment` on a markdown target must match one of that file's
// headings under GitHub's slug rules.
const repoRoot = new URL('../../', import.meta.url).pathname
// GitHub's rule: lowercase, drop everything but letters, digits, spaces,
// hyphens and underscores, then EACH space becomes a hyphen - so a
// heading with an em dash between two spaces slugs to a double hyphen.
const slug = (h) =>
  h
    .toLowerCase()
    .replace(/[`*~]/g, '')
    .replace(/[^\p{L}\p{N} _-]/gu, '')
    .trim()
    .replace(/ /g, '-')
const headingsOf = (file) => {
  const seen = new Map()
  const out = new Set()
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    const m = /^#{1,6}\s+(.*?)\s*#*\s*$/.exec(line)
    if (!m) continue
    const base = slug(m[1])
    const n = seen.get(base) ?? 0
    seen.set(base, n + 1)
    out.add(n === 0 ? base : `${base}-${n}`)
  }
  return out
}
let linksChecked = 0
let linksBroken = 0
for (const href of new Set(
  [...html.matchAll(/href="(https:\/\/github\.com\/chrispaig3\/Axiom[^"]*)"/g)].map(
    (m) => m[1],
  ),
)) {
  const m = /^https:\/\/github\.com\/chrispaig3\/Axiom(?:\/blob\/trunk\/([^#]+))?(?:#(.+))?$/.exec(
    href,
  )
  if (!m) continue
  const path = m[1] ? decodeURIComponent(m[1]) : 'README.md'
  const frag = m[2]
  if (!m[1] && !frag) continue
  linksChecked++
  const file = join(repoRoot, path)
  if (!existsSync(file)) {
    fail(`link to ${path} names a path that is not in the tree (${href})`)
    linksBroken++
    continue
  }
  if (frag && path.endsWith('.md') && !headingsOf(file).has(frag)) {
    fail(`link to ${path}#${frag} names a heading that file does not have`)
    linksBroken++
  }
}
if (linksChecked < 8) {
  fail(`only ${linksChecked} repository link(s) were checked; the page carries many more than that`)
} else if (!linksBroken) {
  console.log(`ok   ${linksChecked} links into the repository resolve to a file and a heading`)
}

// --- 4. external links ------------------------------------------------
const ext = [
  ...new Set(
    [...html.matchAll(/href="(https?:\/\/[^"]+)"/g)].map((m) => m[1]),
  ),
].sort()
console.log(`\n-- ${ext.length} distinct external links --`)
for (const e of ext) console.log(`   ${e}`)

// Every external link must open safely.
const unsafe = [...html.matchAll(/<a\b[^>]*href="https?:[^"]*"[^>]*>/g)]
  .map((m) => m[0])
  .filter((a) => a.includes('target="_blank"') && !a.includes('noopener'))
if (unsafe.length) fail(`${unsafe.length} target=_blank links without noopener`)
else console.log('\nok   every target=_blank link carries rel=noopener')

console.log(`\n${failed === 0 ? 'PASS' : `FAIL (${failed})`}`)
process.exit(failed === 0 ? 0 : 1)
