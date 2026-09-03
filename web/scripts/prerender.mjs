/**
 * Render the page into `dist/index.html` at build time.
 *
 * WHAT THIS FIXES, AND WHY IT IS THE MOST IMPORTANT LINE ON THE SITE.
 * Until 2026-09-03 the served HTML was `<div id="root"></div>` and
 * nothing else. Every word on this page — the effect system, the
 * syscall claim, the benchmark, the honest list of what Axiom is not —
 * existed only after React executed.
 *
 * Google renders JavaScript, on a delay and a crawl budget. Bing's
 * renderer is best-effort. And every crawler that feeds a language
 * model — GPTBot, ClaudeBot, PerplexityBot, Applebot — fetches HTML
 * and parses it, and executes none of it.
 *
 * So a project whose whole pitch is that its diagnostics are built to
 * be read by a machine was publishing a homepage that no machine could
 * read. That is not an SEO nit; it is the site contradicting the
 * language.
 *
 * HOW. This is `scripts/smoke.mjs`'s first act with the output KEPT
 * rather than asserted on — the same esbuild bundle, the same Node
 * render, the same `BASE_URL` define. One difference:
 * `renderToString` rather than `renderToStaticMarkup`. Static markup
 * omits the text-node separators `hydrateRoot` matches against, so the
 * server and the client would disagree on every interpolated string.
 * The pair has to be the hydrating one.
 *
 * Runs AFTER `vite build`, on the file Vite has just written.
 */
import { build } from 'esbuild'
import { readFileSync, writeFileSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

const entry = join(process.cwd(), '.prerender-entry.tsx')
const out = join(process.cwd(), '.prerender-bundle.mjs')
const page = join(process.cwd(), 'dist', 'index.html')

writeFileSync(
  entry,
  `import { renderToString } from 'react-dom/server'
import App from './src/App.tsx'
export const html = renderToString(<App />)
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
  // As in smoke.mjs: react-dom's node server build pulls a
  // `require('util')` that ESM cannot serve, so Node resolves React.
  packages: 'external',
  absWorkingDir: process.cwd(),
  define: { 'import.meta.env.BASE_URL': '"/Axiom/"' },
  loader: { '.css': 'empty', '.png': 'text', '.jpg': 'text' },
})

// A React warning during the server render is a real defect and would
// otherwise be invisible — the same reasoning smoke.mjs uses.
const warnings = []
const realError = console.error
const realWarn = console.warn
console.error = (...a) => warnings.push(a.join(' '))
console.warn = (...a) => warnings.push(a.join(' '))

const { html } = await import(pathToFileURL(out).href)

console.error = realError
console.warn = realWarn
rmSync(entry, { force: true })
rmSync(out, { force: true })

let failed = 0
const fail = (m) => {
  console.log('FAIL ' + m)
  failed++
}

if (warnings.length) {
  fail(`the server render produced ${warnings.length} React warning(s)`)
  warnings.slice(0, 5).forEach((w) => console.log('     ' + w))
}

const MOUNT = '<div id="root"></div>'
const doc = readFileSync(page, 'utf8')

// Vite does not minify the mount point away. If that ever changes this
// must FAIL rather than quietly ship an empty page again — which is the
// exact defect this file exists to have fixed once.
if (!doc.includes(MOUNT)) {
  fail(`${page} does not contain ${MOUNT}; nothing was injected`)
}

// A floor, for the reason every floor in this repository has one: a
// render that silently produced almost nothing reads exactly like a
// render that worked. The page is ~90 KB of markup; 20 KB is far below
// that and far above anything a broken render would emit.
if (html.length < 20000) {
  fail(`rendered markup is ${html.length} bytes; the page is much larger than that`)
}

if (failed) {
  console.log(`\n${failed} check(s) failed; dist/index.html was not modified`)
  process.exit(1)
}

writeFileSync(page, doc.replace(MOUNT, `<div id="root">${html}</div>`))
console.log(`ok   prerendered ${html.length.toLocaleString('en-US')} bytes of markup into dist/index.html`)
