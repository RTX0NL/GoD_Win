# Yaz0 / Yay0 — Nintendo LZ77 Compression

Nintendo's in-house LZ77 codec, in its two container shapes. Yay0 came
first and appears in earlier GameCube titles; Yaz0 replaced it and has been
in use from the GameCube through the Switch, most visibly as the contents of
a `.szs` file and as the usual wrapper around RARC and U8 archives.

Neither is used by Colosseum, XD or Battle Revolution — those compress with
Genius Sonority's own LZSS inside FSYS entries (see
[FSYS - Archive Container](FSYS%20-%20Archive%20Container.md)). Yaz0/Yay0
support exists for general GameCube/Wii titles and as a prerequisite for
RARC and U8.

**Implementation:** `GoDFoundation/Data/Compression/` —
`Yaz0Compressor`, `Yay0Compressor`, the shared `LZ77Encoder`, and
`CompressionFormat` for sniffing a stream.

## The compression, once

Both formats make identical decisions and differ only in how they are
written down. A stream is a sequence of operations, each either a literal
byte or a back-reference:

| | |
|---|---|
| Window | 0x1000 bytes — a match may reach up to 4096 bytes back |
| Match length | 3...0x111 (3...273) |
| Distance | stored one less than it is, so the 12-bit field covers the whole window |

A back-reference is two bytes, `nnnn dddd dddd dddd`:

- `d` — distance minus one. The source is `output.count - (d + 1)`.
- `n` — length minus two, giving lengths 3...0x11.
- `n == 0` is the escape: the length comes from a **third** byte instead,
  as `that byte + 0x12`, giving lengths 0x12...0x111.

A match is allowed to reach past the current output position — `distance 1,
length 40` is a 40-byte run of one value. Decoders therefore copy one byte
at a time, never a block move.

A two-byte match is never emitted: it costs the same two bytes as the
literals it would replace, so it degrades to literals.

## Yaz0 layout

One interleaved stream. Everything big-endian.

| Offset | Size | Field |
|--------|------|-------|
| 0x00 | 4 | Magic `Yaz0` |
| 0x04 | 4 | Uncompressed size |
| 0x08 | 4 | Alignment hint — 0 on GameCube/Wii, used from Wii U on |
| 0x0C | 4 | Reserved (0) |
| 0x10 | … | Groups |

A group is one flag byte followed by the eight operations it describes,
**most significant bit first**. A set bit is a literal (one byte follows); a
clear bit is a back-reference (two or three bytes follow). The final group
may be short — decoding stops on the declared size, not on a group boundary,
so its unused flag bits are never reached.

### Worked example

`ABCABCABCABCD` — three literals, a 9-byte match three bytes back
(overlapping itself), then one literal:

```
59 61 7A 30              "Yaz0"
00 00 00 0D              13 bytes out
00 00 00 00              alignment
00 00 00 00              reserved
E8                       1110 1000 — literal ×3, match, literal
41 42 43                 'A' 'B' 'C'
70 02                    n=7 -> length 9; d=0x002 -> distance 3
44                       'D'
```

## Yay0 layout

The same operations, split into three tables laid end to end. Everything
big-endian.

| Offset | Size | Field |
|--------|------|-------|
| 0x00 | 4 | Magic `Yay0` |
| 0x04 | 4 | Uncompressed size |
| 0x08 | 4 | Offset of the link table |
| 0x0C | 4 | Offset of the chunk table |
| 0x10 | … | Mask table |

- **Mask table** — 32-bit words read most significant bit first, one bit per
  operation, same meaning as Yaz0's flag bytes. Because it is consumed a
  word at a time it is always padded out to a whole number of words.
- **Link table** — the two-byte back-reference fields, one per match.
- **Chunk table** — literal bytes *and* the third byte of a long match,
  interleaved in operation order.

The same `ABCABCABCABCD`:

```
59 61 79 30              "Yay0"
00 00 00 0D              13 bytes out
00 00 00 14              link table
00 00 00 16              chunk table
E8 00 00 00              mask word
70 02                    the one match
41 42 43 44              'A' 'B' 'C' 'D'
```

## Encoder notes

The match finder in `LZ77Encoder` reproduces the semantics of the
widely-mirrored reference encoder (`simpleEnc` / `nintendoEnc`): longest
match wins, the furthest back wins a tie, and Nintendo's one-byte deferral
is applied — if emitting a literal here lets the *next* position take a
match at least two bytes longer, the literal is taken.

Two deliberate departures, both for speed:

- Candidates come from a 3-byte hash chain rather than a linear scan of the
  window. Since a match shorter than three bytes is never emitted, this is
  the same candidate set a linear scan would have found its winner in — no
  behavioral difference.
- Match length is measured up to 0x111 rather than to the end of the input.
  The reference compares *unclamped* lengths and clamps only when writing,
  so where several candidates all run past the maximum it may pick a
  different one. Both streams decode to the same bytes and are the same
  size; only the distance bytes differ. Without this, a large run of one
  value costs O(n²).

### On byte-identical output

Yaz0 is **not** a declared 1:1 target (see the philosophy section of
`CLAUDE.md`). It is a plausible candidate — the reference encoder is known
to reproduce many retail `.szs` files exactly — but nothing here has been
measured against a real corpus, because none of the games this tool
currently opens use the format. Promoting it would mean acquiring a corpus,
measuring, and naming whatever divergences remain, exactly as FSYS did.

## Validation

- `Yaz0CompressorTests` / `Yay0CompressorTests` — round trips, header
  parsing, and the error paths a corrupt stream takes.
- `ReferenceLZ77Decoders` — deliberately independent decoders, transcribed
  from this document rather than derived from the production code, that
  every round-trip test also checks its stream against. A round trip alone
  would only prove the encoder and decoder agree with each other.
- Hand-authored streams (the two worked examples above, plus a long-match
  case) stand in for real-world ground truth on the decode side.
- `NintendoCompressionGoldenTests` — freezes what the encoders emit, so
  unintended drift fails. Not evidence of matching Nintendo's tooling.

## References

- **WiiBrew / CloudModding wikis** — Yaz0 and Yay0 layouts.
- The `simpleEnc` / `nintendoEnc` reference encoder, mirrored across many
  GameCube/Wii toolchains.
