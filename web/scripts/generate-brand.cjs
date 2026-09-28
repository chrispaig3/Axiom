#!/usr/bin/env node
/**
 * Regenerate the brand kit in assets/logo and the site's copies in web/public.
 *
 * Every letter is outlined from the two families the site loads - Inter and
 * JetBrains Mono, from @fontsource - so the SVGs render the same in every
 * viewer and the kit cannot drift from the page's type. assets/logo/geometry.json
 * is the source the site draws its logo from (BrandLogo.tsx, Icons.tsx,
 * NativeVisual.tsx); this script writes it, so edit the constants here.
 *
 * The tools are not site dependencies (Pages would install sharp on every
 * deploy), so run it against a throwaway install:
 *
 *   npm i --no-save --prefix "$TMPDIR/axiom-brand" \
 *     sharp@0.35.5 fontkit@2.0.4 @fontsource/inter@5.3.0 @fontsource/jetbrains-mono@5.3.0
 *   NODE_PATH="$TMPDIR/axiom-brand/node_modules" node web/scripts/generate-brand.cjs
 */
const { writeFileSync, copyFileSync } = require('node:fs')
const { join, resolve } = require('node:path')
const sharp = require('sharp')
const fontkit = require('fontkit')

const root = resolve(__dirname, '../..')
const dir = join(root, 'assets/logo')
const publicDir = join(root, 'web/public')

const c = {
  graphite: '#0b0d0c',
  surface: '#131714',
  paper: '#f1f3ea',
  lime: '#c3f36b',
  forest: '#3c6514',
  light: '#f6f5ef',
  muted: '#8b9788',
  body: '#b3bbae',
  line: '#29312a',
}

// The split A, in a 64-unit box: ink spans x 2..62, y 4..60.
const markPath = 'M32 4 62 60H48L32 28 25.5 41H33L38.5 52H20L16 60H2Z'

const font = (pkg, file) => fontkit.openSync(require.resolve(`@fontsource/${pkg}/files/${file}`))
const inter = w => font('inter', `inter-latin-${w}-normal.woff`)
const sans = { 400: inter(400), 500: inter(500), 600: inter(600) }
const mono = font('jetbrains-mono', 'jetbrains-mono-latin-400-normal.woff')

/** Outline `str` with its baseline at (x, y); returns the path and the advance it used. */
function outline(f, str, size, x, y, tracking = 0) {
  const run = f.layout(str)
  const k = size / f.unitsPerEm
  const glyphs = []
  let pen = x
  run.glyphs.forEach((g, i) => {
    const p = run.positions[i]
    const gx = pen + p.xOffset * k
    const gy = y - p.yOffset * k
    glyphs.push(g.path.mapPoints((px, py) => [gx + px * k, gy - py * k]).toSVG())
    pen += p.xAdvance * k + tracking * size
  })
  return { glyphs, width: pen - x - tracking * size }
}

// ---- the wordmark: Inter SemiBold, cap height 72, as the hero headline is set
const CAP = 72
const TRACK = -0.03
const wordSize = CAP * sans[600].unitsPerEm / sans[600].capHeight
const wk = wordSize / sans[600].unitsPerEm
const [dotTop, inkLeft, inkRight, overshoot] = (() => {
  const run = sans[600].layout('Axiom')
  const b = run.glyphs.map(g => g.bbox)
  const last = run.glyphs.length - 1
  const advance = run.positions.slice(0, last).reduce((s, p) => s + p.xAdvance * wk + TRACK * wordSize, 0)
  return [Math.max(...b.map(g => g.maxY)) * wk, b[0].minX * wk, advance + b[last].maxX * wk, -Math.min(...b.map(g => g.minY)) * wk]
})()
// Wordmark coordinates: ink starts at x 0, the i's dot touches y 0.
const baseline = +dotTop.toFixed(2)
const capTop = +(baseline - CAP).toFixed(2)
const wordmark = outline(sans[600], 'Axiom', wordSize, -inkLeft, baseline, TRACK)
const wordWidth = +(inkRight - inkLeft).toFixed(2)

