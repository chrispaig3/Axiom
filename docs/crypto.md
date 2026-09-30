# Cryptography

Axiom's standard library includes a cryptography suite written in
Axiom. It links nothing extra and adds no C library, so a program that
encrypts or signs still builds from the same freestanding toolchain as
any other. This page shows how to use it, what each part promises, and
where its limits are.

```scheme
(import IO)
(import Err)
(import Crypto.Random)
(import Crypto.Secret)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (secretRandom 32)
    ((Ok key)
      {
        (println "{key}")
        (println (secretLen key))
        (secretWipe key)
        0
      })
    ((Err e) (die (errorText e) 1))))
```

```text
<SecretBytes>
32
```

The key never reaches the output. A secret prints as its type's name,
and `secretWipe` erases it when you are done.

## Random values

`Crypto.Random` answers secure random values from the operating
system's kernel on every call:

| Call | Answers |
|---|---|
| `(secureRandomBytes n)` | `n` random bytes |
| `(randomBelow n)` | an `Int` in `0` to `n - 1`, each value equally likely |
| `(randomRange lo hi)` | an `Int` in `lo` to `hi - 1` |
| `(randomShuffle v)` | shuffles a `Vec` in place into a uniformly random order |
| `(randomTokenUrl n)` | `n` random bytes as URL-safe base64, for tokens and identifiers |
| `(randomTokenHex n)` | `n` random bytes as lower-case hex |

Each one answers a `Result`. The source is `getentropy` on Darwin and
`getrandom` on Linux and FreeBSD. On `baremetal-aarch64` it is the
CPU's `RNDR` register when the CPU has one. There's no generator
inside your program, so there is no seed to manage, nothing a `fork`
duplicates, and nothing threads share.

There's no fallback either. When the kernel call fails, or the target
has no secure source, you get `Err` with code `cryptoEntropyFailed` or
`cryptoEntropyUnavailable`. Nothing substitutes a clock, a process id
or a counter. `randomAvailable` tells you ahead of time whether this
target has a source.

`randomBelow` rejects draws outside the range rather than reducing
them with `%`, so small values aren't favoured. A token needs at least
16 bytes (128 bits) to be unguessable.

Random values are not unique values. Two random 96-bit nonces collide
with probability about n²/2⁹⁷ after n messages, so an authenticated
cipher sets a limit on how many random nonces one key may use.

Tested by `tests/crypto/020-random.ax`.

## Keys and secrets

A secret is a handle, not a buffer. `SecretBytes` and every key type in
the suite are sealed: only the module that declares the type can make
one or read what's inside. A secret prints as `<SecretBytes>`, so it
can't reach a log line, a `Json` value or a formatted string by
accident. One algorithm's key type can't be passed where another's is
expected.

```scheme fragment
(secretRandom 32)          ; a fresh random secret
(secretFromString bytes)   ; a secret holding a copy of these bytes
(secretEq a b)             ; compares in constant time
(secretWipe k)             ; erases and frees it
(secretExposeCopy k)       ; a plain copy, for writing a key out
```

Each secret lives in a memory mapping of its own, outside the arena,
so a region reset can't reclaim it while you still hold it. The suite
asks the kernel to keep that mapping out of swap (`mlock`) and, on
Linux and FreeBSD, out of core files. Both requests can be refused: an
unprivileged process may lock only a few megabytes. The secret still
works when they are, and `(secretIsLocked k)` tells you which you got.

`secretWipe` overwrites the whole mapping with zeros in a way the
optimiser can't remove, then unmaps it. Using a secret after wiping it
stops the program with status 85, and so does passing one key type's
handle where another's is expected. The suite wipes every temporary it
derives from a secret, such as a key schedule, before it returns.

Erasure has limits you should know:

- A copy you made with `secretExposeCopy` is an ordinary string. The
  suite can't find it to wipe it.
- Values that were in registers or on the stack while an operation ran
  aren't cleared.
- A `parallel` binding that runs in a forked child gets a copy of every
  secret mapping, and wiping in the parent doesn't reach it.
