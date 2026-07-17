# CISO - Implementation Plan

Swift-native encoder + decoder for the GameCube/Wii CISO format,
integrated as two new `GODDESS` operations:

- `cisoDump` — `.ciso` → `.iso` (byte-identical original, assuming
  known target size)
- `cisoBuild` — `.iso` → `.ciso`

Paired with the format reference at
[`CISO - Compact ISO.md`](./CISO%20-%20Compact%20ISO.md).

## Goals

- **Byte-identical roundtrip** when the target disc size is known or
  derivable from the disc header.
- **Pure Swift**, no external deps. The format has no crypto and no
  compression — trivial to implement.
- **Cross-platform**. CISO is the simplest of the disc formats we'll
  support; it should be the reference example for the later, heavier
  formats (NKit, RVZ).

## Non-goals

- **PSP CSO** support. Same magic, different format (per-block zlib
  offsets). If we need PSP support later, it goes in a separate file.
- **Non-2 MiB block sizes**. The spec allows any power-of-2 from 32
  KiB to 2 MiB, but no GC/Wii CISO in the wild uses anything other
  than 2 MiB. Implementation reads any legal block size but only
  writes 2 MiB.
- **In-place conversion**. Read the whole source, write the whole
  destination. No streaming-over-itself trick.

## Module layout

```
Sources/Shared/Core/Engines/Dolphin/File Formats/
├── CISOFile.swift            # header + block-map parse/serialise
└── CISOImage.swift           # whole-file semantic model

Sources/Products/GODSDK/Operations/Dolphin/
├── CISODumpConfig.swift
├── CISODumpOperation.swift
├── CISOBuildConfig.swift
└── CISOBuildOperation.swift
```

No new shared primitives; the format needs nothing the existing
`GoDData` + `GoDFoundation` layer doesn't already provide.

## Data types

### `CISOFile`

```swift
public struct CISOFile: Equatable {
    public static let formatName = "ciso"
    public static let headerSize = 0x8000
    public static let defaultBlockSize: UInt32 = 0x0020_0000   // 2 MiB
    public static let magic: [UInt8] = [0x43, 0x49, 0x53, 0x4F] // "CISO"

    public var blockSize: UInt32          // always 2 MiB for GC/Wii in practice
    public var blockMap: [Bool]           // up to 32760 entries
    public var discSize: UInt64           // derived or caller-supplied

    public init(blockSize: UInt32, blockMap: [Bool], discSize: UInt64)
}
```

The block map is a `[Bool]` rather than `[UInt8]` at the API level
because "present/absent" is what it semantically is; the single-byte
on-disc encoding is an implementation detail of parse/serialise.

### `CISOImage`

A thin wrapper that composes the header with a block-accessor. Since
CISO content is just raw disc bytes (no decryption, no per-block
headers), the "semantic" model here is really just "an ISO with some
blocks omitted":

```swift
public struct CISOImage {
    public var ciso: CISOFile
    /// Returns the 2 MiB block at the given index. If the block is
    /// marked omitted in the map, returns 2 MiB of zeros.
    public func readBlock(_ index: Int) throws -> Data
    /// Random-access read within the logical ISO. Transparent to
    /// caller — they see a full ISO, we walk the map underneath.
    public func read(at discOffset: UInt64, length: Int) throws -> Data
}
```

## Algorithms

### `cisoDump` (restore to `.iso`)

```
1. Read 0x8000 header:
     - validate magic "CISO"
     - read block_size (little-endian u32)
     - read block map (32760 bytes → [Bool])
2. Determine target disc size:
     (a) explicit override from config, OR
     (b) inspect the first present block for the disc header's size
         field (GC: 0x400; Wii: derived from partition table), OR
     (c) fall back to "last set bit in map + 1 block"
3. For each block index 0..(discSize / blockSize - 1):
     if blockMap[i]:
         copy blockSize bytes from input body to output
     else:
         write blockSize zero bytes
4. Truncate or pad output to discSize.
5. (Optional) verify GC/Wii magic at expected offset in output.
```

### `cisoBuild` (shrink `.iso`)

```
1. Read source ISO in 2 MiB chunks.
2. For each chunk:
     if all bytes are 0x00:
         blockMap[i] = false
     else:
         blockMap[i] = true
         append chunk to pending body
3. Write output:
     - "CISO" + blockSize (little-endian) + 32760-byte map
     - concatenated body
```

No junk detection, no PRNG, no compression — pure zero-run elimination.

## Phases

### Phase 1 — `CISOFile` header parse/serialise *(0.5 session)*

Pure data type. Hand-build a header, serialise, parse back, assert
equality. No IO dependency.

**Done when**: roundtrip holds for block sizes 32 KiB → 2 MiB and
block maps ranging from all-zero to all-one to sparse patterns.

### Phase 2 — `cisoDump` *(0.5 session)*

Produce a byte-identical ISO from a CISO.

**Done when**: for every `.ciso` in the test corpus, the dumped ISO
matches the known-good reference ISO byte-for-byte. (Will need at
least one `.ciso` sample — user drops in or we build it via Swiss on
a real console / Wiimms wit on macOS.)

### Phase 3 — `cisoBuild` *(0.5 session)*

Produce a CISO from an ISO.

**Done when**:
- `cisoDump(cisoBuild(iso)) == iso` for every corpus ISO
- `cisoBuild(iso)` matches Wiimms `wit` output byte-for-byte on a
  reference sample

### Phase 4 — Integration *(0.5 session)*

- `ProjectSetup` auto-detects `.ciso` input, chains `cisoDump` before
  `gamecubeDump` / `wiiDump`
- Optional `cisoBuild` after a `gamecubeBuild` / `wiiBuild`

## Testing

- **Unit**: header parse/serialise roundtrip with various block maps
- **Reference-vector**: known good `.ciso` files with known ISO
  content — dump and verify
- **Corpus roundtrip**: same as for NKit / REL — take every ISO in
  `scripts/`, build a CISO, dump back, assert byte-identity
- **Cross-implementation**: build a CISO from a corpus ISO, run it
  through Wiimms `wit -t CISO` or Dolphin, confirm both produce the
  same decoded ISO

## Open questions before Phase 1

1. **Target size for `cisoDump`** — we need to decide whether to
   always pad/truncate to a canonical disc size (1.4 GiB GC, 4.7
   GiB / 8.5 GiB Wii) or to stop at the last present block. Most
   loaders accept either; for byte-identity roundtrip we'd want the
   canonical size. Canonical is the default; add an override flag.
2. **All-1 blocks** — some Wii discs have partition padding that's
   `0xFF` rather than `0x00`. Should we compress all-byte-fill runs
   in general? Answer: **no**, that would break roundtrip with Wiimms'
   implementation. Only omit pure-zero blocks.

## Starting work

Smallest possible piece: **Phase 1 (header)**. Pure struct. Writes a
32 KiB buffer with little-endian magic + size + map; reads it back.
Trivial unit test. Land in a single short session, then Phase 2 stacks
directly on it.
