import { StrictMode } from 'react'
import { createRoot, hydrateRoot } from 'react-dom/client'
import App from './App.tsx'
import './styles/index.css'
import { installOverflowProbe } from './lib/overflow.ts'

// No-op unless the URL carries `?debug=overflow`.
installOverflowProbe()

const root = document.getElementById('root')
if (!root) throw new Error('#root is missing from index.html')

const tree = (
  <StrictMode>
    <App />
  </StrictMode>
)

// `scripts/prerender.mjs` fills the mount at build time so that a crawler
// which executes no JavaScript still gets the whole page. Under `vite
// dev` the mount is empty, so both paths have to exist: hydrate what is
// there, or render from nothing.
if (root.firstChild) hydrateRoot(root, tree)
else createRoot(root).render(tree)