- A secret you never wipe stays mapped until the program exits. There
  is no destructor.

Tested by `tests/crypto/030-secret.ax` and
`tests/stdlib/640-crypto-secret-wiped.ax`.

## Byte strings

A `String` holds any bytes, so the suite uses it for public byte data:
messages, ciphertexts, digests and encoded keys. `Crypto.Bytes` has
what you need around them:

- `bytesEqCt` compares two strings in time that depends only on their
  lengths. Use it, never `==`, for tags and digests of secrets.
- `hexEncode` and `hexDecode`, `b64Encode` and `b64Decode`, and the
  unpadded and URL-safe variants, run in constant time.
- The decoders are strict. A character outside the alphabet, padding
  in the wrong place, or leftover bits that aren't zero is an `Err`, so
  every byte string has exactly one accepted encoding.
- `bytesU32Be`, `bytesU64Le` and their kin encode integers.

Tested by `tests/crypto/010-bytes.ax`.

## Hashes

A hash turns a message of any length into a short digest. The same
message always gives the same digest, and no one can find two
messages that share one.

```scheme
(import IO)
(import Crypto.Bytes)
(import Crypto.Sha2)
(import Crypto.Sha3)
(import Crypto.Blake2b)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((h sha256New))
    {
      (println (hexEncode (sha256 "abc")))
      (sha256Update h "a")
      (sha256Update h "bc")
      (println (hexEncode (sha256Final h)))
      (println (hexEncode (sha3_256 "abc")))
      (println (hexEncode (shake256 "abc" 16)))
      (println (hexEncode (blake2b256 "abc")))
      0
    }))
```

```text
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
483366601360a8771c6863080cc4114d
bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319
```

Each one-shot function takes a `String` and answers the digest's raw
bytes, which `hexEncode` makes printable. For a message that arrives
in pieces, make a state with `sha256New`, feed it with
`sha256Update`, and take the digest with `sha256Final`. The second
line shows it gives the same answer. `Final` leaves the state fresh
for the next message.

| Module | Functions | Digest |
|---|---|---|
| `Crypto.Sha2` | `sha256`, `sha384`, `sha512` | 32, 48 or 64 bytes |
| `Crypto.Sha3` | `sha3_224`, `sha3_256`, `sha3_384`, `sha3_512` | 28 to 64 bytes |
| `Crypto.Sha3` | `shake128`, `shake256` | as many bytes as you ask for |
| `Crypto.Blake2b` | `blake2b256`, `blake2b512`, and `blake2b` with a length and an optional key | 1 to 64 bytes |

Use SHA-256 unless a protocol asks for something else. SHAKE128 and
SHAKE256 are extendable-output functions: `(shake256 msg n)` answers
`n` bytes, and a `Shake256` state lets you squeeze more output as
often as you like.

Tested by `tests/crypto/100-sha2.ax` and `tests/crypto/110-sha3.ax`.

## Message authentication and key derivation

A message authentication code (MAC) proves that a message came from
someone holding the key and hasn't changed since. HKDF turns one
secret into as many independent keys as you need.

```scheme
(import IO)
(import Err)
(import Crypto.Secret)
(import Crypto.Hmac)
(import Crypto.Hkdf)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match hmacSha256KeyGenerate
    ((Err e) (die (errorText e) 1))
    ((Ok key)
      (let ((tag (hmacSha256 key "order 17")))
        {
          (println (strLen tag))
          (println (hmacSha256Verify key "order 17" tag))
          (println (hmacSha256Verify key "order 18" tag))
          (hmacSha256KeyWipe key)
          (match (secretRandom 32)
            ((Err e) (die (errorText e) 1))
            ((Ok shared)
              (match (hkdfSha256 shared "salt" "session keys v1" 64)
                ((Err e) (die (errorText e) 1))
                ((Ok keys)
                  {
                    (println (secretLen keys))
                    (secretWipe keys)
                    (secretWipe shared)
                    0
                  }))))
        }))))
```

