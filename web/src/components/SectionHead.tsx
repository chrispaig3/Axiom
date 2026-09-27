import type { ReactNode } from 'react'

/**
 * Every section opens the same way: an eyebrow naming the topic, one
 * claim as the heading, and a sentence or two under it. One device,
 * repeated, is what makes a long page read as a single document.
 */
export function SectionHead({
  id,
  eyebrow,
  title,
  children,
  center = false,
}: {
  id: string
  eyebrow: string
  title: ReactNode
  children?: ReactNode
  center?: boolean
}) {
  return (
    <header className={center ? 'shead shead--center' : 'shead'}>
      <p className="eyebrow">{eyebrow}</p>
      <h2 id={id}>{title}</h2>
      {children && <div className="shead__lede">{children}</div>}
    </header>
  )
}
