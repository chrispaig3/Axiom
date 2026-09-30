# The AXQLite file format

This page specifies the bytes of an AXQLite database file and of its
rollback journal, and the protocol that keeps the file whole through a
crash. You need it to write a tool that reads a database directly, or
to check what the storage layer promises. To use a database, read the
AXQLite guide instead.

## At a glance

A database is one file of 4096-byte pages. Beside it, `<file>-journal`
holds the original bytes of the pages a write transaction changes.
This program makes a new database and asks how many pages it has:

```scheme
(import IO)
(import Err)
(import Axqlite.Pager)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (pagerOpen "notes.db" true false 64)
    ((Err e) { (println (errorText e)) 1 })
    ((Ok p)
      (let ((pages (unwrapOr (andThen (pagerBeginRead p) (lambda (_) (pagerPageCount p))) 0)))
        {
          (println "{pages} pages")
          (let ((_ (pagerClose p))) 0)
        }))))
```

```text
2 pages
```

The file starts with the header page. Its first 64 bytes:

```text
00000000: 4158 514c 6974 6520 666f 726d 6174 2031  AXQLite format 1
00000010: 0000 0000 0000 0001 0000 1000 0000 0002  ................
00000020: 0000 0000 0000 0000 0000 0000 0000 0001  ................
00000030: 0000 0001 0000 0000 0000 0000 0000 0000  ................
```

That is the magic, format version 1, page size 4096, two pages, an
empty free list, change counter 1, and the schema table's root at page
1. Every multi-byte integer in the file and the journal is big-endian.

## Pages

Pages are numbered from 0, and page `n` starts at byte `n * 4096`. A
file holds at most 2^31 pages. The file's length is always its page
count times 4096; any other length is corruption.

Every page ends with an 8-byte checksum. Bytes 4088-4095 hold the
XXH64 hash of bytes 0-4087, seeded with the page's number. XXH64 is
the published algorithm: 64-bit words are read little-endian, and the
hash is stored big-endian like everything else. The seed means a valid
page written at the wrong place fails its check. Every page read from
the file is checked, and one that fails answers `axqCorrupt`.

The first byte of every page but page 0 says what it is:

| Byte 0 | Page |
|---|---|
| 1 | table leaf |
| 2 | table interior node |
| 3 | index leaf |
| 4 | index interior node |
| 5 | overflow page |
| 6 | free page |

## The header page

| Offset | Size | Field |
|---|---|---|
| 0 | 16 | the magic `AXQLite format 1` |
| 16 | 4 | zero |
| 20 | 4 | format version, 1 |
| 24 | 4 | page size, 4096 |
| 28 | 4 | page count, header included |
| 32 | 4 | first page of the free list, 0 when it is empty |
| 36 | 4 | pages on the free list |
| 40 | 8 | change counter |
| 48 | 4 | root page of the schema table, always 1 |
| 52 | 4 | zero |
| 56 | 8 | schema version |
| 64 | 64 | eight meta words for the layer above, 8 bytes each |
| 128 | 3960 | zero |
| 4088 | 8 | checksum, seed 0 |

A file whose first 16 bytes aren't the magic, or whose version isn't
1, answers `axqNotADatabase`. A header that fails its checksum, or
whose page count, free list or schema root is out of range, answers
`axqCorrupt`.

Every commit that changes anything adds one to the change counter. A
connection compares it with the counter its page cache was filled
under whenever it takes a lock, and drops the cache when they differ.
`pagerBumpSchemaVersion` raises the schema version; the AXQL layer
does it for every change to the schema.

## B-tree nodes

Tables and indices use one B+tree. A node is a slotted page: a header,
an array of 2-byte cell offsets growing up from byte 12, and cells
growing down from byte 4088.

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | type: 1 to 4, from the table above |
| 1 | 1 | zero |
| 2 | 2 | cell count `n` |
| 4 | 2 | offset of the lowest cell byte |
| 6 | 2 | free bytes: 4076 - 2`n` - the cells' sizes |
| 8 | 4 | right child, on interior nodes; 0 on leaves |
| 12 | 2`n` | cell offsets, in key order |

A leaf cell holds a key and its value:

| Size | Field |
|---|---|
| 2 | key length `k`, at most 1000 |
| 4 | value length `v` |
| `k` | the key |
| `l` | the first `l` bytes of the value |
| 4 | first overflow page, only when `l` < `v` |

