import { useCallback, useEffect, useRef, useState } from 'react'
import { Check, Copy } from './Icons.tsx'

/** A shell command with a copy button. */
export function Command({ command }: { command: string }) {
  const [copied, setCopied] = useState(false)
  const timer = useRef<number | undefined>(undefined)

  useEffect(() => () => window.clearTimeout(timer.current), [])

  const copy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(command)
      setCopied(true)
      window.clearTimeout(timer.current)
      timer.current = window.setTimeout(() => setCopied(false), 1800)
    } catch {
      // Clipboard access can be denied; the text is selectable either way.
    }
  }, [command])

  return (
    <div className="command">
      <div className="command__text">
        <span className="command__prompt" aria-hidden>
          $
        </span>
        <code>{command}</code>
      </div>
      <button
        type="button"
        className="command__copy"
        onClick={copy}
        data-copied={copied}
        aria-label={copied ? 'Command copied' : `Copy: ${command}`}
      >
        {copied ? <Check /> : <Copy />}
        <span aria-hidden>{copied ? 'Copied' : 'Copy'}</span>
      </button>
    </div>
  )
}
