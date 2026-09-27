/**
 * Hold every program and every piece of compiler output on the site to
 * the compiler that produces it.
 *
 * The site has always said "every program here was compiled and run,
 * and the output under it is real". Until this file that was a promise
 * kept by hand: somebody ran each sample once, pasted stdout into
 * `samples.ts`, and nothing re-ran it. A promise nothing re-checks is
 * the thing this repository calls a claim without a gate.
 *
 * So, against a real compiler, for every entry in `src/data/samples.ts`:
 *
 *   PROGRAMS   `axiom fmt --check` passes (what is shown IS the
 *              formatter's normal form), then `axiom run` (or
 *              `axiom test`) exits 0 and prints exactly `output`.
 *   BREAKS     each broken program fails `axiom check` with exit 1, and
 *              stderr is byte-for-byte the `human` report and the `ai`
 *              line the page shows.
 *   QUOTES     the agent-notation blocks: AXDL, JSON and human reports,
 *              and the AXSYM table and lines, re-rendered from their
 *              source files and compared.
 *
 * It is NOT part of `npm run build`, on purpose: the Pages workflow
 * deliberately builds no compiler (see `.github/workflows/pages.yml`),
 * and a copy fix must not wait three minutes for a bootstrap. Run it
 * whenever a sample, the compiler or the standard library changes:
 *
 *   ./scripts/bootstrap-from-seed.sh --install .axiom-bin   # once
 *   cd web && npm run check:samples
 *
 * `$AXIOM` overrides the compiler, `$AXIOM_STDLIB` the library. With no
 * compiler to run, this FAILS rather than skips: a check that reports
 * success without having looked is worse than none.
 */
import { build } from 'esbuild'
import { spawnSync } from 'node:child_process'
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

const repo = new URL('../..', import.meta.url).pathname
const axiom = process.env.AXIOM ?? join(repo, '.axiom-bin', 'axiom')
const stdlib = process.env.AXIOM_STDLIB ?? join(repo, 'stdlib')

if (!existsSync(axiom)) {
  console.log(
    `FAIL no compiler at ${axiom}\n` +
      '     build one with ./scripts/bootstrap-from-seed.sh --install .axiom-bin,\n' +
      '     or point $AXIOM at one',
  )
  process.exit(1)
}

// --- load the site's data -------------------------------------------
const entry = join(process.cwd(), '.samples-entry.ts')
const out = join(process.cwd(), '.samples-bundle.mjs')
writeFileSync(entry, `export * from './src/data/samples.ts'\n`)
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
const data = await import(pathToFileURL(out).href)
rmSync(entry, { force: true })
rmSync(out, { force: true })

// --- run the compiler in a scratch directory --------------------------
const work = mkdtempSync(join(tmpdir(), 'axiom-site-'))
process.on('exit', () => rmSync(work, { recursive: true, force: true }))

// The library is linked in as `./stdlib` and named RELATIVELY, so a
// diagnostic that points into it (an `AX3049` call path does) prints
// `stdlib/IO.ax:42`, the same on every machine, rather than this one's
// absolute path.
symlinkSync(stdlib, join(work, 'stdlib'))
const env = { ...process.env, AXIOM_STDLIB: 'stdlib' }

/** Write `code` as `file` in the scratch directory and run `args`. */
function ax(file, code, args) {
  writeFileSync(join(work, file), code.endsWith('\n') ? code : `${code}\n`)
  const r = spawnSync(axiom, args, { cwd: work, env, encoding: 'utf8', timeout: 120_000 })
  return { status: r.status, stdout: r.stdout ?? '', stderr: r.stderr ?? '' }
}

const trimEnd = (s) => s.replace(/\s+$/, '')

