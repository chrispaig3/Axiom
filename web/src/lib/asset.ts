/**
 * Resolve a file in `public/` against the deploy base.
 *
 * Vite's base is `/` for `https://axiomlang.software/` and local
 * development. Use its runtime value so every image follows that base.
 */
export function asset(path: string): string {
  const base = import.meta.env.BASE_URL
  return `${base.endsWith('/') ? base : `${base}/`}${path.replace(/^\//, '')}`
}
