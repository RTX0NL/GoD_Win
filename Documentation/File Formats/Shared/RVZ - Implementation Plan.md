# WIA / RVZ - Implementation Plan

Swift-native encoder + decoder for Dolphin's WIA and RVZ disc image
formats, integrated as two new `GODDESS` operations:

- `rvzDump` — `.wia` / `.rvz` → `.iso`
- `rvzBuild` — `.iso` → `.rvz` (we'll default to RVZ/Zstd for new files)

Paired with the format reference at
[`RVZ - Dolphin Disc Image.md`](./RVZ%20-%20Dolphin%20Disc%20Image.md).

## Goals

- **Byte-identical roundtrip** on every test disc.
- **Read both WIA and RVZ**; write RVZ/Zstd by default (fast decode,
  Dolphin-preferred).
- **Pure Swift** for the format / framing / PRNG layers; compression
  codecs are the one place we allow vetted C deps (zstd, bzip2, LZMA).
- Share the Wii crypto primitives (AES-128-CBC + SHA-1 + hash chain)
  with the NKit implementation — build them **once**, use in both.

## Non-goals

- **Writing WIA**. We only read legacy WIA, write RVZ. Dolphin itself
  only writes RVZ in recent versions.
- **PURGE compression** (WIA compression ID 1). Legacy; rarely used;
  we reject WIAs that use it with a clear error message.
- **Progressive re-compression**. No "change a chunk in place"; any
  edit is a full rewrite.

## Module layout

```
Sources/Shared/
├── Core/Engines/Dolphin/
│   └── File Formats/
│       ├── WIAHeader.swift              # wia_file_head_t, wia_disc_t
│       ├── WIAPartition.swift           # wia_part_t, wia_part_data_t
│       ├── WIARawData.swift             # wia_raw_data_t
│       ├── WIAGroupTable.swift          # wia_group_t, rvz_group_t
│       ├── WIAExceptionList.swift       # wia_except_list_t
│       ├── RVZPacking.swift             # junk-compression encode/decode
│       └── RVZImage.swift               # whole-file semantic model
├── Core/Engines/Wii/Crypto/             # shared with NKit
│   ├── AES128CBC.swift
│   ├── SHA1.swift
│   └── WiiPartitionCodec.swift
└── Dependencies/Compression/            # new module
    ├── Zstd.swift                       # thin Swift wrapper around libzstd
    ├── LZMA.swift                       # thin wrapper around xz-utils
    └── BZip2.swift                      # thin wrapper around libbz2

Sources/Products/GODSDK/Operations/Dolphin/
├── RVZDumpConfig.swift
├── RVZDumpOperation.swift
├── RVZBuildConfig.swift
└── RVZBuildOperation.swift
```

## Data types

### `WIAFileHeader`

Maps exactly onto `wia_file_head_t`. Codable via the same `HexInt`
pattern as RELFile (SHA-1 hashes as hex strings, offsets as hex,
sizes as decimal).

### `WIADisc`

```swift
public struct WIADisc: Equatable {
    public enum DiscType: UInt32, Codable { case unknown = 0, gamecube = 1, wii = 2 }
    public enum Compression: UInt32, Codable {
        case none = 0, purge = 1, bzip2 = 2, lzma = 3, lzma2 = 4, zstd = 5
    }
    public var discType: DiscType
    public var compression: Compression
    public var compressionLevel: Int32
    public var chunkSize: UInt32
    public var discHeader: [UInt8]         // 128 bytes — first 0x80 of original disc
    public var partitions: [WIAPartition]
    public var partitionTableOffset: UInt64
    public var partitionHash: SHA1
    public var rawData: [WIARawData]
    public var rawDataOffset: UInt64
    public var rawDataCompressedSize: UInt32
    public var groupCount: UInt32
    public var groupTableOffset: UInt64
    public var groupTableCompressedSize: UInt32
    public var compressionData: [UInt8]    // max 7 bytes; interpretation per `compression`
}
```

### `WIAGroupEntry`

```swift
public enum WIAGroupEntry: Equatable {
    case wia(dataOffset: UInt64, dataSize: UInt32)
    case rvz(dataOffset: UInt64, dataSize: UInt32, isCompressed: Bool, rvzPackedSize: UInt32)

    public var isAllZeros: Bool    // true when dataSize == 0
}
```

### `RVZImage`

The semantic whole:

```swift
public struct RVZImage {
    public var header: WIAFileHeader
    public var disc: WIADisc
    public var partitions: [WIAPartition]    // uncompressed, as stored
    public var rawData: [WIARawData]         // decoded from compressed table
    public var groups: [WIAGroupEntry]       // decoded from compressed table
    /// Random-access read over the logical ISO. Transparent to caller.
    public func read(at discOffset: UInt64, length: Int) throws -> Data
}
```

## Compression dependency

RVZ needs zstd, bzip2, LZMA. These are C libraries; pure-Swift reimp
is unreasonable (zstd alone is >10 KLOC). Plan:

- **Vendor** each via Swift Package Manager with a `system-library`
  target when the host provides one, falling back to bundled sources.
  macOS ships `libbz2` and `liblzma` system-wide; zstd isn't
  guaranteed but is trivially included as source.
- Wrap each in a thin Swift API: `Zstd.decompress(_:into:)`, etc.
- Keep the wrappers in `Sources/Shared/Dependencies/Compression/`
  so they're reusable for any future format (GCZ for instance).

## Algorithms

### `rvzDump` (restore)

```
1. Read wia_file_head_t, validate magic "WIA\1", check hashes.
2. Read wia_disc_t (size = disc_size), validate disc_hash.
3. Read partition table (uncompressed) at part_off.
4. Decompress raw-data table at raw_data_off.
5. Decompress group table at group_off.
6. Allocate output .iso of size iso_file_size.
7. Fill pattern:
     - Write first 0x80 bytes = disc.dhead.
     - Iterate wia_raw_data_t entries; for each, decompress its
       groups and write at raw_data_off.
     - Iterate wia_part_t entries; for each partition:
       - Walk pd[0] + pd[1] groups, decompress each
       - Decode RVZ packing if rvz_packed_size > 0
       - Split stored data into 0x7C00 segments
       - Read exception list; apply exceptions over recomputed hashes
       - Recompute H0/H1/H2 for each 0x8000 group
       - AES-CBC encrypt with part_key
       - Write at the partition's disc offset
8. Verify output size matches iso_file_size.
```

### `rvzBuild` (shrink)

```
1. Parse source .iso disc header + partition table.
2. Build wia_file_head_t skeleton (hash fields filled at end).
3. Build wia_disc_t with target compression (RVZ/Zstd, 128 KiB chunks).
4. For each Wii partition:
     - Decrypt + strip hashes → 0x7C00 payloads
     - Run RVZ packing pass → emit (literal | PRNG-seed) segments
     - Compress with Zstd
     - Record wia_group_t entries
5. For non-partition regions, same pipeline without the decrypt step
   (they're already plaintext on the source disc).
6. Compute partition hash, disc hash, file-head hash; write them.
7. Write layout:
     - file_head
     - disc_struct
     - partitions (uncompressed)
     - raw data (compressed)
     - group table (compressed)
     - group payloads (compressed)
```

### RVZ packing detection (encoder)

Scan each chunk for runs of junk matching the Nintendo PRNG. When a
run ≥ threshold is found, replace it with a `(size | 0x8000_0000)
+ 68-byte seed` marker; surrounding non-junk stays as literal
segments. The packing pass keeps total size constant or shrinks it;
we pick the shorter of `packed` vs `unpacked` per chunk.

The "68-byte seed" is the first 17 × UInt32 state words of the LFG
PRNG at the point of generation. Recovering it is non-trivial — the
encoder must either (a) run the LFG forward against the source bytes
to find a seeding position that matches, or (b) re-run the disc's
original junk-generation with the correct seed and detect when the
source matches the output. Dolphin's implementation uses (b) via its
built-in junk generator; we'll follow suit.

## Phases

### Phase 1 — Compression dependency scaffolding *(1 session)*

Vendor zstd + link libbz2/liblzma. Thin Swift wrappers, compress +
decompress roundtrip tests against known vectors.

**Done when**: `Zstd.compress`/`decompress`, `LZMA.decompress`,
`BZip2.decompress` all pass unit tests (writing LZMA isn't needed —
we write RVZ/Zstd).

### Phase 2 — `WIAFileHeader` + `WIADisc` parse *(1 session)*

Structs. No IO, no decompression. Hand-build bytes, parse, assert.

**Done when**: parse + serialise roundtrip holds for all discType /
compression combos.

### Phase 3 — Group table + exception list parse *(1 session)*

Decode the compressed group table (LZMA / Zstd). Decode exception
list framing.

**Done when**: given a known RVZ file and its group table bytes, we
can enumerate every group's location and size correctly.

### Phase 4 — RVZ packing codec *(1-2 sessions)*

Implement LFG PRNG + pack/unpack. Stand-alone; no disc knowledge.

**Done when**:
- `unpack(pack(literal)) == literal` for various sizes
- PRNG matches Dolphin's reference output for known seeds (pull
  vectors from Dolphin test suite)

