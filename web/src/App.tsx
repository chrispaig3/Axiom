import { Nav } from './components/Nav.tsx'
import { Hero } from './sections/Hero.tsx'
import { Bootstrap } from './sections/Bootstrap.tsx'
import { Showcase } from './sections/Showcase.tsx'
import { Benchmark } from './sections/Benchmark.tsx'
import { Compare } from './sections/Compare.tsx'
import { Audience } from './sections/Audience.tsx'
import { Agents } from './sections/Agents.tsx'
import { Editors } from './sections/Editors.tsx'
import { Start } from './sections/Start.tsx'
import { Footer } from './sections/Footer.tsx'
import { useTheme } from './lib/theme.ts'

export default function App() {
  const [theme, toggle] = useTheme()

  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <Nav theme={theme} onToggle={toggle} />
      <main id="main">
        <Hero />
        <Bootstrap />
        <Showcase />
        <Benchmark />
        <Compare />
        <Audience />
        <Agents />
        <Editors />
        <Start />
      </main>
      <Footer />
    </>
  )
}