```text
32
true
false
64
```

`hmacSha256` answers a 32-byte tag. Check one with
`hmacSha256Verify`, which compares in constant time and accepts only a
full-length tag. HMAC keys are sealed like the cipher keys, and
`hmacSha256KeyFromSecret` takes a `SecretBytes` of any length from one
byte. `Crypto.Hmac` has the same functions for HMAC-SHA-512.

`hkdfSha256` takes input keying material that is already secret, such
as a shared secret from a key exchange, then a salt and an `info`
string naming what the keys are for. It answers up to 255 × 32 bytes
as a `SecretBytes`, and a different `info` gives an independent key.
`hkdfSha256Extract` and `hkdfSha256Expand` are its two halves, for
protocols that call them separately.

HKDF and HMAC are fast by design, so neither is a password hash. A
stored password needs a slow, memory-hard function, and the suite
doesn't have one yet.

Every hash, MAC and XOF state has a `Wipe`. A hash state is left fresh
afterwards; a `Blake2b` or `HmacSha256` state has held a key, so once
wiped it refuses further use.

Tested by `tests/crypto/130-hmac.ax` and `tests/crypto/140-hkdf.ax`.

## Authenticated encryption

An authenticated cipher keeps a message secret and detects any change
to it. The suite has AES-256-GCM, AES-128-GCM and ChaCha20-Poly1305,
each with the same shape:

```scheme
(import IO)
(import Str)
(import Err)
(import Crypto.Aead)
(import Crypto.AesGcm)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match aes256GcmKeyGenerate
    ((Err e) (die (errorText e) 1))
    ((Ok key)
      (match aeadNonceRandom
        ((Err e) (die (errorText e) 1))
        ((Ok nonce)
          (let ((sealed (unwrapOr (aes256GcmSeal key nonce "order 17" "attack at dawn") "")))
            {
              (println (strLen sealed))
              (match (aes256GcmOpen key nonce "order 17" sealed)
                ((Ok plain) (println plain))
                ((Err e) (println (errorText e))))
              (match (aes256GcmOpen key nonce "order 18" sealed)
                ((Ok plain) (println plain))
                ((Err e) (println (errorText e))))
              (aes256GcmKeyWipe key)
              0
            }))))))
```

```text
30
attack at dawn
authentication failed while aes256GcmOpen
```

`Seal` takes the key, a nonce, associated data and the plaintext, and
answers the ciphertext with a 16-byte tag on the end. The associated
data isn't encrypted, but it is authenticated: opening with different
associated data fails, as the third call shows. Use it for whatever
the ciphertext must stay bound to, such as a record id or a header.

`Open` checks the tag before it decrypts anything, so no plaintext is
released from a message that fails. Every failure, whether a wrong key,
a changed byte, a truncated tag or the wrong associated data, answers
the same `cryptoAuthFailed` error.

| Module | Key | Nonce | Tag | Longest plaintext |
|---|---|---|---|---|
| `Crypto.AesGcm` | `Aes256GcmKey` or `Aes128GcmKey` | 12 bytes | 16 bytes | 2³⁶ − 32 bytes |
| `Crypto.ChaCha20Poly1305` | `ChaCha20Poly1305Key` | 12 bytes | 16 bytes | 274,877,906,880 bytes |

Prefer AES-256-GCM where you need a NIST-approved algorithm and
ChaCha20-Poly1305 otherwise. Both run in constant time here: AES is
bitsliced, with no lookup table indexed by a secret. Only one-shot
calls exist, so a message is sealed or opened whole.

Tested by `tests/crypto/220-aes-gcm.ax` and
`tests/crypto/250-chacha20-poly1305.ax`.

### Nonces

A nonce must never repeat under one key. A repeat under GCM reveals
the XOR of two plaintexts and lets an attacker forge tags, so this is
the one rule you can't get wrong. You have two ways to follow it:

- `aeadNonceRandom` draws 12 random bytes. Use at most 2³² of them
  with one key (NIST SP 800-38D section 8.3); past that, the chance of
  a repeat is too high. Rotate the key before then.
