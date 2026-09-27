/**
 * The 1-based lines of `b` that are not in a longest common subsequence
 * with `a`: what a reader should look at after an edit. The programs
 * here are tens of lines, so the quadratic table is nothing.
 */
export function changedLines(a: string, b: string): number[] {
  const x = a.split('\n')
  const y = b.split('\n')
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