The value stays whole in the cell when `6 + k + v` is at most 1016
bytes, so `l` is `v`. Otherwise the cell is exactly 1016 bytes: `l` is
`1006 - k`, and the rest of the value goes to a chain of overflow
pages.

An interior cell is a child and a key:

| Size | Field |
|---|---|
| 4 | child page |
| 2 | key length `k` |
| `k` | the key |

A cell's child holds the keys below the cell's key, and at or above
the previous cell's key. The right child holds the keys at or above
the last cell's key. Keys compare bytewise as unsigned bytes, and a key
sorts before every longer key it is a prefix of.

A tree is named by its root page, which never moves: when the root
splits, its cells go down into two new pages and the root becomes an
interior node over them. Every leaf is at the same depth. A leaf that
deletes empty is freed, and an interior node left with one child is
replaced by it. Nodes aren't merged or rebalanced otherwise.

Each node is checked when it is read from the file: its type, its
header, that every cell lies inside the page, that no key exceeds 1000
bytes, and that the free count adds up. A tree deeper than 40 levels
answers `axqCorrupt`.

## Overflow and free pages

An overflow page carries the next part of one value:

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | 5 |
| 1 | 1 | zero |
| 2 | 2 | bytes of the value on this page, 1 to 4080 |
| 4 | 4 | next overflow page, 0 on the last |
| 8 | 4080 | the value's bytes, zero after the used ones |

A chain holds exactly the value's remaining `v - l` bytes. A chain
that ends early or runs past them is corruption.

A free page is `6` in byte 0, the next free page (or 0) at bytes 4-7,
and zeros. The header points at the first. Freeing a page pushes it on
the front of the list, and a new page comes from the front before the
file grows. Freeing the file's last page shortens the file instead.

## Records

A table's value is a record: one row's values in column order.

| Size | Field |
|---|---|
| 2 | column count `c`, at most 65535 |
| `c` | a type code per column: 0 `NULL`, 1 `INTEGER`, 2 `REAL`, 3 `TEXT`, 4 `BLOB` |
| ... | the payloads, in column order |

An `INTEGER`'s payload is 8 bytes of two's complement, a `REAL`'s the
8 bytes of its IEEE 754 binary64 encoding, and a `TEXT` or `BLOB`'s a
4-byte length and then the bytes. `NULL` has none. A record is at most 1 GiB,
and a NaN can't be stored. Decoding checks every length against the
record's size, and a short record, a leftover byte or an unknown type
code answers `axqCorrupt`.

The record `[NULL, -2, 1.5, 'ab', x'']` is these 33 bytes:

```text
0005 00 01 02 03 04 fffffffffffffffe 3ff8000000000000 00000002 6162 00000000
```

## Keys

A table is keyed by rowid. Its key is the rowid's 8 bytes with the
sign bit flipped, so bytewise order is numeric order: rowid 1 is
`8000000000000001`.

An index is keyed by its columns' values, encoded so that comparing
two keys bytewise orders them as the values order, followed by the
rowid's 8-byte key. The rowid makes every index key unique, and an
index entry's value is empty.

Each value is a tag byte and a body:

| Tag | Value | Body |
|---|---|---|
| 01 | `NULL` | none |
| 02 | a negative number | 2-byte exponent and 8-byte mantissa, each with every bit inverted |
| 03 | zero | none |
| 04 | a positive number | 2-byte exponent, 8-byte mantissa |
| 05 | `TEXT` | the bytes, each 00 written as 00 FF, then 00 01 |
| 06 | `BLOB` | the same |

A non-zero number is written as its exact magnitude 1.m × 2^e. The
exponent field is `e + 1075`, and the mantissa is the bits after the
leading one, left-aligned in 64 bits. `INTEGER` and `REAL` use the
same encoding, so the integer 2 and the real 2.0 are one key, as are
0, 0.0 and -0.0, and 2^53 + 1 sorts above the real 2^53. An infinity
has exponent field 2099 and mantissa 0, beyond every finite number.

So `NULL` sorts before every number, numbers before `TEXT`, and `TEXT`
before `BLOB`. The escaping makes a string sort before every longer
string it is a prefix of, and lets one contain 00 bytes. A key is at
most 1000 bytes; a longer one answers `axqTooBig`.

