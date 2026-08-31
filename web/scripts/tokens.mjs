/**
 * Print every sample's tokens with the capture the highlighter assigned,
 * so a wrong role is visible without a browser. Trivia is elided.
 *
 *   node scripts/tokens.mjs           # all samples
 *   node scripts/tokens.mjs shapes    # one, by id
 */
import { build } from 'esbuild'
import { rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

const entry = join(process.cwd(), '.tok-entry.ts')
const out = join(process.cwd(), '.tok-bundle.mjs')

writeFileSync(
  entry,
  `export { highlight } from './src/lib/highlight.ts'
export { SAMPLES, HERO } from './src/data/samples.ts'
`,
)

await build({
  entryPoints: [entry],
  bundle: true,
  outfile: out,
  format: 'esm',
  platform: 'node',
  target: 'node20',
  logLevel: 'warning',
  packages: 'external',
  absWorkingDir: process.cwd(),
})

const { highlight, SAMPLES, HERO } = await import(
  pathToFileURL(out).href
)
rmSync(entry, { force: true })
rmSync(out, { force: true })

const only = process.argv[2]
const all = [
  [HERO.id, HERO.code],
  ...SAMPLES.map((s) => [s.id, s.code]),
]

for (const [id, code] of all) {
  if (only && id !== only) continue
  console.log(`\n===== ${id} =====`)
  for (const t of highlight(code)) {
    if (t.capture === 'text' || !t.text.trim()) continue
    console.log(`${t.capture.padEnd(22)} ${t.text}`)
  }
}
