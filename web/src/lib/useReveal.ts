import { useEffect, useRef } from 'react'

/**
 * A one-shot entrance transition: an element fades and lifts into place
 * the first time it crosses into view, then is left alone.
 *
 * `prefers-reduced-motion` is handled in CSS (`.reveal` is already in its
 * final state under the media query), and the observer is skipped
 * entirely where `IntersectionObserver` is unavailable — in both cases
 * the attribute is set immediately so nothing can be left invisible.
 */
export function useReveal<T extends HTMLElement>() {
  const ref = useRef<T>(null)

  useEffect(() => {
    const el = ref.current
    if (!el) return

    const reduced =
      typeof matchMedia === 'function' &&
      matchMedia('(prefers-reduced-motion: reduce)').matches

    if (reduced || typeof IntersectionObserver !== 'function') {
      el.dataset.shown = 'true'
      return
    }

    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            el.dataset.shown = 'true'
            io.disconnect()
          }
        }
      },
      { rootMargin: '0px 0px -8% 0px', threshold: 0.05 },
    )

    io.observe(el)
    return () => io.disconnect()
  }, [])

  return ref
}
