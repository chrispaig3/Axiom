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
import { writeFileSync, rmSync } from 'node:fs'
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

const { html } = await import(pathToFileURL(out).href)

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