- `NonceSequence` counts. `(nonceSequenceNew prefix)` takes a 4-byte
  prefix unique to this sender, and each `nonceSequenceNext` answers
  the next nonce or `cryptoLimitExceeded` once the counter runs out.
  It never wraps.

A sequence is only as unique as its counter. If your program restarts,
resume with `nonceSequenceResume` from a position you saved, and save
the position *before* you seal with the nonce it answers, so a crash
between the two can't make you reuse one. Two processes sharing a key
need different prefixes.

Tested by `tests/crypto/260-aead-nonce.ax`.

## Key agreement

X25519 (RFC 7748) lets two parties that each send the other a public
key arrive at the same 32-byte shared secret. Nobody watching the
exchange can compute it.

```scheme
(import IO)
(import Err)
(import Crypto.Secret)
(import Crypto.X25519)

(:: agree (-> X25519SecretKey X25519SecretKey Int))
;@axiom:effect(io)
(fn (agree alice bob)
  (match (x25519 alice (x25519PublicKey bob))
    ((Err e) (die (errorText e) 1))
    ((Ok s1)
      (match (x25519 bob (x25519PublicKey alice))
        ((Err e) (die (errorText e) 1))
        ((Ok s2)
          {
            (println (secretLen s1))
            (println (secretEq s1 s2))
            0
          })))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match x25519KeyGenerate
    ((Err e) (die (errorText e) 1))
    ((Ok alice)
      (match x25519KeyGenerate
        ((Err e) (die (errorText e) 1))
        ((Ok bob) (agree alice bob))))))
```

```text
32
true
```

The shared secret comes back as `SecretBytes`. Don't use it as a key
directly: pass it through `hkdfSha256` with both public keys in the
info string, as RFC 7748 section 6.1 advises.

Any 32 bytes are a public key, as the RFC requires, so
`x25519PublicKeyFromBytes` checks only the length. When the peer sends
a point of small order, the shared secret comes out all zero, and
`x25519` answers `cryptoInvalidKey` instead. A peer following the
protocol never sends one, so treat the error as a failed exchange.

Tested by `tests/crypto/310-x25519-rfc7748.ax` and
`tests/crypto/311-x25519-wycheproof.ax`.

## Signatures

Ed25519 (RFC 8032) signs a message with a private key, and anyone
holding the matching public key can check the signature. Signing is
deterministic, so the same key and message always give the same
64-byte signature.

```scheme
(import IO)
(import Str)
(import Err)
(import Crypto.Ed25519)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match ed25519KeyGenerate
    ((Err e) (die (errorText e) 1))
    ((Ok key)
      (let ((pk (ed25519PublicKey key))
            (sig (ed25519Sign key "release 0.8.0")))
        {
          (println (strLen (ed25519SignatureBytes sig)))
          (println (ed25519Verify pk "release 0.8.0" sig))
          (println (ed25519Verify pk "release 0.8.1" sig))
          (ed25519KeyWipe key)
          0
        }))))
```

```text
64
true
false
```

Decoding is strict. `ed25519PublicKeyFromBytes` accepts one encoding
per key, and `ed25519SignatureFromBytes` refuses an S at or above the
group order, so a valid signature has no second form that also
verifies. Verification uses the cofactorless equation. It accepts
public keys of small order when the equation holds, as RFC 8032
permits, so if strangers choose the keys, check how they were made.

The Ed25519ctx and Ed25519ph variants aren't provided.

Tested by `tests/crypto/320-ed25519-rfc8032.ax` and
`tests/crypto/323-ed25519-strict.ax`.

## Constant time

A function runs in constant time when nothing an attacker can time
depends on a secret: which branches run, which memory it touches, and
which instructions it uses. The suite's code avoids branches, memory
indices and division that depend on secrets.

