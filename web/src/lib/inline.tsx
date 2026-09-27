import { Fragment, type ReactNode } from 'react'

/**
 * Render the backtick spans in a sentence as <code>, without pulling in
 * a markdown parser. Content strings on this site use exactly one piece
 * of markup, and this is it.
 */
export function inline(text: string): ReactNode {
  return text
    .split(/`([^`]+)`/g)
    .map((part, i) =>
      i % 2 === 1 ? <code key={i}>{part}</code> : <Fragment key={i}>{part}</Fragment>,
    )
}
