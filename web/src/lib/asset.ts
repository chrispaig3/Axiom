/**
 * Resolve a file in `public/` against the deploy base.
 *
 * The site is served from `https://chrispaig3.github.io/Axiom/`, so a
 * bare `/axiom-logo.jpg` would 404. `import.meta.env.BASE_URL` is Vite's
 * `base` at runtime (`/Axiom/` in a build, `/` under `vite dev` unless
 * base is set), which keeps one spelling correct in both.
 */
export function asset(path: string): string {
  const base = import.meta.env.BASE_URL
  return `${base.endsWith('/') ? base : `${base}/`}${path.replace(/^\//, '')}`
}
