/**
 * A layout probe, for the viewport nobody here can render.
 *
 * Both headless Chromium modes clamp their window: `--headless=new`
 * near 500px, `--headless=old` at 492px measured. A `--window-size=390`
 * capture therefore lays the page out at 492 and CROPS to 390, which
 * looks exactly like a horizontal overflow and is not one. Two rounds of
 * "fixes" were aimed at that phantom before the clamp was measured
 * rather than assumed.
 *
 * So the measurement moves to the device that has the real viewport.
 * Load the site with `?debug=overflow` on a phone and this prints, in a
 * bar at the bottom of the screen: the viewport width, the document's
 * scroll width, and every element whose right edge is past the viewport
 * — worst first, with its tag and first class.
 *
 * If `scrollWidth` equals the viewport width, the page does not overflow
 * and anything that looks cropped is the screenshot, not the layout.
 * Elements listed *inside* a code frame are expected: a `<pre>` that
 * scrolls horizontally is a `<pre>` doing its job.
 *
 * Costs nothing when the parameter is absent — the module is only
 * imported for its side effect, and returns immediately.
 */
export function installOverflowProbe(): void {
  if (typeof window === 'undefined') return
  if (new URLSearchParams(window.location.search).get('debug') !== 'overflow') {
    return
  }

  const render = () => {
    const vw = document.documentElement.clientWidth
    const offenders: string[] = []

    for (const el of Array.from(document.querySelectorAll('*'))) {
      const r = el.getBoundingClientRect()
      if (r.right > vw + 1) {
        const cls =
          typeof el.className === 'string' && el.className
            ? `.${el.className.split(' ')[0]}`
            : ''
        offenders.push(`${Math.round(r.right)} ${el.tagName.toLowerCase()}${cls}`)
      }
    }

    offenders.sort((a, b) => parseInt(b, 10) - parseInt(a, 10))

    const bar = document.createElement('pre')
    bar.setAttribute('data-overflow-probe', '')
    bar.style.cssText = [
      'position:fixed',
      'left:0',
      'right:0',
      'bottom:0',
      'z-index:9999',
      'margin:0',
      'max-height:45vh',
      'overflow:auto',
      'padding:10px 12px',
      'background:#0b0d10',
      'color:#7fd6a8',
      'font:11px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace',
      'border-top:2px solid #4cc2f1',
      'white-space:pre-wrap',
    ].join(';')

    const clean = document.documentElement.scrollWidth <= vw + 1
    bar.textContent =
      `viewport ${vw}  ·  document ${document.documentElement.scrollWidth}  ·  ` +
      `${clean ? 'NO PAGE OVERFLOW' : 'PAGE OVERFLOWS'}\n` +
      (offenders.length
        ? `past the right edge (worst first):\n  ${offenders.slice(0, 20).join('\n  ')}`
        : 'nothing extends past the right edge')

    document.querySelector('[data-overflow-probe]')?.remove()
    document.body.appendChild(bar)
  }

  window.setTimeout(render, 500)
  window.addEventListener('resize', () => window.setTimeout(render, 200))
}