Code that looks branchless isn't enough, because the optimiser can
turn a mask back into a branch. `Crypto.Ct` passes every mask a secret
produces through `ctBarrier`, an empty assembly block that hides the
value from the optimiser. Functions that handle secrets carry a
`;@axiom:ct(...)` tag naming their secret parameters.

Some channels are below what Axiom source controls: a multiplier whose
timing depends on its operands, cache lines shared with another
process, and speculative execution. The suite removes the channels
software can see. It can't promise more than the processor does.

In particular, GHASH, Poly1305 and the curve arithmetic
rely on 64-bit multiplication taking the same time for every operand.
Arm promises that only while the DIT bit (FEAT_DIT) is set, and the
suite doesn't set it yet.

`scripts/check-crypto.sh` checks every claimed kernel's optimised IR
at `--opt` 1, 2 and 3 for a branch, a `select`, a memory index or a
division that depends on a secret. A timing measurement would only be
supporting evidence, so there's no timing test in the gate.

## Performance

Measured on darwin-aarch64 at `--opt 1`: whole-process time over many
iterations, best of five, with an empty program's startup subtracted.

| Operation | 1 MiB | 64-byte message |
|---|---|---|
| AES-256-GCM seal | 111 MB/s | 1.42 µs |
| AES-256-GCM open | 97 MB/s | 1.53 µs |
| AES-128-GCM seal | 130 MB/s | 1.14 µs |
| ChaCha20-Poly1305 seal | 226 MB/s | 0.90 µs |
| ChaCha20-Poly1305 open | 217 MB/s | 0.96 µs |
| SHA-256 | 306 MB/s | 0.47 µs |
| SHA-512 | 506 MB/s | 0.35 µs |
| SHA3-256 | 582 MB/s | 0.28 µs |
| BLAKE2b-512 | 996 MB/s | 0.30 µs |
| HMAC-SHA-256, key already loaded | | 0.74 µs |

SHA-256 doesn't use the processor's SHA-2 instructions yet. OpenSSL
3.6.4, which does, hashes about seven times faster on the same machine.

| Operation | Time |
|---|---|
| X25519 shared secret | 79 µs |
| Ed25519 sign, 64-byte message | 39 µs |
| Ed25519 sign, 4 KiB message | 55 µs |
| Ed25519 verify, 64-byte message | 91 µs |
| Ed25519 and X25519 key generation, one of each | 122 µs |

## Error codes

Every Crypto module answers an `Err` carrying one of these codes:

| Code | Name | Means |
|---|---|---|
| 1101 | `cryptoInvalidLength` | a key, nonce, tag, salt or input of a length the algorithm doesn't accept |
| 1102 | `cryptoInvalidEncoding` | bytes that don't decode, or a key or signature that isn't a canonical encoding |
| 1103 | `cryptoAuthFailed` | authentication failed; no plaintext is released |
| 1104 | `cryptoEntropyUnavailable` | this target has no secure entropy source |
| 1105 | `cryptoEntropyFailed` | the kernel's entropy call failed |
| 1106 | `cryptoLimitExceeded` | a usage limit, such as a message length or a nonce sequence that has run out |
| 1107 | `cryptoUnsupported` | parameters this implementation doesn't support |
| 1108 | `cryptoNoSecretStore` | the kernel refused a mapping for a secret, or the handle table is full |
| 1109 | `cryptoInvalidKey` | a key that decodes but must not be used |

Every authentication failure answers the same code and message, so an
error never tells an attacker which check a forgery failed.

## Limits

- Not yet on `windows-x86_64`: there's no entropy source or secret
  store there, and each call answers an availability error.
- On `baremetal-aarch64` there's no page mapping for the secret store,
  so key types aren't available there yet. Random values are, on CPUs
  with `RNDR`.
- The suite hasn't had an external cryptographic review, and it isn't
  a FIPS 140-3 validated module.

## See also

- [stdlib-api.md](stdlib-api.md) lists every public name in the
  `Crypto` modules with its type and effects.
- [memory-model.md](memory-model.md) `MM-PAR-8` describes the handle
  table that the secret store's handles live in.
