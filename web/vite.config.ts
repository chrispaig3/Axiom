import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// The custom domain serves the site at its root. Keep the client and
// server renders on the same base so every asset resolves there.
export default defineConfig({
  base: '/',
  plugins: [react()],
  build: {
    target: 'es2022',
    // The site is one page of static content plus a hand-written
    // highlighter; a manual chunk split would produce more requests
    // without shrinking anything worth splitting.
    chunkSizeWarningLimit: 400,
  },
})
