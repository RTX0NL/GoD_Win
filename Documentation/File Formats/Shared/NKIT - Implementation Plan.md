# NKIT - Implementation Plan

Swift-native encoder + decoder for Nanook's NKit lossless disc-shrink
format, integrated as two new `GODDESS` operations:

- `nkitDump` — `.nkit.iso` → `.iso` (byte-identical original)
- `nkitBuild` — `.iso` → `.nkit.iso` (lossless shrink)

Paired with the format reference at
[`NKIT - Lossless Shrunk ISO.md`](./NKIT%20-%20Lossless%20Shrunk%20ISO.md).
This doc focuses on module layout, data types, algorithms, and the
phased rollout.

## Status (2026-09-25)

**GameCube is done, and verified against NKit v1's own output.** Our
`.nkit.iso` for Pokemon XD US is byte-identical to the one NKit v1
produced — 1,093,384,192 bytes, zero differences — and restoring either
one reproduces the Redump ISO exactly.

| Phase | State |
|---|---|
| 1 — Junk PRNG | Done. `JunkStream` + tests, confirmed on real discs. |
| 2 — Gap RLE codec | Done and wired. `NKitGapEncoding` encodes and decodes real NKit gaps. |
| 3 — CRC32 + CRC-force | Done and confirmed against NKit's output: CRC-32 of a real `.nkit.iso` equals the CRC stored at `0x208`. Open question 4 answered. |
| 4 — GameCube NKit dump | Done. Real image → byte-identical Redump ISO. |
| 5 — GameCube NKit build | Done. Real ISO → byte-identical to NKit v1's own `.nkit.iso`. |
| 6-8 — Wii | Not started. Both operations refuse a Wii image. |
| 9 — Integration | Partly. `ProjectSetup` auto-detects `.nkit.iso`; the operations are hand-authored only, like the CISO pair. |

### The format, as measured

The system area — disc header, `bi2.bin`, apploader, `main.dol`, FST —
is kept verbatim at its original offsets. After it the files are packed
end to end, each run of junk between them replaced by a gap encoding,
and **the FST is rewritten to the packed offsets**. The image is padded
to a `0x800` boundary.

Two rules carry the layout and neither is readable off a file:

- **A file occupies its length rounded up to 4 bytes**, packed and
  original alike, so a gap is measured from `align4(end)`.
- **A junk run may begin with zeros, and how many is derived.** The
  allowance is `nullsPos - position` with `nullsPos = align4(end of the
  last file) + 0x1C`, dropping to zero for a gap of `0x40000` or more
  that isn't first or last in the list. Measured on six retail discs
  before the source was consulted: junk begins at `align4(gapStart) +
  28` in 49 of 50 sampled gaps, and at `gapStart` in the big interior
  ones.

### What a structural check cannot see

An earlier version implemented a different shape and detected the real
one by asking whether every FST file fits inside the image. For a
packed image it always does — the FST *is* the packed layout — so a
real XD image restored to 1.4 GB that was 99.24 % wrong, and the run
reported success. The gate is the CRC comparison at the end of the
restore, which is step 8 of the algorithm below and had never been
implemented. Do not replace it with a structural check.

### Still open

- **Wii** (Phases 6-8) — needs partition re-hashing and re-encryption,
  and a Wii `.nkit.iso` to validate against.
- **The `junkFile` gap form** — a file whose whole content is junk,
  dropped and regenerated on restore. The decoder handles it; the
  encoder doesn't emit it, so such files are written out instead. Valid,
  slightly larger, and it did not cost byte-identity on XD US.
- **Corpus size** — one disc. More `.nkit.iso` samples would widen it.
- **Memory** — both directions hold whole images, so a build peaks at
  about twice the ISO.

## Goals

- **Byte-identical roundtrip** on every test ISO, matching the bar we
  set for `RELFile`. `dump(build(iso)) == iso` bit-for-bit.
- **Pure Swift**, cross-platform (no CryptoKit, no CommonCrypto).
  Reuses the same primitives we'll need for Wii ISO encryption.
- **Composable with existing ops**: project setup auto-detects
  `.nkit.iso`, chains a `nkitDump` before `gamecubeDump`/`wiiDump`.
- **GameCube first, Wii second**. GC NKit has no crypto — it's pure
  junk/gap removal — and lets us validate the PRNG + gap codec
  independently of the Wii stack.

## Non-goals (this iteration)

- `.nkit.gcz` (Dolphin GCZ-wrapped NKit). Plain `.nkit.iso` only. GCZ
  support would be a follow-up that slots in as an additional
  compression layer.