// The human renderer is coloured ALWAYS, even into a pipe - a choice
// `self_host/style.ax` explains - and the page paints its own colour
// over plain text (`src/components/Terminal.tsx`). So the escapes are
// removed before comparing, and only the SGR form the palette emits.
// eslint-disable-next-line no-control-regex
const plain = (s) => s.replace(/\x1b\[[0-9;]*m/g, '')

let failed = 0
let checked = 0
const fail = (what, msg) => {
  failed++
  console.log(`FAIL ${what}: ${msg}`)
}

/** Report the first line where `want` and `got` part company. */
function differs(what, label, want, got) {
  const a = trimEnd(want).split('\n')
  const b = trimEnd(got).split('\n')
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    if (a[i] !== b[i]) {
      fail(
        what,
        `${label} differs at line ${i + 1}\n` +
          `       site:     ${JSON.stringify(a[i] ?? '<end>')}\n` +
          `       compiler: ${JSON.stringify(b[i] ?? '<end>')}`,
      )
      return true
    }
  }
  return false
}

// --- 1. programs -----------------------------------------------------
const programs = [data.HERO, ...data.TOUR]
for (const p of programs) {
  const what = `${p.id} (${p.file})`
  checked++

  const fmt = ax(p.file, p.code, ['fmt', '--check', p.file])
  if (fmt.status !== 0) {
    fail(what, `not in axiom fmt normal form: ${trimEnd(fmt.stderr || fmt.stdout)}`)
    continue
  }

  const mode = p.mode ?? 'run'
  // A crate is passed exactly as `--crate` spells it on the page, made
  // absolute: the driver builds and links the archive (cargo must be on
  // PATH; with no cargo the build is refused as AX4004, and so is this).
  const crate = p.crate ? ['--crate', join(repo, p.crate)] : []
  const r = ax(p.file, p.code, [mode, p.file, ...crate])
  if (r.status !== 0) {
    fail(what, `axiom ${mode} exited ${r.status}\n${trimEnd(plain(r.stderr))}`)
    continue
  }
  if (differs(what, 'stdout', p.output, r.stdout)) continue

  // The Rust half of an FFI sample is QUOTED, so every blank-separated
  // item of it must be a verbatim slice of the file it names.
  if (p.rust) {
    const src = readFileSync(join(repo, p.rust.path), 'utf8')
    const missing = p.rust.code.split('\n\n').filter((item) => !src.includes(item))
    if (missing.length) {
      fail(what, `${missing.length} Rust item(s) are not in ${p.rust.path}:\n${missing[0]}`)
      continue
    }
  }

  // The refusal: a real compile of the changed program, under the SAME
  // file name, so every path in the report is the one the page shows.
  if (p.refusal) {
    const bad = ax(p.file, p.refusal.code, ['check', p.file])
    if (bad.status !== 1) {
      fail(what, `the refusal compiled (exit ${bad.status}); the page says it is refused`)
      continue
    }
    if (differs(what, 'refusal report', p.refusal.human, plain(bad.stderr))) continue
    const f = ax(p.file, p.refusal.code, ['fmt', '--check', p.file])
    if (f.status !== 0) {
      fail(what, 'the refused program is not in axiom fmt normal form')
      continue
    }
  }

  console.log(
    `ok   ${what}: formatted, ${mode === 'test' ? 'tests pass' : 'runs'}, prints what the page says` +
      (p.refusal ? ', refusal matches' : '') +
      (p.rust ? ', Rust quoted verbatim' : ''),
  )
}

// The hero's terminal: each tab's steps, run in order, filtered the way
// its prompt's pipe says, must print exactly what the tab shows.
for (const t of data.HERO_SESSIONS) {
  checked++
  const what = `session/${t.id}`
  writeFileSync(join(work, data.HERO.file), `${data.HERO.code}\n`)
  let out = ''
  let bad = false
  for (const step of t.steps) {
    const local = step[0].startsWith('./')
    const r = spawnSync(local ? join(work, step[0]) : axiom, local ? step.slice(1) : step, {
      cwd: work,
      env,
      encoding: 'utf8',
      timeout: 120_000,
    })
    if (r.status !== 0) {
      fail(what, `${step.join(' ')} exited ${r.status}: ${trimEnd(plain(r.stderr ?? ''))}`)
      bad = true
      break
    }
    out += r.stdout ?? ''
  }
  if (bad) continue
  let lines = trimEnd(out).split('\n')
  if (t.grep) lines = lines.filter((l) => l.includes(t.grep))
  if (t.head) lines = lines.slice(0, t.head)
  if (!differs(what, 'output', t.output, lines.join('\n'))) {
    console.log(`ok   ${what}: \`${t.command}\` prints what the tab shows`)
  }
}