### Phase 5 — Wii crypto primitives *(shared with NKit; 1-2 sessions)*

`AES128CBC`, `SHA1`, `WiiPartitionCodec`. See NKit implementation
plan — same deliverable.

### Phase 6 — `rvzDump` end-to-end *(2 sessions)*

Stitch it all: read RVZ → decompress → unpack → re-encrypt Wii → emit
ISO.

**Done when**: every `.rvz` in our corpus dumps byte-identically to
its source `.iso`.

### Phase 7 — `rvzBuild` end-to-end *(2 sessions)*

Reverse direction.

**Done when**:
- `rvzDump(rvzBuild(iso)) == iso` for every corpus ISO
- File's disc_hash, part_hash, file_head_hash all check out when
  Dolphin opens the output

### Phase 8 — Integration *(0.5 session)*

Project setup detects `.rvz` / `.wia`, chains `rvzDump`. Build path
optionally writes RVZ.

## Testing

- **Unit**: PRNG vectors, header parse/serialise, exception-list
  round-trip, compression wrappers against known vectors
- **Reference-vector**: a Dolphin-produced RVZ of a known ISO; parse
  every struct, compare each field against hand-extracted values
- **Corpus roundtrip**: every ISO in `scripts/` → build RVZ → dump
  back → byte-identity