- Hacked / corrupt image repair. We assume well-formed inputs and fail
  loudly otherwise. NKit v1 has a large surface of recovery paths we
  can skip.
- NKit v2 format changes. The magic `"NKIT v01"` is what we target. If
  future NKit versions appear, we'll extend.

## Module layout

```
Sources/Shared/
├── Core/Engines/Dolphin/
│   ├── Junk/
│   │   └── JunkStream.swift          # Nintendo disc PRNG, seekable
│   └── File Formats/
│       ├── NKitHeader.swift          # 0x200 block parse/serialise
│       ├── NKitImage.swift           # whole-file semantic model
│       ├── NKitGapEncoding.swift     # 4-byte gap headers + block entries
│       └── NKitChecksum.swift        # CRC32 + the CRC-force pad trick
└── Core/Engines/Wii/
    └── Crypto/                       # lives here regardless of NKit; NKit uses it
        ├── AES128CBC.swift
        ├── SHA1.swift
        ├── WiiTitleKey.swift
        └── WiiPartitionCodec.swift   # encrypt/decrypt + hash chain

Sources/Products/GODSDK/Operations/Dolphin/
├── NKitDumpConfig.swift
├── NKitDumpOperation.swift
├── NKitBuildConfig.swift
└── NKitBuildOperation.swift
```

## Data types

### `NKitHeader`

Semantic mirror of the 0x200 block. Public Swift API uses native types;
Codable JSON goes through `HexInt` for addressy fields (same pattern as
`RELFile`).

```swift
public struct NKitHeader: Equatable {
    public enum Platform: Equatable { case gamecube, wii }

    public var platform: Platform         // derived from disc-header magic
    public var version: UInt8             // from "NKIT v01" → 1
    public var originalCRC: UInt32        // offset 0x208
    public var crcForce: UInt32           // offset 0x20C — disc-ID checksum match
    public var originalImageSize: UInt64  // offset 0x210 (x4 on Wii)
    public var junkOverrideID: String?    // offset 0x214, GC only; nil if all-zero
    public var updatePartitionCRC: UInt32? // offset 0x218, Wii only, non-zero if removed
}
```

### `NKitImage`

The whole file, semantic-only. No stored raw byte blobs for regions
that are derivable (junk runs, zero-fill, repeats).

```swift
public struct NKitImage {
    public var diskHeader: [UInt8]        // 0x00-0x1FF, with 0x60/0x61 and 0x2BC restored
    public var nkitHeader: NKitHeader
    public var platform: Platform
    public var files: [DiscFile]          // FST-ordered real files
    public var gaps: [Gap]                // one between each consecutive pair of files
    public var partitions: [WiiPartition] // empty for GC
}

public struct DiscFile {
    public var path: String
    public var discOffset: UInt64
    public var data: Data                 // actual file bytes, kept verbatim
}

public enum Gap: Equatable {
    case allJunk(length: UInt64)
    case allScrubbed(length: UInt64)        // zero fill
    case junkFile(length: UInt64, streamOffset: UInt64)
    case mixed(blocks: [MixedBlock])
}

public enum MixedBlock: Equatable {
    case junk(count: UInt32)              // count × 0x100 bytes from the PRNG
    case nonJunk(bytes: Data)             // literal data, length multiple of 0x100
    case byteFill(byte: UInt8, count: UInt32)
    case repeatPrevious(count: UInt32)    // re-emit the last nonJunk payload N times
}
```

### `JunkStream`

```swift
public struct JunkStream {
    public init(gameID: [UInt8], disc: UInt8, length: UInt64)
    public var position: UInt64 { get set }     // seekable
    public mutating func read(_ count: Int) -> [UInt8]
    public func peek(at: UInt64, count: Int) -> [UInt8]  // non-mutating
}
```

Internally: compute `block = position / 0x40000`, regenerate the 521-
word state for that block from scratch, extract bytes at the right
intra-block offset. No caching in the first pass; if profiling shows
it's a hotspot, add an LRU on `(block → [UInt8; 0x40000])`.

### Gap encoding

`NKitGapEncoding` is the pure codec — no IO, no game knowledge.

```swift
public enum NKitGapEncoding {
    public static func encode(_ gap: Gap) -> [UInt8]
    public static func decode(
        from bytes: [UInt8], length: UInt64,
        junk: JunkStream, junkOffset: UInt64
    ) -> Gap
    public static func expand(_ gap: Gap, junk: JunkStream, at: UInt64) -> [UInt8]
}
```

