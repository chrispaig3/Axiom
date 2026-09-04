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
import { Closing } from './sections/Closing.tsx'
import { Footer } from './sections/Footer.tsx'
import { useTheme } from './lib/theme.ts'

export default function App() {
  // The theme VALUE is no longer read here: the toggle still stamps
  // `data-theme`, and the glyph that used to depend on it is chosen by
  // CSS now, so the markup is identical on the server and the client.
  const [, toggle] = useTheme()

  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <Nav onToggle={toggle} />
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
        <Closing />
      </main>
      <Footer />
    </>
  )
}