- **Cross-implementation**: build an RVZ, open in Dolphin, run the
  game (visual check at least); or have Dolphin dump our RVZ to ISO
  and compare

## Open questions

1. **Compression deps** — do we vendor zstd's source (MIT, clean,
   ~10 KLOC of C) or insist on a system install? Lean vendored for
   portability.
2. **bzip2 + LZMA** — read-only for legacy WIAs. Acceptable to punt
   LZMA writing entirely since we never write it.
3. **RVZ packing opt-in** — RVZ spec allows omitting packing per
   chunk. For our encoder, should it always try packing, or only
   when the compression saving exceeds a threshold? Default: always
   try, pick smaller.
4. **Compression level default** — Zstd level `5` (balanced), `9`
   (Dolphin's default), or `19` (archival)? Start at `5` for build
   time, document the config override.
5. **Endian sanity** — WIA is big-endian but its compression data
   fields embed little-endian LZMA dictionary sizes. Gotcha — account
   for it in the LZMA wrapper.

## Starting work

RVZ is the heaviest of the three disc formats we're planning. The
smallest useful first step is **Phase 1** (compression scaffolding) —
unlocks RVZ, but also stands alone as reusable infrastructure for any
future compressed format we add.

If we're not ready to commit to vendoring compression libraries yet,
**Phase 4 (RVZ packing codec)** is self-contained: pure integer math
LFG, doesn't need any codec to work, and lets us exercise the trickiest
novel algorithm in RVZ independently of the rest.

## Dependencies on NKit plan

The Wii crypto phase (Phase 5 above, Phase 6 in the NKit plan) is
**shared**. Whichever format we ship first pays that cost; the other
inherits it. Recommend: build crypto as its own milestone between the
two plans, or do NKit first (simpler format overall) to amortise the
Wii work.

### Suggested combined order across both plans

1. **NKit Phase 1 (JunkStream)** — unblocks NKit
2. **NKit Phase 2 (GapRLE)** — unblocks NKit
3. **NKit Phase 3 (CRC32 + force)** — unblocks NKit
4. **NKit Phase 4 (GC NKit dump)** — NKit GC round-trip
5. **NKit Phase 5 (GC NKit build)** — NKit GC roundtrip complete
6. **CISO Phases 1-4** — fill in CISO in parallel; trivial
7. **Wii crypto primitives** (shared) — AES, SHA-1, WiiPartitionCodec
8. **NKit Phases 7-8** — Wii NKit roundtrip
9. **RVZ Phase 1 (compression)** — introduce Zstd / bzip2 / LZMA
10. **RVZ Phases 2-4** — headers, groups, RVZ packing
11. **RVZ Phases 6-7** — end-to-end
12. **Integration** — all three formats auto-detected in ProjectSetup
