# Give strings stable IDs

`Intern` maps equal string contents to one dense integer ID.
Use IDs for repeated comparisons and as keys in an integer `Map`.

Save this as `Main.ax` and run `axiom run Main.ax`:

<!-- doc-gate:run -->
```scheme
(import IO)
(import Intern)
(import Str)

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main)
  (let (
    (names (internNew))
    (first (internIntern names "alpha"))
    (second (internIntern names "beta"))
    (again (internIntern names (strDup "alpha")))
    (count (internCount names))
  )
    {
      (println "first: {first}")
      (println "second: {second}")
      (println "again: {again}")
      (println "count: {count}")
      (println (internLookup names 1))
      (internFree names)
      0
    }))
```

```text
first: 0
second: 1
again: 0
count: 2
beta
```

## Find without adding

`internFind` returns `Some id` when the string is already present and
`None` otherwise. `internIntern` adds a missing string and returns its
ID. IDs start at zero, stay unchanged during growth, and belong to that
interner. Two independent interners can assign different IDs to the
same contents.

`internLookup` returns the string for an ID. A negative or out-of-range
ID returns `""`, which is also a valid interned string. Check that the
ID is below `internCount` when you need to distinguish these cases.

## Keep the bytes unchanged

The interner retains the string storage without copying its bytes.
Keep those bytes unchanged for the interner's lifetime. If another
part of your program may mutate a string or its backing buffer,
intern `(strDup text)`.

`internFree` releases your owning share, the table and its retained
strings, and returns zero. The raw `Int` handle and any unretained
views must be unused after the last release. That caller obligation
accounts for the example's `effect(unsafe)` annotation.

## Reserve space

`internWithCapacity` takes the expected number of distinct strings.
It reserves a table at a load factor of one half. The header and IDs
remain stable when the table grows. Entries cannot be removed.

Tested by `tests/stdlib/090-intern.ax` and
`tests/stdlib/488-intern-free.ax`.

See also: [memory ownership](memory-model.md) and the
[generated API](stdlib-api.md#intern).
