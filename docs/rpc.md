# Read framed messages

`Rpc` reads and writes the byte framing used by the language server.
A frame contains a `Content-Length` header, a blank line and exactly
that many body bytes. The body can hold JSON or any other text.

Save this as `Main.ax`:

<!-- doc-gate:run {"stdin":"Content-Length: 2\r\n\r\n{}"} -->
```scheme
(import IO)
(import Rpc)
(import Str)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((reader (rdNew 0)))
    {
      (match (rpcReadMsg reader)
        ((None) (println "no complete frame"))
        ((Some body)
          (let ((bytes (strLen body)))
            {
              (println "body: {body}")
              (println "bytes: {bytes}")
            })))
      0
    }))
```

```bash
printf 'Content-Length: 2\r\n\r\n{}' | axiom run Main.ax
```

```text
body: {}
bytes: 2
```

## Keep one reader per stream

`rdNew` takes a file descriptor: `0` is standard input. Keep that
reader for successive calls to `rpcReadMsg`. It retains unread bytes
when one system read brings in several frames, and joins a frame that
arrives across several reads.

`Some ""` is a complete frame with `Content-Length: 0`. `None` means
the stream ended, the read failed, or the framing was invalid.
These outcomes share one result. `rpcRead` is a convenience that also
returns `""` for `None`; use `rpcReadMsg` to distinguish an empty frame.

Bodies are copied out of the reader's mutable buffer, so later reads
preserve bodies already returned. `rdBuf`, `rdFilled` and `rdConsumed`
expose the buffer and its cursors for tooling. A buffer view can change
after a read.

## Write a reply

`rpcWrite` takes a file descriptor and body, writes the complete frame,
and returns the body's byte length. For a protocol on standard output,
send ordinary logs to a different descriptor.

```scheme fragment
(rpcWrite 1 (jsonWrite reply))
```

The length counts UTF-8 bytes. A body of `"é"` has length 2.
The reader rejects missing, invalid or oversized lengths; its body
limit is 64 MiB. The writer uses the IO short-write loop and terminates
on a write failure.

## Reclaim storage between messages

The reader and its buffer are arena allocations. `rdReseat` supports
callers that explicitly reclaim an arena between messages. It requires
a live reader and a live source range for all unread bytes; copying
from a reclaimed buffer violates its Unsafe precondition.

Tested by `tests/stdlib/390-rpc-framing.ax` and
`tests/stdlib/623-rpc-empty-frame.ax`.

See also: [JSON](json.md), [editor setup](lsp.md) and the
[generated API](stdlib-api.md#rpc).