Encoding is straight from the format doc:
- 4-byte header, low 2 bits = gap type, top 30 bits = gap length
- Mixed gaps: a run of 4-byte block entries; top 2 bits = block type,
  remaining bits = count (in `0x100`-byte units); ByteFill uses the
  low 8 bits as the fill byte
- Lengths ≥ `0xFFFFFFFC` split into two consecutive 4-byte headers

## Algorithms

### `nkitDump` (restore)

1. Read disc header (0-0x1FF). Parse as GameCube / Wii based on magic
   bytes at 0x18 (`0xC2339F3D` for GC) / 0x18 (`0x5D1C9EA3` for Wii).
2. Read the NKit header at 0x200, confirm `"NKIT v01"`, decode fields.
3. Undo header patches:
   - Wii: clear 0x60 and 0x61; restore original `0x2BC` from the
     partition table (tricky: we don't have the original value stored
     directly — it's reconstructed by reading the new partition size
     and multiplying by the group expansion factor 0x8000/0x7C00).
   - Wii: restore original partition-table entries at 0x40000 (the
     writer stashes the original in the NKit header block area past
     0x21C, or derives them).
4. Instantiate `JunkStream(gameID: header.junkOverrideID ?? gameID,
   disc: discNum, length: originalImageSize)`.
5. Walk the FST, enumerate files in on-disc order.
6. Between each adjacent pair of files, read the gap header (4-byte
   aligned), decode with `NKitGapEncoding.expand(...)`, write the
   expanded bytes at the correct offset.
7. Wii only: walk each partition. For each 0x7C00 data block:
   - Recompute H0 SHA-1 hashes
   - Update H1/H2/H3 chains
   - AES-128-CBC encrypt with the partition's title key
   - Write the resulting 0x8000 group
8. Recompute CRC32 of the rebuilt image; assert equals
   `header.originalCRC`. Fail loudly on mismatch.

### `nkitBuild` (shrink)

1. Read and validate the source `.iso`. Reject if already NKit
   (`NKIT` at 0x200).
2. Parse disc header, FST, Wii partition table.
3. Wii: decrypt each partition group, strip the 0x400 hash block,
   store 0x7C00 plaintext payloads in `WiiPartition.blocks`.
4. Build the `JunkStream` for the source ID + disc num.
5. For each gap between files:
   - Compare against the junk stream byte-for-byte
   - Detect zero-fill runs, byte-fill runs, repeats
   - Emit the smallest encoding that reproduces the original bytes
6. Write:
   - Disc header 0x00-0x1FF with patches (Wii: 0x60/0x61 = 1;
     0x2BC = new partition size; 0x40000 table rewritten)
   - NKit header at 0x200 with `"NKIT v01"`, CRC, image size,
     junk-override ID (empty unless game uses an unusual junk seed)
   - Files at their declared offsets
   - Gap encodings between them
7. Compute `crcForce` by brute-forcing a 32-bit pad value into some
   fixed slot so `CRC32(nkit.iso) == CRC32(original)`. NKit calls this
   "CRC forcing"; the slot is typically the `0x20C` field itself —
   writing `crcForce` there makes the CRC come out right. Algorithm
   is a well-known reverse-CRC trick (≈ 50 lines of Swift).

### Junk detection (encoder)

Comparing every gap byte against the PRNG is straightforward but has
subtleties:

- Gaps may be partly junk, partly scrubbed (zero). Split at 256-byte
  boundaries and tag each block independently.
- Scrubbed regions (where a tool nulled out junk without regenerating
  it) are detected as runs of `0x00` that *don't* match the PRNG —
  encoded as `Mixed → NonJunk(zeros)` or preferably `Mixed → ByteFill(0, N)`.
- Repeats: if the same `0x100` block appears N times consecutively in
  the source and doesn't match the PRNG, we emit one NonJunk + a
  Repeat. Saves a lot of space on some discs.

## Phases & estimated cost

Each phase is sized so it's a single-session delivery with a clear
byte-identity gate before moving on.

### Phase 1 — Junk PRNG *(1 session)*

`JunkStream.swift` + tests. Validate against a known Redump clean GC
ISO: hash the first 4 × 0x40000 blocks starting from a known junk
region and compare against bytes extracted from the real ISO at the
same offsets.

**Done when**: seeded with a real Game ID + disc, bytes match the
source ISO's junk region exactly for at least 3 corpus discs.

### Phase 2 — Gap RLE codec *(1 session)*

`NKitGapEncoding.swift` + tests. No IO. Roundtrip every gap case by
hand-building and decoding.