// ---- the lockup: the mark as tall as a capital, sitting on the baseline
const markScale = CAP / 56
const gap = +(0.4 * CAP).toFixed(2)
const lockup = {
  width: Math.ceil(60 * markScale + gap + wordWidth),
  height: Math.ceil(baseline + overshoot),
  mark: `translate(${+(-2 * markScale).toFixed(2)} ${+(capTop - 4 * markScale).toFixed(2)}) scale(${+markScale.toFixed(4)})`,
  word: `translate(${+(60 * markScale + gap).toFixed(2)} 0)`,
  capTop,
  baseline,
}

writeFileSync(join(dir, 'geometry.json'), JSON.stringify({
  name: 'Axiom',
  generatedBy: 'web/scripts/generate-brand.cjs',
  markPath,
  wordmark: { font: 'Inter SemiBold', capHeight: CAP, tracking: TRACK, width: wordWidth, baseline },
  wordmarkPaths: wordmark.glyphs,
  lockup,
  colors: c,
}, null, 2) + '\n')

// ---- drawing helpers, all in the page's own units
const mark = (x, y, scale, color) => `<path d="${markPath}" fill="${color}" transform="translate(${x} ${y}) scale(${scale})"/>`
const logo = (x, y, scale, ink = c.paper, accent = c.lime) =>
  `<g transform="translate(${x} ${y}) scale(${scale})"><path d="${markPath}" fill="${accent}" transform="${lockup.mark}"/>` +
  `<g fill="${ink}" transform="${lockup.word}">${wordmark.glyphs.map(d => `<path d="${d}"/>`).join('')}</g></g>`
/** The lockup at `scale`, centred on x = cx, with its capitals centred on y = cy. */
const logoAt = (cx, cy, scale, ink, accent) =>
  logo(+(cx - lockup.width * scale / 2).toFixed(2), +(cy - (capTop + baseline) / 2 * scale).toFixed(2), scale, ink, accent)
const rect = (x, y, w, h, fill, rx = 0) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}" fill="${fill}"/>`
const rule = (x1, y, x2, color = c.line) => `<path d="M${x1} ${y}H${x2}" stroke="${color}"/>`

/** Set text: anchor is 'start', 'middle' or 'end' at x. */
function text(x, y, str, { size = 14, weight = 400, color = c.muted, tracking = 0, anchor = 'start' } = {}) {
  const w = outline(sans[weight], str, size, 0, 0, tracking).width
  const x0 = anchor === 'end' ? x - w : anchor === 'middle' ? x - w / 2 : x
  return `<path fill="${color}" d="${outline(sans[weight], str, size, x0, y, tracking).glyphs.join('')}"/>`
}

/**
 * A mono caption, 12px and widely tracked, as the site's eyebrows are.
 * @fontsource ships no arrow in these subsets, so each `→` is drawn into
 * its own monospace cell, on the hyphen's axis.
 */
function label(x, y, str, color = c.muted, anchor = 'start') {
  const size = 12, tracking = 0.18, k = size / mono.unitsPerEm
  const cell = mono.layout('M').positions[0].xAdvance * k + tracking * size
  const hy = mono.layout('-').glyphs[0].bbox
  const axis = (hy.minY + hy.maxY) / 2 * k, stem = (hy.maxY - hy.minY) * k
  const cells = [...str].length
  const x0 = anchor === 'end' ? x - (cells * cell - tracking * size) : x
  let d = ''
  ;[...str].forEach((ch, i) => {
    const cx = x0 + i * cell
    if (ch === '→') {
      const l = cx - 0.2, r = cx + cell - tracking * size + 0.4, len = 2.9, half = 2.6, ay = y - axis
      d += `M${l} ${ay - stem / 2}H${r - len}V${ay - half}L${r} ${ay}L${r - len} ${ay + half}V${ay + stem / 2}H${l}Z`
    } else if (ch !== ' ') {
      d += outline(mono, ch, size, cx, y).glyphs.join('')
    }
  })
  return `<path fill="${color}" d="${d}"/>`
}

