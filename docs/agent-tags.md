# Read symbol metadata

`Agent.Tags` reads the AXSYM stream produced by `axiom symbols`.
You can inspect names, types, locations, derived effects and author
tags without importing the compiler's implementation.

```bash
axiom --diagnostic-format=ai symbols Main.ax --calls > symbols.axsym
```

This program reads one function row from the symbol corpus:

<!-- doc-gate:run -->
```scheme
(import IO)
(import Agent.Tags)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (axsymLine "F shout specimen.ax:11:5-10 \"(Int -> Int)\" @cc70b00d8093fca4 #effect=io #agent:readonly #effects=IO")
    ((None) (die "invalid symbol row" 1))
    ((Some symbol)
      (let ((readonly (symHasAgentTag symbol "readonly")))
       {
        (println symbol.name)
        (println (symEffects symbol))
        (println (symTag symbol "effect"))
        (println "readonly: {readonly}")
        0
       }))))
```

```text
shout
IO
io
readonly: true
```

## Read a whole stream

`axsymLine` returns `Option Sym`. `axsymParse` takes a stream and
returns `Vec Sym`, skipping lines outside the symbol notation.
A `Sym` has `kind`, `name`, `loc`, `ty`, `nid` and `meta` fields.
The kind is the integer byte value of its AXSYM letter.
The reader accepts all eight kinds: `F`, `D`, `C`, `S`, `T`, `A`, `E`
and `M`. Error diagnostics also start with `E`; their location and
message fields keep them outside the symbol grammar.

Locations belong to the file that declared the symbol, including
imported modules. `"-"` marks a missing source location. The node ID
comes from the declaration's kind and name, so it survives unrelated
source edits; it can be empty when there is no declaration span.

## Separate claims from derived effects

`symTag symbol "effect"` reads the author's annotation.
`symEffects` reads the checker's `#effects` field. A tag with an empty
value and an absent tag both give `""`; `symHasTag` tells them apart.
For duplicate keys, the last value wins. The compiler writes its
derived fields after author tags.

`symDerivedPure` reports that no derived effect field is present.
Treat it as an analysis result: effects reached through values in
memory may escape the static call graph, and handled effects are
subtracted. It does not prove that running the function has no effects.

## Read agent tags

`symAgentTag symbol "rewrite"` reads `agent:rewrite`.
`symHasAgentTag` also handles a flag such as `agent:readonly`.
The compiler records this namespace without enforcing a policy.
Your tool decides what those tags permit.

Parsing helpers and delimiter constants are module-private. Use
`axsymLine`, `axsymParse` and the `sym...` accessors to read the stream.

The reader preserves spaces in metadata values and decodes structural
bytes escaped as `%XX`. Keep the stream in AXSYM format;
`symbols --diagnostic-format=json` is refused with status 2.

Tested by `tests/stdlib/380-agent-tags.ax` and
`scripts/check-tools-selfhost.sh`.

See also: [agent harness](agent-harness.md),
[diagnostics](diagnostics.md) and the
[generated API](stdlib-api.md#agenttags).
