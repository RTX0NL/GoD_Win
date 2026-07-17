# WIA / RVZ - Dolphin Disc Image Formats

WIA ("Wiimms ISO Archive") was introduced by Wiimms in 2011 as a
lossless, compressed disc image for GameCube and Wii, supporting PURGE
+ bzip2 + LZMA + LZMA2. RVZ is Dolphin's 2020 extension: same
underlying framework, plus Zstandard, smaller chunks, and a PRNG-
based "packing" pass that lets Nintendo junk data roundtrip without
having to actually store it.

Both share the same magic, header, and struct layout. The differences
are a few field semantics and which compression IDs are valid.

## Identification

| Property | Value |
|----------|-------|
| Extensions | `.wia`, `.rvz` |
| Magic | ASCII `"WIA\x01"` at offset `0x00` (both formats) |
| Byte order | **Big-endian** (unlike CISO) |
| Distinguish WIA vs RVZ | By `compression` field in `wia_disc_t`: RVZ uses `5` (Zstandard) and allows non-2-MiB chunk sizes; WIA forbids both |

Dolphin accepts either under either extension at read time; at write
time it chooses WIA for pre-v1.4 compatibility or RVZ for newer
features.

## File structure

```
┌───────────────────────────────────────────────────────────────────┐
│ 0x0000  wia_file_head_t          (0x48 bytes, fixed)              │
├───────────────────────────────────────────────────────────────────┤
│ 0x0048  wia_disc_t               (variable — see disc_size)       │
├───────────────────────────────────────────────────────────────────┤
│ ...     wia_part_t[n_part]       (partitions, uncompressed)       │
├───────────────────────────────────────────────────────────────────┤
│ ...     wia_raw_data_t[n_raw]    (raw-data descriptors, LZMA'd)   │
├───────────────────────────────────────────────────────────────────┤
│ ...     wia_group_t[n_groups]    (group table, compressed)        │
├───────────────────────────────────────────────────────────────────┤
│ ...     group payloads           (one blob per group, compressed) │
└───────────────────────────────────────────────────────────────────┘
```

The three tables (partitions, raw data, groups) live at offsets
recorded inside `wia_disc_t`; they aren't necessarily adjacent.

## `wia_file_head_t` (0x48 bytes, big-endian)

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | char[4] | magic | Always `"WIA\x01"` (even for RVZ) |
| 0x04 | 4 | UInt32 | version | Writer's format version |
| 0x08 | 4 | UInt32 | version_compatible | Minimum version required to read |
| 0x0C | 4 | UInt32 | disc_size | Byte size of the `wia_disc_t` that follows |
| 0x10 | 20 | SHA-1 | disc_hash | SHA-1 over the `wia_disc_t` bytes |
| 0x24 | 8 | UInt64 | iso_file_size | Original uncompressed disc size |
| 0x2C | 8 | UInt64 | wia_file_size | Size of this file on disk |
| 0x34 | 20 | SHA-1 | file_head_hash | SHA-1 over bytes `[0x00..0x34)` (i.e. this struct minus this field) |

## `wia_disc_t` (starts at 0x48)

| Field | Type | Size | Meaning |
|-------|------|------|---------|
| disc_type | UInt32 | 4 | `0` = unknown, `1` = GameCube, `2` = Wii |
| compression | UInt32 | 4 | See compression IDs below |
| compr_level | Int32 | 4 | Compressor-specific level (signed; Zstd can be negative) |
| chunk_size | UInt32 | 4 | Bytes per group; rules below |
| dhead | UInt8[0x80] | 128 | First 128 bytes of the original disc image, verbatim |
| n_part | UInt32 | 4 | Number of `wia_part_t` entries |
| part_t_size | UInt32 | 4 | On-disc size of each `wia_part_t` (for forward compat) |
| part_off | UInt64 | 8 | File offset of the partition table. Not compressed. |
| part_hash | SHA-1 | 20 | SHA-1 over the partition table |
| n_raw_data | UInt32 | 4 | Number of `wia_raw_data_t` entries |
| raw_data_off | UInt64 | 8 | File offset of the raw-data table (compressed) |
| raw_data_size | UInt32 | 4 | Compressed byte size of the raw-data table |
| n_groups | UInt32 | 4 | Number of `wia_group_t` entries |
| group_off | UInt64 | 8 | File offset of the group table (compressed) |
| group_size | UInt32 | 4 | Compressed byte size of the group table |
| compr_data_len | UInt8 | 1 | Used bytes in `compr_data` (0-7) |
| compr_data | UInt8[7] | 7 | Compressor-specific parameters (see below) |

