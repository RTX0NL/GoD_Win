# WIA / RVZ — Implementation Record

Swift-native **decoder** for Dolphin's WIA and RVZ disc image formats,
shipped as one `GODDESS` operation:

- `rvzDump` — `.wia` / `.rvz` → `.iso`

Paired with the format reference at
[`RVZ - Dolphin Disc Image.md`](./RVZ%20-%20Dolphin%20Disc%20Image.md).

This file was a forward plan; it now records what was built, what was
deliberately left out, and the decisions that turned out to matter.

## What shipped

| Piece | Where |
|---|---|
| Zstandard decoder (pure Swift) | `GoDFoundation/Data/Compression/Zstd/` |
| XXH64 (frame checksums) | `GoDFoundation/Data/Crypto/XXHash64.swift` |
| `wia_file_head_t`, `wia_disc_t` | `Dolphin/File Formats/WIAHeader.swift` |
| `wia_part_t`, `wia_raw_data_t`, group entries, exception lists | `Dolphin/File Formats/WIAPartition.swift` |
| Junk PRNG + packing codec | `Dolphin/File Formats/RVZPacking.swift` |
| Whole-file model and restore | `Dolphin/File Formats/RVZImage.swift` |
| Wii hash-tree rebuild + re-encryption | `Wii/File Formats/WiiRVZPartitionRestorer.swift` |
| Operation | `GODSDK/Operations/Dolphin/RVZDump*.swift` |
| Test images (independent encoder) | `FixtureCatalog/RVZFixtures.swift` |

## Non-goals

- **Writing WIA or RVZ.** Producing one needs a Zstandard *encoder*, which
  is a much larger job than the decoder and buys nothing: the tool reads
  these images to get an ISO it can work on, and writes ISOs back.
  `rvzBuild` does not exist and is not planned.
- **bzip2, LZMA, LZMA2.** Legacy WIA compression. Refused by name. No
  sample has come up; add one only when a real file needs it.
- **PURGE** (WIA compression ID 1). Legacy, RVZ forbids it, refused.

## The compression dependency, resolved

The original plan called for vendoring zstd's C source through SwiftPM.
That was reversed: the decoder is **pure Swift**, for the same reason AES,
SHA-1 and the LZ77 family are. A C target would have been the first thing
in the tree that doesn't build wherever Swift does, and the package has no
other C dependency to amortise the build-system cost against.

Decoding is the whole requirement — writing RVZ is a non-goal — and a
decoder is a fraction of a full codec. The result is about 1,000 lines
across four files.

## What the validation actually proved

Three checks, each catching something the others could not.

- **Cross-implementation, against the `zstd` CLI.** Every compressed test
  fixture was produced by the reference encoder, so the decoder is checked
  against an independent implementation rather than against itself. 134
  vectors during development, 5 checked in.

- **The reference's own precomputed tables.** `ZstdPredefinedTableTests`
  compares all three predefined FSE tables state by state against the
  arrays in facebook/zstd. This is the highest-value test in the decoder:
  a mis-transcribed distribution still builds a table that fills its 64
  states and still decodes most streams. The match-length distribution was
  wrong twice — five `-1` entries, then seven in the wrong place — and each
  time it only showed up as a long match decoded as a short one.

- **A real 2.6 GB corpus.** Two of one disc's 35,859 groups failed, and
  nothing smaller reproduced it: a sequence whose offset, match-length and
  literal-length extra-bit fields together overran the bit reader's 64-bit
  window. The common sequence asks for far fewer bits, so reading all three
  plus the three state updates without reloading is right almost always.
  That frame is now a checked-in fixture.

For the container itself:

- **GameCube junk cross-checks against `JunkStream`.** Two independent
  generators — RVZ's inline 68-byte seeds and NKit's game-ID derivation —
  must agree because they describe the same physical bytes. 209 of 209
  sampled windows across 848 MB matched, including deliberately unaligned
  offsets, which is what exercises the `offset % 0x8000` advance.

- **Wii partitions verify cryptographically.** A restored partition's
  recomputed H0/H1/H2 chain up to the H3 table, and H3 comes verbatim from
  the image's unencrypted raw data. All 2,191 groups of a 4.7 GB disc
  matched, which is a proof that 4.4 GB of decrypted payload, the rebuilt
  hash tree and the AES round trip are all correct.

## Things worth knowing before touching this

- **The junk generator is not seeded by the seed alone.** It is advanced by
  `offset % 0x8000` first, and the offset advances over literal segments
  too. See the format reference.
- **Exception-list offsets are chunk-local below a 2 MiB chunk** and have to
  be shifted by where the chunk sits in its 2 MiB group.
- **H3 is not recomputed.** It lives in the partition's unencrypted header,
  which the image stores verbatim; deriving it would overwrite the disc's
  own value.
- **An RVZ group can opt out of compression individually** (bit 31 of
  `data_size` clear), and when it does its exception lists are stored
  plainly and padded to a 4-byte boundary. That is the only place the
  payload's layering changes shape.
- **WIA and RVZ are told apart by magic**, not by a compression heuristic.
  The magic decides the group table's stride, 12 bytes against 8.

## Not done

- **Booting a restored ISO in an emulator.** The hash-chain check is
  strong evidence, but no rebuilt image has been run.
- **A WIA corpus.** Everything measured is RVZ/Zstd, because that is what
  Dolphin writes now. The WIA paths (8-byte group entries, no packing) are
  covered by synthetic fixtures only.

## Streaming, which is done

`discImageView` returns a `GoDReadable` that decodes the block a read lands in,
and `FileHandleAccess.write` already pulled a readable in 8 MB windows — so no
writer infrastructure was needed, only an addressable decode. `restoreISO()`
remains as `materialized()` over the view, and is the reference the equivalence
tests compare against.

Measured on the 4.7 GB Wii disc: peak footprint **6.13 → 2.84 GiB**, 186 s.
That is the output buffer gone, but the remainder still scales with output size
(1.46 GB out peaks at 0.56 GiB), which the bounded caches don't account for —
unprofiled, most likely dirty-page write-back and allocator churn. A halving,
not constant memory.

The same treatment was applied to the Wii *rebuild* path, which had the
identical problem in its own code and stacked four full-size copies. Both now
compose `GoDCompositeData` — the lazy form of "make a `GoDData(length: 0)` and
`write` each part at its offset" — see CLAUDE.md's "Wii ISO Encryption".
