/**
 * The 1-based lines of `b` that a reader would call changed after an
 * edit that turned `a` into `b`.
 *
 * Lines are compared without their indentation and without the run of
 * closing parentheses at their end, because in an S-expression those
 * move when a neighbour changes: add a constructor after the last one,
 * and the last one gives up its `)`. A plain line diff marked that line
 * as edited, and the page lit `(Delivered)` under a sentence about
 * `(Returned)`. The programs here are tens of lines, so the quadratic
 * table is nothing.
 */
const norm = (line: string) => line.trim().replace(/[)\]}]+$/, '')

export function changedLines(a: string, b: string): number[] {
  const x = a.split('\n').map(norm)
  const y = b.split('\n').map(norm)
  const n = x.length
  const m = y.length
  const t: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0))
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      t[i]![j] = x[i] === y[j] ? t[i + 1]![j + 1]! + 1 : Math.max(t[i + 1]![j]!, t[i]![j + 1]!)
    }
  }
  const out: number[] = []
  let i = 0
  let j = 0
  while (j < m) {
    if (i < n && x[i] === y[j]) {
      i++
      j++
    } else if (i < n && t[i + 1]![j]! >= t[i]![j + 1]!) {
      i++
    } else {
      out.push(j + 1)
      j++
    }
  }
  return out
}

/** The lines a human compiler report points at, from its `-->` lines. */
export function reportedLines(report: string): number[] {
  return [...new Set([...report.matchAll(/-->\s+\S+?:(\d+):\d+/g)].map((m) => Number(m[1])))]
}

/** The 1-based line of `code` that holds `text`, or 0. */
export function lineOf(code: string, text: string): number {
  return code.split('\n').findIndex((l) => l.includes(text)) + 1
}
