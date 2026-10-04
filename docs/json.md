# Read and write JSON

`Json` parses a document, lets you inspect or build its values, and
writes them back as JSON text. Check the parse result before reading
fields.

Save this as `Main.ax` and run `axiom run Main.ax`:

<!-- doc-gate:run -->
```scheme
(import IO)
(import Json)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((doc (jsonParse "{\"name\":\"Axiom\",\"count\":3}")))
    (if (== doc 0)
      (die "invalid JSON" 1)
      {
        (println (jsonGetStr doc "name"))
        (println (jsonWrite (jsonGet doc "count")))
        (println (jsonWrite (jsonObjPut doc "ready" (jsonBool 1))))
        0
      })))
```

```text
Axiom
3
{"name":"Axiom","count":3,"ready":true}
```

## Handle a missing field

`jsonParse` returns an `Int` handle, with `0` for invalid input.
`jsonGet` also returns `0` when an object has no matching key. A parsed
JSON `null` has a nonzero handle, so compare with `0` before using
`jsonIsNull` when that distinction matters.

`jsonGetInt` returns `0` for missing or nonnumeric values.
`jsonGetStr` returns `""` for missing or nonstring values. These defaults
also represent valid JSON values. Use `jsonGet` when you need to detect
absence separately.

## Keep number text

`jsonInt` reads a number's integer part. `jsonNumText` preserves its
original spelling, including a fraction or exponent, and `jsonWrite`
uses that spelling. There is no floating-point accessor.

```scheme fragment
(jsonInt (jsonParse "12.5"))       ; 12
(jsonNumText (jsonParse "12.5"))   ; "12.5"
(jsonWrite (jsonParse "1e3"))      ; "1e3"
```

## Build objects and arrays

Use `jsonNull`, `jsonBool`, `jsonNum`, `jsonStr`, `jsonArr` and
`jsonObj` to make values. `jsonBool` takes an integer: zero means false,
and any other value means true.

`jsonObjPut` mutates the object and returns its handle. Replacing a key
keeps its position. `jsonArrPush` similarly appends in place.
`jsonArrLen` and `jsonArrGet` let you walk an array; an invalid index
returns `0`.

```scheme fragment
(let ((items (jsonArr)))
  {
    (jsonArrPush items (jsonStr "first"))
    (jsonArrPush items (jsonNum 2))
    (jsonWrite items)                 ; "[\"first\",2]"
  })
```

## Input limits

The parser rejects trailing input and nesting beyond its depth budget
of 64. Parsing failures carry no error location. Values are allocated
in the arena; this module has no individual-value release operation.
The writer replaces malformed UTF-8 bytes with `U+FFFD`.

Tested by `tests/stdlib/340-json.ax` and
`tests/stdlib/485-json-mutation.ax`.

See also: [RPC framing](rpc.md) and the
[generated API](stdlib-api.md#json).