// The hero's notes each name a line and a token that line must hold.
{
  checked++
  const lines = data.HERO.code.split('\n')
  const off = data.HERO_NOTES.filter((n) => !(lines[n.line - 1] ?? '').includes(n.token))
  if (off.length) {
    for (const n of off) fail('hero notes', `line ${n.line} no longer holds ${JSON.stringify(n.token)}`)
  } else {
    console.log(`ok   hero notes: all ${data.HERO_NOTES.length} point at the line they describe`)
  }
}

// `axiom new`, then `axiom run` inside the project it made.
{
  checked++
  const what = 'new-project'
  const name = data.NEW_PROJECT.name
  const made = spawnSync(axiom, ['new', name], { cwd: work, env, encoding: 'utf8' })
  const dir = join(work, name)
  if (made.status !== 0) {
    fail(what, `axiom new exited ${made.status}: ${trimEnd(made.stderr)}`)
  } else if (differs(what, 'Main.ax', data.NEW_PROJECT.main, readFileSync(join(dir, 'Main.ax'), 'utf8'))) {
    // reported
  } else {
    const r = spawnSync(axiom, ['run'], { cwd: dir, env: { ...env, AXIOM_STDLIB: stdlib }, encoding: 'utf8' })
    if (r.status !== 0) fail(what, `axiom run in the project exited ${r.status}`)
    else if (!differs(what, 'stdout', data.NEW_PROJECT.output, r.stdout)) {
      console.log(`ok   ${what}: axiom new writes the Main.ax shown, and axiom run prints its line`)
    }
  }
}

// --- 2. the broken programs -------------------------------------------
for (const b of data.BREAKS) {
  const what = `break/${b.id}`
  checked++
  const human = ax(data.BREAK_FILE, b.code, ['check', data.BREAK_FILE])
  const ai = ax(data.BREAK_FILE, b.code, ['--diagnostic-format=ai', 'check', data.BREAK_FILE])
  if (human.status !== 1) {
    fail(what, `axiom check exited ${human.status}, the page says it is refused`)
    continue
  }
  const bad = differs(what, 'human report', b.human, plain(human.stderr)) ||
    differs(what, 'ai report', b.ai, ai.stderr)
  if (!bad) console.log(`ok   ${what}: refused, both reports match`)
}

// --- 3. quoted compiler output -----------------------------------------
{
  checked++
  const what = 'quote/undefined-suggestion'
  const a = ax('main.ax', data.FIX_SOURCE, ['--diagnostic-format=ai', 'check', 'main.ax'])
  const j = ax('main.ax', data.FIX_SOURCE, ['--diagnostic-format=json', 'check', 'main.ax'])
  if (!differs(what, 'ai', data.FIX_AXDL, a.stderr.split('\n')[0] ?? '') &&
      !differs(what, 'json', data.FIX_JSON, j.stderr.split('\n')[0] ?? '')) {
    console.log(`ok   ${what}: AXDL and JSON match`)
  }
}
{
  checked++
  const what = 'quote/axsym'
  const t = ax('main.ax', data.AXSYM_SOURCE, ['symbols', 'main.ax'])
  const a = ax('main.ax', data.AXSYM_SOURCE, ['--diagnostic-format=ai', 'symbols', 'main.ax'])
  if (!differs(what, 'table', data.AXSYM_TABLE, t.stdout) &&
      !differs(what, 'AXSYM', data.AXSYM_AI, a.stdout)) {
    console.log(`ok   ${what}: table and AXSYM lines match`)
  }
}

// A floor: a data module that silently exported nothing would pass.
if (checked < 15) {
  fail('floor', `only ${checked} item(s) were checked; the site carries more than that`)
}

console.log(
  failed
    ? `\nFAIL (${failed}) - the page shows output this compiler does not produce`
    : `\nPASS ${checked} programs, breaks and quotes match ${trimEnd(spawnSync(axiom, ['version'], { encoding: 'utf8' }).stdout)}`,
)
process.exit(failed ? 1 : 0)
