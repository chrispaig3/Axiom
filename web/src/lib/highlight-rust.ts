import type { Token } from './highlight.ts'

/**
 * Just enough Rust to colour the crate side of an FFI sample: the
 * excerpts on this page are a few `#[axiom_export]` functions and one
 * struct, quoted verbatim from `rust/examples/demo/src/lib.rs`. It
 * emits the same capture names as the Axiom highlighter, so one set of
 * token colours serves both languages.
 *
 * It is a lexer, not a parser: keywords by spelling, types by an
 * initial capital or a primitive name, a function name by the `fn`
 * before it, a call or macro by the `(` or `!` after it.
 */
const KEYWORDS = new Set([
  'pub', 'fn', 'let', 'mut', 'struct', 'enum', 'impl', 'use', 'mod', 'return',
  'if', 'else', 'match', 'for', 'while', 'loop', 'in', 'as', 'const', 'static',
  'unsafe', 'extern', 'crate', 'self', 'Self', 'super', 'where', 'trait', 'type',
])
const PRIMITIVES = new Set([
  'i8', 'i16', 'i32', 'i64', 'i128', 'isize', 'u8', 'u16', 'u32', 'u64', 'u128',
  'usize', 'f32', 'f64', 'bool', 'char', 'str',
])

const LEX =
  /(\/\/[^\n]*)|(#!?\[[^\]]*\])|("(?:[^"\\]|\\.)*")|('(?:[^'\\]|\\.)')|(\b\d[\d_]*(?:\.\d+)?\b)|([A-Za-z_][A-Za-z0-9_]*)|(\s+)|(.)/g

export function highlightRust(src: string): Token[] {
  const out: Token[] = []
  let prevWord = ''
  let m: RegExpExecArray | null
  LEX.lastIndex = 0
  while ((m = LEX.exec(src)) !== null) {
    const [text] = m
    if (m[1]) out.push({ text, capture: 'comment' })
    else if (m[2]) out.push({ text, capture: 'attribute' })
    else if (m[3]) out.push({ text, capture: 'string' })
    else if (m[4]) out.push({ text, capture: 'character' })
    else if (m[5]) out.push({ text, capture: 'number' })
    else if (m[6]) {
      const next = src.slice(LEX.lastIndex).match(/^\s*(\S)/)?.[1]
      let capture: Token['capture']
      if (KEYWORDS.has(text)) capture = text === 'fn' ? 'keyword.function' : 'keyword'
      else if (PRIMITIVES.has(text)) capture = 'type.builtin'
      else if (prevWord === 'fn') capture = 'function'
      else if (/^[A-Z]/.test(text)) capture = prevWord === 'struct' ? 'type.definition' : 'type'
      else if (next === '(' || next === '!') capture = 'function.call'
      else capture = 'variable'
      out.push({ text, capture })
      prevWord = text
      continue
    } else if (m[7]) out.push({ text, capture: 'text' })
    else out.push({ text, capture: /[(){}[\]]/.test(text) ? 'punctuation.bracket' : 'punctuation.delimiter' })
    if (!m[7]) prevWord = ''
  }
  return out
}
