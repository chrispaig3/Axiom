import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// The site is served from a GitHub *project* page, so every asset URL is
// rooted at `/Axiom/` rather than `/`. Getting this wrong is the classic
// way a Pages deploy renders a blank page: index.html asks for
// `/assets/index-*.js`, Pages answers 404, and React never boots.
//
// `base` is also read at runtime as `import.meta.env.BASE_URL`, which is
// what `src/lib/asset.ts` uses so that in-page links stay correct under
// both `npm run dev` (base applied by the dev server) and the deployed
// path.
export default defineConfig({
  base: '/Axiom/',
  plugins: [react()],
  build: {
    target: 'es2022',
    // The site is one page of static content plus a hand-written
    // highlighter; a manual chunk split would produce more requests
    // without shrinking anything worth splitting.
    chunkSizeWarningLimit: 400,
  },
})