**Done when**: `decode(encode(gap)) == gap` for all gap types and
representative lengths including the `0xFFFFFFFC` split case.

### Phase 3 — CRC32 + CRC-force *(0.5 session)*

`NKitChecksum.swift`. Standard CRC32 we probably already have
somewhere; the force algorithm is new.

**Done when**: given original + modified images, the force value
written at 0x20C makes both CRC32s equal.

### Phase 4 — GameCube NKit dump *(2 sessions)*

Parse `NKitHeader`, read FST, walk gaps, expand to `.iso`, verify CRC.

**Done when**: every `.nkit.iso` in our GC test corpus dumps to a
byte-identical `.iso`. We'll need real `.nkit.iso` samples — option A:
user drops a couple into `scripts/`; option B: build them on Windows
via NKit v1 and copy over.

### Phase 5 — GameCube NKit build *(2 sessions)*

Reverse direction. This is where the junk detection heuristics get
exercised.

**Done when**: `dump(build(iso)) == iso` for every corpus GC ISO, and
`build(iso) == nkit_produced_by_NKit_v1(iso)` byte-for-byte on at
least one reference sample.

### Phase 6 — Wii crypto primitives *(1-2 sessions)*

`AES128CBC.swift`, `SHA1.swift`, `WiiTitleKey.swift`. Pure Swift.
Tests against RFC / NIST vectors plus a real Wii partition decrypt →
encrypt roundtrip.

**Done when**: decrypt + re-encrypt reproduces the original partition
bytes exactly.

### Phase 7 — Wii NKit dump *(2 sessions)*

Extends Phase 4 with partition re-encryption, hash recomputation,
header patch reversal.

**Done when**: a reference Wii `.nkit.iso` restores byte-identically
to its original `.iso`.

### Phase 8 — Wii NKit build *(2 sessions)*

Extends Phase 5 symmetrically.

**Done when**: Wii roundtrip holds.

### Phase 9 — Integration *(1 session)*

- Auto-detect `.nkit.iso` in `ProjectSetup` and chain `nkitDump`
  before the regular ISO unpack
- Optional `nkitBuild` step after `gamecubeBuild`/`wiiBuild`
- `.nkit.iso` surfaced as a first-class output artifact

## Testing strategy

Four layers, each independent:

1. **Unit** — `JunkStream`, `NKitGapEncoding`, `NKitChecksum`,
   crypto. Pure functions, deterministic, no corpus needed. Run on
   every commit.
2. **Reference-vector** — known PRNG bytes from real discs, known AES
   test vectors, known CRC-force outputs.
3. **Corpus roundtrip** — for every `.iso` in `scripts/`, `build` it
   to `.nkit.iso`, `dump` back, assert byte-identity. Mirrors the REL
   corpus roundtrip we already have.
4. **Cross-implementation** — build a `.nkit.iso` from one of our
   ISOs, run it through NKit v1 on Windows, assert byte-identical
   restoration. Catches any case where our encoder picks a different
   (but still valid) gap encoding than the reference.

Corpus currently available in the repo: Colo US, XD US, plus whatever
Wii ISOs the user has locally. For `.nkit.iso` samples, we need at
least one GC and one Wii — either created with NKit v1 or pulled from
preservation trackers.

## Open questions before Phase 1

1. **Partition table restore on Wii** — NKit rewrites `0x40000`
   entries with new offsets. The original offsets are recoverable
   from the partition headers themselves (each partition has its own
   header block with its absolute position). But we should verify
   this by round-tripping a Wii sample before committing to the
   approach.
2. **Junk-override ID semantics (0x214)** — empirically GC NKit leaves
   this empty when Game ID seeds correctly. Are there known games
   where the override is non-zero? Need a Redump dataset sample to
   check.
3. **Gap alignment** — the NKit source requires gap length `% 4 == 0`.
   Are there games where files land on non-aligned offsets and
   NKit silently pads? Look for any pad-byte writing in the encoder.
4. **CRC-force slot** — ~~confirm it's exactly offset `0x20C`~~
   **Answered.** CRC-32 of the whole real `XD (US).nkit.iso` equals the
   CRC stored at `0x208`, so the slot is `0x20C` and the convention is
   the one `CRCForce` implements.

## Next move

GameCube is closed out. The remaining work is **Wii** (Phases 6-8),
which needs a Wii `.nkit.iso` sample and the partition re-hashing and
re-encryption that `WiiCrypto` already has the primitives for. Until
then both operations refuse a Wii image by name.
