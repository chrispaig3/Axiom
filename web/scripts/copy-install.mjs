/**
 * Serve the installer from the site's own domain.
 *
 * `curl -fsSL https://axiomlang.software/install.sh | bash` only works
 * if that address answers with the script itself, not a page about it.
 * GitHub Pages serves `dist/` as it finds it, so this copies the one
 * canonical installer, `scripts/install.sh`, to `dist/install.sh` after
 * the Vite build. There is no second copy to keep in step: edit
 * `scripts/install.sh` and the next deploy serves the edit.
 *
 * It runs as part of `npm run build`, which is what the Pages workflow
 * runs, so a missing or malformed installer fails the deploy rather
 * than publishing a homepage whose install command 404s. The Pages
 * workflow then compares the result byte for byte, so this log line
 * is not the only evidence.
 *
 *   node scripts/copy-install.mjs
 */
import { copyFileSync, readFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { fileURLToPath } from 'node:url'

const src = fileURLToPath(new URL('../../scripts/install.sh', import.meta.url))
const dest = fileURLToPath(new URL('../dist/install.sh', import.meta.url))

let failed = 0
const fail = (m) => {
  console.log('FAIL ' + m)
  failed++
}

let script
try {
  script = readFileSync(src)
} catch {
  fail(`no installer at ${src}; axiomlang.software/install.sh would 404`)
}

if (script) {
  if (!script.length) fail('scripts/install.sh is empty')
  const firstLine = script.toString('utf8').split('\n', 1)[0]
  if (firstLine !== '#!/usr/bin/env bash') {
    fail(`scripts/install.sh opens with '${firstLine}', not '#!/usr/bin/env bash'`)
  }
}

if (failed) {
  console.log(`\n${failed} check(s) failed; dist/install.sh was not written`)
  process.exit(1)
}

copyFileSync(src, dest)
const key = createHash('sha256').update(script).digest('hex').slice(0, 12)
console.log(
  `ok   axiomlang.software/install.sh is scripts/install.sh ` +
    `(${script.length.toLocaleString('en-US')} bytes, sha256 ${key})`,
)
