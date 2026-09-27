import { Nav } from './components/Nav.tsx'
import { Hero } from './sections/Hero.tsx'
import { Pillars } from './sections/Pillars.tsx'
import { BreakIt } from './sections/BreakIt.tsx'
import { Tour } from './sections/Tour.tsx'
import { UseCases } from './sections/UseCases.tsx'
import { Benchmark } from './sections/Benchmark.tsx'
import { Trust } from './sections/Trust.tsx'
import { Compare } from './sections/Compare.tsx'
import { Agents } from './sections/Agents.tsx'
import { Toolchain } from './sections/Toolchain.tsx'
import { Start } from './sections/Start.tsx'
import { Status } from './sections/Status.tsx'
import { Faq } from './sections/Faq.tsx'
import { Docs } from './sections/Docs.tsx'
import { Closing } from './sections/Closing.tsx'
import { Footer } from './sections/Footer.tsx'
import { useTheme } from './lib/theme.ts'

/**
 * The page, in the order a newcomer's questions arrive: what is it, why
 * would I want it, show me, teach me, what is it for, is it fast, can I trust it, how
 * does it compare, what about my tools, how do I start, what is
 * missing, and the questions left over.
 */
export default function App() {
  // The theme VALUE is not read here: the toggle stamps `data-theme`,
  // and the glyph that depends on it is chosen by CSS, so the markup is
  // identical on the server and the client.
  const [, toggle] = useTheme()

  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <Nav onToggle={toggle} />
      <main id="main">
        <Hero />
        <Pillars />
        <BreakIt />
        <Tour />
        <UseCases />
        <Benchmark />
        <Trust />
        <Compare />
        <Agents />
        <Toolchain />
        <Start />
        <Status />
        <Faq />
        <Docs />
        <Closing />
      </main>
      <Footer />
    </>
  )
}
