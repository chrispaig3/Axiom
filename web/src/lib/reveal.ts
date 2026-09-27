/**
 * A quiet fade-up as blocks scroll into view.
 *
 * AN ENHANCEMENT THAT CANNOT HIDE ANYTHING. The prerendered page has no
 * hidden state: every block is visible in the HTML a crawler reads and
 * a reader without JavaScript sees. After hydration this marks only
 * the blocks that are still BELOW the fold as pending, and reveals each
 * as it arrives. A block already on screen is never touched, so nothing
 * blinks out and back; under `prefers-reduced-motion` nothing is
 * touched at all.
 */
const SELECTOR = [
  '.shead',
  '.pillar',
  '.usecase',
  '.bar-card',
  '.built__grid > li',
  '.docs__group',
  '.status__col',
  '.tool',
  '.involved > li',
].join(',')

export function installReveal(): void {
  if (typeof window === 'undefined' || typeof IntersectionObserver !== 'function') return
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return

  const fold = window.innerHeight
  const pending = Array.from(document.querySelectorAll<HTMLElement>(SELECTOR)).filter(
    (el) => el.getBoundingClientRect().top > fold,
  )
  if (!pending.length) return

  const io = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue
        const el = e.target as HTMLElement
        // Siblings arriving together stagger slightly, left to right.
        const i = Array.prototype.indexOf.call(el.parentElement?.children ?? [], el)
        el.style.transitionDelay = `${Math.min(i, 5) * 60}ms`
        el.dataset.reveal = 'in'
        io.unobserve(el)
        // Once it has arrived, hand the element back to its own styles:
        // the reveal's slow transition and stagger must not linger on
        // a card's hover effect.
        const done = () => {
          delete el.dataset.reveal
          el.style.transitionDelay = ''
        }
        el.addEventListener('transitionend', done, { once: true })
        window.setTimeout(done, 1400)
      }
    },
    { rootMargin: '0px 0px -8% 0px' },
  )
  for (const el of pending) {
    el.dataset.reveal = 'pending'
    io.observe(el)
  }
}