const svg = (w, h, content, title) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-label="${title}"><title>${title}</title>${content}</svg>\n`
const sources = {}
const save = (name, w, h, content, title) => {
  sources[name] = { source: svg(w, h, content, title), w }
  writeFileSync(join(dir, `${name}.svg`), sources[name].source)
}
/** Rasterise at twice the output width, so a 64-unit mark is not upscaled into a 1024px blur. */
function png(name, width, out = name) {
  const { source, w } = sources[name]
  return sharp(Buffer.from(source), { density: Math.min(2400, 72 * 2 * width / w) })
    .resize({ width }).png({ compressionLevel: 9 }).toFile(join(dir, `${out}.png`))
}

async function main() {
  const L = lockup
  save('Axiom_Mark', 64, 64, mark(0, 0, 1, c.lime), 'Axiom split-A symbol')
  save('Axiom_Mark_Light', 64, 64, mark(0, 0, 1, c.forest), 'Axiom symbol for light backgrounds')
  save('Axiom_Mark_Mono', 64, 64, mark(0, 0, 1, c.graphite), 'Axiom monochrome symbol')
  save('Axiom_Lockup_Dark', L.width, L.height, logo(0, 0, 1), 'Axiom logo for dark backgrounds')
  save('Axiom_Lockup_Light', L.width, L.height, logo(0, 0, 1, c.graphite, c.forest), 'Axiom logo for light backgrounds')
  save('Axiom_Lockup_Mono', L.width, L.height, logo(0, 0, 1, c.graphite, c.graphite), 'Axiom monochrome logo')
  save('Axiom_Avatar', 512, 512, rect(0, 0, 512, 512, c.graphite) + mark(96, 96, 5, c.lime), 'Axiom avatar')
  save('Axiom_Icon', 64, 64, rect(0, 0, 64, 64, c.graphite, 14) + mark(9, 9, 0.72, c.lime), 'Axiom app icon')

  const tagline = 'High-level thinking. Native-level control.'
  save('Axiom_Logo', 1600, 900,
    rect(0, 0, 1600, 900, c.graphite) +
    label(72, 72, 'AX / THE FUNCTIONAL SYSTEMS LANGUAGE') + label(1528, 72, 'SOURCE → NATIVE', c.muted, 'end') +
    rule(72, 109.5, 1528) + logoAt(800, 408, 2.9) +
    text(800, 620, tagline, { size: 30, weight: 500, color: c.paper, tracking: -0.02, anchor: 'middle' }) +
    rule(72, 795.5, 1528) + label(72, 840, 'POWERFUL TYPES. EXPLICIT EFFECTS. NATIVE BINARIES.') +
    label(1528, 840, 'BUILT IN AXIOM.', c.lime, 'end'),
    `Axiom — ${tagline}`)

  save('Axiom_Social', 1200, 630,
    rect(0, 0, 1200, 630, c.graphite) + logo(64, 56, 0.66) +
    label(64, 210, 'THE FUNCTIONAL SYSTEMS LANGUAGE') +
    text(60, 301, 'High-level thinking.', { size: 62, weight: 600, color: c.paper, tracking: -0.055 }) +
    text(60, 374, 'Native-level control.', { size: 62, weight: 600, color: c.lime, tracking: -0.055 }) +
    text(64, 431, 'Powerful types. Explicit effects. Native binaries.', { size: 21, color: c.body }) +
    `<g fill="none" stroke="${c.lime}" stroke-opacity=".17"><path d="M945 105 1144 457 945 519 746 457Z"/><path d="M945 105V519M746 457 945 355 1144 457"/><circle cx="945" cy="326" r="187" stroke-dasharray="2 9"/></g>` +
    mark(801, 174, 4.5, c.lime) + rule(64, 526.5, 1136) +
    label(64, 571, 'OPEN SOURCE. BUILT IN AXIOM.') + label(1136, 571, 'AXIOM → LLVM → NATIVE', c.lime, 'end'),
    `Axiom — ${tagline}`)

  // The three panels share one optical centre line, y = 740.
  save('Axiom_Brand_Preview', 1600, 1120,
    rect(0, 0, 1600, 1120, c.graphite) +
    label(64, 63, 'AXIOM / VISUAL IDENTITY', c.lime) + label(1536, 63, '01 — NATIVE A', c.muted, 'end') +
    rule(64, 96.5, 1536) + logoAt(800, 302, 2.9) +
    text(800, 490, tagline, { size: 28, weight: 500, color: c.paper, tracking: -0.02, anchor: 'middle' }) +
    rect(64, 590, 470, 352, c.surface, 12) + mark(203, 644, 3, c.lime) + label(92, 913, '01 / THE MARK') +
    rect(554, 590, 492, 352, c.light, 12) + logoAt(800, 740, 1.05, c.graphite, c.forest) + label(582, 913, '02 / ON WARM PAPER', c.forest) +
    rect(1066, 590, 470, 352, c.lime, 12) + rect(1213, 652, 176, 176, c.graphite, 38) + mark(1238, 677, 1.98, c.lime) +
    label(1094, 913, '03 / APP & AVATAR', c.graphite) +
    rect(64, 990, 18, 18, c.lime) + label(96, 1004, 'ELECTRIC LIME / #C3F36B') +
    rect(530, 990, 18, 18, c.paper) + label(562, 1004, 'WARM WHITE / #F1F3EA') +
    rect(1084, 990, 18, 18, c.forest, 0) + label(1116, 1004, 'FOREST / #3C6514') +
    text(64, 1066, 'One precise silhouette. From source to native.', { size: 18, color: c.muted }),
    'Axiom brand identity: logo, mark, light variant and app icon')

  await Promise.all([
    png('Axiom_Logo', 1600), png('Axiom_Mark', 1024), png('Axiom_Mark_Light', 1024),
    png('Axiom_Lockup_Dark', 1600), png('Axiom_Lockup_Light', 1600),
    png('Axiom_Avatar', 1024), png('Axiom_Social', 1200), png('Axiom_Brand_Preview', 1600),
    png('Axiom_Avatar', 180, 'apple-touch-icon'), png('Axiom_Icon', 32, 'favicon-32'), png('Axiom_Icon', 16, 'favicon-16'),
  ])

  // The site's copies. axiom-mark.png and axiom-logo.jpg keep their old
  // URLs alive for anything that linked them before the redesign.
  copyFileSync(join(dir, 'Axiom_Mark.png'), join(publicDir, 'axiom-mark.png'))
  copyFileSync(join(dir, 'Axiom_Mark.svg'), join(publicDir, 'axiom-mark.svg'))
  copyFileSync(join(dir, 'Axiom_Icon.svg'), join(publicDir, 'favicon.svg'))
  copyFileSync(join(dir, 'favicon-32.png'), join(publicDir, 'favicon-32.png'))
  copyFileSync(join(dir, 'apple-touch-icon.png'), join(publicDir, 'apple-touch-icon.png'))
  copyFileSync(join(dir, 'Axiom_Social.png'), join(publicDir, 'og.png'))
  await sharp(join(dir, 'Axiom_Logo.png')).flatten({ background: c.graphite }).jpeg({ quality: 90 }).toFile(join(publicDir, 'axiom-logo.jpg'))
  console.log(`ok   brand kit in assets/logo (lockup ${L.width}x${L.height}), site copies in web/public`)
}

main().catch(error => { console.error(error); process.exitCode = 1 })