The index key for `[NULL, -2, 1.5, 'a\0b', x'']` and rowid 7:

```text
01 02 fbcb ffffffffffffffff 04 0433 8000000000000000 05 61 00ff 62 0001 06 0001 8000000000000007
```

## The rollback journal

The journal is `<file>-journal`. Its first 512 bytes are a header:

| Offset | Size | Field |
|---|---|---|
| 0 | 16 | `AXQLite journal` and a zero byte |
| 16 | 4 | journal version, 1 |
| 20 | 4 | page size, 4096 |
| 24 | 4 | the database's page count before the transaction |
| 28 | 4 | zero |
| 32 | 8 | salt |
| 40 | 8 | XXH64 of bytes 0-39, seed 0 |
| 48 | 464 | zero |

Records follow, 4108 bytes each: the page number (4 bytes), the page's
original 4096 bytes, and the XXH64 of those 4100 bytes seeded with the
salt. A new salt is made for every transaction from the clock, the
process, the connection and the change counter, so a record left over
from an earlier transaction doesn't verify under a later header.

A journal whose header is all zeros, or whose header fails its check,
is empty.

## Writing a transaction

A write transaction runs these steps:

1. Take the exclusive lock, or answer `axqBusy`.
2. Before a page that was in the file at the start is first changed,
   append its original bytes to the journal. The first record of a
   transaction cuts the journal to nothing and writes a new header.
   Pages added by the transaction aren't journalled.
3. When the page cache must evict a changed page before the commit,
   sync the journal, then write the page to the file.
4. To commit: write the new header into page 0, sync the journal,
   write every changed page, truncate the file if it shrank, and sync
   the file.
5. Write zeros over the journal's header, and sync the journal. This
   last sync is the commit point.

Syncing is `fsync`, and on Darwin `fcntl(F_FULLFSYNC)`, because a
plain `fsync` there stops at the drive's own cache.

When `pagerCommit` answers `Ok`, the transaction is durable. When it
answers `Err`, it has been rolled back and the file is as it was. A
rollback copies every journal record back into the file, truncates the
file to its original length and syncs it, then zeroes the journal's
header. When nothing reached the file, a rollback just drops the
changed pages.

## Recovery

A journal is hot when its header is valid and its first record
verifies. Whenever a connection takes a lock it first looks for a hot
journal, and when it finds one it takes the exclusive lock and:

1. copies every record that verifies back into the file, stopping at
   the first that doesn't, so a torn last record is ignored;
2. truncates the file to the header's original page count;
3. syncs the file;
4. zeroes the journal's header and syncs the journal.

A crash during recovery leaves the journal hot, and the next lock
recovers again. A connection opened read-only can't recover a hot
journal, and answers `axqReadOnly` until a writable one has.

The property all of this gives: after a crash at any write, sync or
truncate of a transaction, its commit or its recovery, reopening the
file gives exactly the database before the transaction or exactly the
one after it, byte for byte.

A new database is made the same way, as a transaction from zero pages.
Its journal's one record gives page 0 back its zeros, so a crash
while the file is being created leaves a journal that empties the file
again, and the next open creates it afresh.

## Locking

A connection opens the file itself and locks it with `flock`: shared
for a read, exclusive for a write transaction. The lock belongs to the
open file, so two connections in one process exclude each other as two
processes do. Locks never wait: one that isn't available answers
`axqBusy` with nothing changed.

Going from a shared lock to the exclusive one isn't atomic, so a
connection that fails to upgrade has lost its read lock too, and its
transaction must start again. `flock` is advisory, and on a network
file system it may not work at all.

## Limits

- Pages are 4096 bytes, and a file holds at most 2^31 of them.
- A key is at most 1000 bytes, a value at most 2,147,483,647 bytes, and
  a record at most 1 GiB and 65535 columns.
- Deleting frees pages that empty, but doesn't merge or rebalance
  nodes, and nothing compacts the file. It shrinks only when the pages
  freed are at its end.
- The checksums catch damage and misplaced writes, not tampering:
  XXH64 isn't a cryptographic hash.
- Durability is only as good as the storage's `fsync`.

Tested by `tests/axqlite/105-format-kat.ax` and `tests/axqlite/201-crash-insert.ax`.

## See also

- [The AXQLite guide](axqlite.md): using a database, its transactions
  and its concurrency model.
- [The AXQL reference](axql.md): the query language.