### Compression IDs

| ID | Name | WIA | RVZ |
|----|------|:---:|:---:|
| 0 | None | ✓ | ✓ |
| 1 | PURGE (run-length-ish) | ✓ | — |
| 2 | bzip2 | ✓ | ✓ |
| 3 | LZMA (raw stream) | ✓ | ✓ |
| 4 | LZMA2 | ✓ | ✓ |
| 5 | Zstandard | — | ✓ |

### `compr_data` by compressor

- **None / bzip2**: unused, `compr_data_len = 0`
- **LZMA**: 5 bytes — byte 0 packs `(lc, pb, lp)`, bytes 1-4 are
  dictionary size little-endian
  ```
  lc = d % 9
  pb = (d / 9) / 5
  lp = (d / 9) % 5
  ```
- **LZMA2**: 1 byte `prop` — dictionary size is
  `(prop == 40) ? 0xFFFF_FFFF : (((2 | (prop & 1)) << (prop / 2 + 11)))`
- **Zstandard (RVZ)**: 0 bytes; `compr_level` is used directly (may
  be negative for Zstd's fast modes)

### Chunk size rules

- **WIA**: must be a non-zero multiple of `2 MiB` (0x20_0000)
- **RVZ**: must be ≥ 32 KiB (0x8000) and a power of 2 if < 2 MiB,
  otherwise a multiple of 2 MiB

## `wia_part_t` (per-partition, Wii only)

Partitions are stored **uncompressed** (the table itself; the data
goes through the group system).

| Field | Type | Size | Notes |
|-------|------|------|-------|
| part_key | UInt8[16] | 16 | AES-128 title key (already decrypted from the ticket's common-key encryption), so the tool doesn't need the Wii common key at read time |
| pd[0] | `wia_part_data_t` | 16 | Management segment (first ~0x18000 bytes of the partition — tickets, TMD, certs) |
| pd[1] | `wia_part_data_t` | 16 | Bulk data segment (the rest of the partition) |

### `wia_part_data_t` (16 bytes)

| Field | Type | Size | Notes |
|-------|------|------|-------|
| first_sector | UInt32 | 4 | Starting Wii sector (1 sector = 32 KiB) |
| n_sectors | UInt32 | 4 | Number of Wii sectors covered |
| group_index | UInt32 | 4 | Index of the first group containing this segment |
| n_groups | UInt32 | 4 | Number of consecutive groups |

GameCube images have `n_part = 0`; GC data lives entirely in
`wia_raw_data_t` entries.

## `wia_raw_data_t`

Covers everything outside Wii partitions (GC data, Wii disc header,
update partition, filler between partitions).

| Field | Type | Size |
|-------|------|------|
| raw_data_off | UInt64 | 8 |
| raw_data_size | UInt64 | 8 |
| group_index | UInt32 | 4 |
| n_groups | UInt32 | 4 |

The raw-data table itself is LZMA-compressed (with the same settings
as the rest of the file), starting at `raw_data_off` in the file.

## Groups

The group table is **n_groups** consecutive records, compressed en
bloc.

### `wia_group_t` (WIA — 8 bytes)

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | UInt32 | data_off4 | File offset of the group payload, divided by 4 |
| 0x04 | 4 | UInt32 | data_size | Compressed payload byte size. `0` = group is all zeros, nothing stored |

### `rvz_group_t` (RVZ — 12 bytes)

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | UInt32 | data_off4 | As above |
| 0x04 | 4 | UInt32 | data_size_flag | Bit 31 = "compressed" flag; bits 0-30 = payload byte size. If bit 31 is clear, payload is raw (bypassed the compressor) |
| 0x08 | 4 | UInt32 | rvz_packed_size | Post-packing, pre-compression byte size (non-zero iff the group went through the RVZ packing pass) |

### Reading a group

```
read ((data_off4 as UInt64) * 4) for (data_size) bytes
if RVZ and bit 31 of data_size_flag is 0:
    → payload is raw; skip decompression
else:
    decompress with the file's compression method
if rvz_packed_size > 0:
    decode the RVZ packing scheme (see below)
if this group covers a Wii partition:
    apply the exception list to fix up per-block hashes (see below)
```

An all-zero group (WIA `data_size == 0`, RVZ `data_size_flag == 0`)
expands to `chunk_size` bytes of zeros with no IO.

## Wii partition data layout inside a group

For Wii partition groups, the stored data is the **decrypted payload
with hash blocks stripped**, just like NKit does: each 0x8000 sector
becomes 0x7C00 bytes of plaintext data. A chunk covering N sectors
therefore holds `N × 0x7C00` bytes (not `N × 0x8000`).

When restoring, the reader:
1. Splits the stored data into 0x7C00 segments
2. Recomputes H0/H1/H2 hashes for each 0x8000 group
3. Applies exceptions from the group's exception list (these override
   recomputed hashes when the original image has unusual/corrupt
   hashes worth preserving)
4. Re-encrypts with the partition's title key

## Exception list (`wia_except_list_t`)

Prefixed to each Wii partition group's compressed payload:

```
UInt16                n_exceptions;
wia_exception_t[]     exceptions;
```

Each `wia_exception_t` is 22 bytes:

```
UInt16                offset;        // hash index within the chunk
UInt8[20]             hash;          // SHA-1 replacement
```

The `offset` is a non-linear mapping into the chunk's hash region;
Dolphin caps it at 3328 exceptions per list (the max number of hashes
in a 2 MiB Wii chunk).

## RVZ packing scheme

The key RVZ innovation: Nintendo junk data (from the disc PRNG) is
stored as "regenerate N bytes from this seed" rather than the actual
bytes. This compresses junk down to ~68 bytes of seed regardless of
run length.

### Encoding

Each packed stream is a sequence of segments:

```
repeat until end-of-stream:
    size = read_u32_be()
    if (size & 0x8000_0000) == 0:
        // Literal segment: output the next `size` bytes verbatim
        output(read_bytes(size))
    else:
        size &= 0x7FFF_FFFF
        seed = read_bytes(0x44)        // 68 bytes of PRNG seed state
        output(generate_prng(seed, size))
```

### Junk PRNG

A **Lagged Fibonacci Generator**, not the same PRNG as NKit's junk
stream:

- Parameters: `f = xor`, `j = 32`, `k = 521`
- State: 521 × UInt32 ring buffer
- 4 warm-up cycles (iterate the recurrence 4 × 521 times before
  output)
- Then one cycle produces 521 words (2084 bytes)

The 68-byte seed is: first 17 state words initialised directly, rest
derived by XOR recurrence (effectively the same expansion NKit uses,
but with different seed source).

### Note

The RVZ packing pass runs **before** compression on write; so a
reader decompresses first, then decodes the packing. Packed regions
may span into the middle of a group — the packing stream is
self-delimiting via the size fields.

## Hash verification at read time

| What | Where | Covers |
|------|-------|--------|
| `file_head_hash` | `wia_file_head_t` @ 0x34 | Bytes `[0x00..0x34)` of the file |
| `disc_hash` | `wia_file_head_t` @ 0x10 | The `wia_disc_t` bytes (size = `disc_size`) |
| `part_hash` | `wia_disc_t` | All partition-table bytes |

The group table and group payloads are *not* independently hashed;
their integrity is implied by the underlying compressor's integrity
check (bzip2 CRC / LZMA2 stream marker / Zstd frame checksum) and by
post-decompression per-block Wii hashes.

## Size comparison

Typical results for a Wii dual-layer disc:

| Format | Typical size (8.5 GB source) | Lossless? | Loader support |
|--------|------------------------------|-----------|----------------|
| ISO | 8.5 GB | - | universal |
| CISO | 4-6 GB | ✓ | Swiss/Nintendont/Dolphin |
| NKit | 1-5 GB | ✓ | Dolphin/Swiss/Nintendont |
| WIA (LZMA) | 1-2 GB | ✓ | Dolphin only |
| RVZ (Zstd, 128 KiB chunks) | 1-2 GB, fast decode | ✓ | Dolphin only |

RVZ's main win over WIA is decompression speed (Zstd is ~5× faster
than LZMA) with comparable compression ratio. Its main win over NKit
is that it's Dolphin's native format and produces better compression
on Wii discs (the per-group compression catches patterns NKit's gap-
level approach misses).

## References

- [Dolphin WIA/RVZ spec](https://github.com/dolphin-emu/dolphin/blob/master/docs/WiaAndRvz.md)
  — canonical, authoritative
- [Dolphin PR #8538](https://github.com/dolphin-emu/dolphin/pull/8538) —
  original WIA/RVZ implementation in Dolphin
- [Wiimms WIA docs](https://wit.wiimm.de/info/wia.html) — original
  WIA reference (WIA portion only, pre-RVZ)
- [RVZ Rust crate](https://lib.rs/crates/rvz) — third-party reader
  reference
