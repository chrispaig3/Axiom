import { useCallback, useEffect, useState } from 'react'

export type Theme = 'light' | 'dark'

const KEY = 'axiom-theme'

function stored(): Theme | null {
  try {
    const v = localStorage.getItem(KEY)
    return v === 'dark' || v === 'light' ? v : null
  } catch {
    // Private windows and blocked site data throw on access, not on read.
    return null
  }
}

/**
 * The terminal theme is the default; the paper one is a choice, stamped
 * on the root element and persisted. The same stamp is applied by an
 * inline script in index.html so the first paint is already correct.
 */
export function useTheme(): [Theme, () => void] {
  const [theme, setTheme] = useState<Theme>(() => stored() ?? 'dark')

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme)
  }, [theme])

  const toggle = useCallback(() => {
    setTheme((prev) => {
      const next: Theme = prev === 'dark' ? 'light' : 'dark'
      try {
        localStorage.setItem(KEY, next)
      } catch {
        // The toggle still works for this page view; it just won't persist.
      }
      return next
    })
  }, [])

  return [theme, toggle]
}
