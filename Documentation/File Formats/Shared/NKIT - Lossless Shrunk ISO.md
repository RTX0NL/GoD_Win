# NKIT - Lossless Shrunk ISO

NKit (by Nanook) is a non-lossy, non-cryptographic shrink format for
GameCube and Wii disc images. A `.nkit.iso` is a regular ISO in shape
(same sector size, readable by Dolphin, Swiss, Nintendont) but with junk
data removed, gaps between files squeezed, and — for Wii — the
partition's per-block hashes and AES encryption stripped. The original
`.iso` can be reconstructed byte-for-byte from a `.nkit.iso` plus a
matching junk-PRNG seed.

NKit is **not** a container. It reuses the GameCube/Wii disc layout and
just swaps blocks of junk/encrypted data for compact representations
that a restore pass can expand back in place. Size savings are typically
large (GC .iso 1.4 GB → .nkit.iso ~30-200 MB; dual-layer Wii 8.5 GB →
~1-5 GB depending on content).

## Identification

| Property | Value |
|----------|-------|
| Extension | `.nkit.iso` (also `.nkit.gcz` when wrapped in Dolphin's GCZ) |
| Byte order | Big-endian (same as original disc) |
| Magic | ASCII `NKIT` at file offset `0x200` |
| File signature | First 4 bytes remain the original 4-byte Game ID |

Detection: read 4 bytes at `0x200`. If they're `0x4E 0x4B 0x49 0x54`
("NKIT"), the file is an NKit image.

## Relation to the Original Disc Header

The 0x00-0x1FF disc header is preserved from the original, with these
modifications:

| Offset | Size | Original | NKit value | Meaning |
|--------|------|----------|------------|---------|
| 0x60   | 1    | `0x00`   | `0x01`     | Wii only. "Hashes removed" flag (devkit/Dolphin-compatible) |
| 0x61   | 1    | `0x00`   | `0x01`     | Wii only. "Encryption removed" flag |
| 0x2BC  | 4    | Original partition size | Compacted size | Wii only. Length of the (now decrypted, hash-stripped) partition data. Used by the loader to know where the next partition starts. |

The Wii disc header's partition table at `0x40000` is rewritten: each
partition's `disc offset / 4` is updated to point at the new, smaller
partition layout.

Everything else in the first 0x200 bytes — Game ID, maker code, disc
number, version, title, debug monitor size/offsets, DOL offset, FST
offset, FST size, max FST size — is unchanged from the original.

## The NKit Header Block (0x200-)

Confirmed from Nanook's NKit v1 source
(`NKit/Conversion/Writers/NkitWriterGc.cs` and
`NkitWriterWii.cs`). The header block is ASCII-first, everything
big-endian, same for GC and Wii:

| Offset | Size | Type | Field | GC | Wii | Meaning |
|--------|------|------|-------|-----|-----|---------|
| 0x200 | 8 | ASCII | Magic + version | ✓ | ✓ | `"NKIT v01"` literal |
| 0x208 | 4 | UInt32 | Original CRC | ✓ | ✓ | CRC32 of the reconstructed source image (the original ISO) |
| 0x20C | 4 | UInt32 | CRC-force value | ✓ | ✓ | Filler value picked so `CRC32(.nkit.iso) == CRC32(original)` — lets a disc-ID hash match Redump without restoring first |
| 0x210 | 4 | UInt32 | Image size | ✓ | ✓ | GC: `originalByteSize`. Wii: `originalByteSize / 4` (fits 8.5 GB in 32 bits) |
| 0x214 | 4 | ASCII | Junk override ID | ✓ | — | 4-byte Game ID used to seed the junk PRNG. All-zero when the current Game ID already seeds it correctly |
| 0x218 | 4 | UInt32 | Update-partition CRC | — | ✓ | If the Wii update partition was removed, its CRC32 (so restore can detect if a known-good update is available to splice back in) |

Everything from `0x21C` to the end of the first sector is zero-padded.

The block is short (24-28 bytes of actual fields). No flags byte lives
here — "encryption removed" and "hashes removed" for Wii are expressed
instead via `0x60`/`0x61` in the original disc header (see below), and
"update partition removed" is implicit in whether `0x218` is non-zero.

## Junk / Gap Encoding

Real GameCube/Wii discs fill space between files with a deterministic
pseudorandom junk stream (Nintendo's disc padding PRNG, keyed off the
Game ID). NKit removes those runs and replaces them with markers that
tell the restore pass "regenerate N bytes of junk starting at PRNG
position P".

### Gap layout

- Gaps sit between files on the reconstructed filesystem
- Gaps are 4-byte aligned; length must be a multiple of 4
- Mixed-content gaps (partly junk, partly scrubbed or real) are
  processed in 256-byte (`0x100`) blocks

### Gap headers

Each gap starts with a 32-bit header whose low 2 bits are a type
sentinel:

| Bits 0..1 | Type | Meaning |
|-----------|------|---------|
| `0b00` | AllJunk | Entire gap is pure junk; expand via PRNG |
| `0b01` | AllScrubbed | Entire gap is zero-filled (scrubbed) |
| `0b10` | Mixed | Gap contains a sequence of 0x100-byte block entries |
| `0b11` | JunkFile | Gap represents a removed "junk file" with its own stream offset |

The upper 30 bits hold the gap length. When the length is
≥ `0xFFFFFFFC`, two consecutive 4-byte headers are used.

### Mixed-gap block entries

For `Mixed` gaps, the body is a run of 32-bit values. Each value's top
2 bits select a block kind; the remaining 30 bits are the count (in
0x100 blocks):

| Bits 30..31 | Kind | Payload |
|-------------|------|---------|
| `0b00` | Junk | Regenerate N × 0x100 bytes from PRNG |
| `0b01` | NonJunk | N × 0x100 bytes of literal data follow inline |
| `0b10` | ByteFill | Low byte of the header is the fill; emit N × 0x100 copies |
| `0b11` | Repeat | Repeat the previous NonJunk block N times |

Counts max out at `0x3FFF_FFFF` for standard kinds, `0x3F_FFFF` for
ByteFill (since 8 bits are consumed by the fill byte).

### Nintendo junk PRNG

The PRNG that produced the original disc padding is keyed off the
**4-byte Game ID + disc number + block index**. Each `0x40000`-byte
block is generated from scratch from the seed — no cross-block state —
so it's fully seekable (O(block) to jump to any position).

**Seed derivation** (per `NKit/FilesAndStreams/JunkStream.cs`):

```
sample = ((id[2] << 8 | id[1]) << 16) | ((id[3] + id[2]) << 8) | (id[0] + id[1])
sample = ((sample ^ disc) * 0x260BCD5) ^ blockIndex
```

Where `id[0..3]` is the 4-byte Game ID string, `disc` is the disc
number (disc header offset 0x06), and `blockIndex = position / 0x40000`.

**State init** (17 × `UInt32`, LFSR-style):

```
for i in 0..16:
    for j in 0..31:
        sample *= 0x5D588B65
        num = (num >> 1) | ((sample + 1) & 0x80000000)
    state[i] = num
```

**State expansion** (to 521 × `UInt32`):

```
state[0x10] ^= (state[0] >> 9) ^ (state[0x10] << 23)
for k in 1..504:
    state[k + 16] = ((state[k - 1] << 23) ^ (state[k] >> 9)) ^ state[k + 15]
```

**Mixing** (applied 3 times):

```
for k in 0..31:
    state[k] ^= state[k + 0x1E9]
for k in 32..520:
    state[k] ^= state[k - 32]
```

**Byte extraction** (4 bytes per state word — note the odd `>> 0x12`
for byte index 1; this is the confirmed extraction, even though it's
not the uniform `>> 16`):

```
out[4i+0] = byte(state[i] >> 24)
out[4i+1] = byte(state[i] >> 18)
out[4i+2] = byte(state[i] >> 8)
out[4i+3] = byte(state[i])
```

**Length**: the junk stream length is `align(discSize, 0x8000)`; bytes
past `discSize` are zero-padded.

Key constants:

| Constant | Value | Role |
|----------|-------|------|
| ID mixer | `0x260BCD5` | Seed derivation multiply |
| Sample LCG | `0x5D588B65` | Per-bit state init multiply |
| Block size | `0x40000` | 256 KB — state is re-seeded per block |
| Align unit | `0x8000` | 32 KB sector boundary |

Reference Swift-side target: `Sources/Shared/Core/Engines/Dolphin/Junk/JunkStream.swift` with constructor `(id: [UInt8], disc: UInt8, length: UInt64)` and a seekable `position` / `read(count:)` API. Pure integer arithmetic, no external deps.

## Wii Partition Handling

For Wii images, each partition undergoes extra transformation:

**In a normal Wii ISO** (see `../Wii ISO Encryption Spec` notes in
CLAUDE.md): every 0x8000-byte data group is AES-CBC encrypted, with the
first 0x400 bytes being the per-group hash metadata (H0/H1/H2).

**In a Wii NKit ISO** each partition's data area is stored **decrypted
and with the 0x400-byte hash blocks removed**. So a group is just
`0x7C00` bytes of plaintext data. The `0x60`/`0x61` flags signal this
to readers. The `0x2BC` partition-length field holds the new (smaller)
partition size so the disc header's partition table stays coherent.

Reconstruction:
1. For each 0x8000-byte original group, take the 0x7C00 stored bytes.
2. Recompute H0 / H1 / H2 hashes and write the 0x400 hash block.
3. AES-CBC encrypt using the partition's title key and the per-group
   IV derivation (see the Wii spec).
4. Re-sign the ticket (fakesign) if the partition was modified.

The update partition on Wii discs is typically removed entirely by NKit
(it's duplicated across many games and not needed for gameplay). A
separate flag in the NKit header records whether it was removed.

## Reconstruction Algorithm

At a high level, restoring `.nkit.iso` → `.iso`:

1. Read the NKit header at `0x200`, confirm magic, note flags, CRC/MD5,
   version.
2. Clear bytes `0x60`/`0x61` back to `0x00` (Wii). Restore the original
   `0x2BC` partition length.
3. Clear the NKit header block back to original disc-header bytes if
   the game had data there; many games leave `0x200-0x3FF` as junk.
4. Walk the filesystem (FST) to enumerate real files in their declared
   on-disc order.
5. For each gap between files, consume the gap header/body and write
   either regenerated junk (via the PRNG), zero fill, byte fill, or
   inline NonJunk data.
6. For Wii images, reverse the partition transform: for each stored
   0x7C00 block, recompute hashes and re-encrypt into 0x8000 groups.
7. (Optional) recompute and verify the CRC/MD5 against the header.

## Shrinking Algorithm (ISO → NKit)

Essentially the inverse:

1. Parse the original disc header, FST, partition table.
2. Walk the junk PRNG alongside the on-disc junk regions; anywhere the
   disc bytes match the PRNG stream, replace the run with an `AllJunk`
   gap marker.
3. Detect runs of zeros (scrubbed), byte-fill runs, and repeats; emit
   those as mixed-gap block entries.
4. For Wii: decrypt each partition group, drop the 0x400 hash block,
   store the 0x7C00 data payload. Update `0x2BC`, set `0x60`/`0x61` to
   `0x01`, rewrite the partition table.
5. Write the NKit header at `0x200` with flags, CRC/MD5, PRNG seed/
   offset pointers.
6. Ensure the result is still a valid ISO shape (sectors aligned,
   loaders can boot directly from it).

## Current Tooling Landscape

- Nanook's **NKit v1** (C# / .NET) — canonical implementation, Windows-
  focused. Source: https://github.com/Nanook/NKitv1.
- **NKit v2** (C# / .NET 6+) — cross-platform rewrite, but still Windows
  binaries are the primary distribution.
- **Dolphin**, **Swiss**, **Nintendont** — read `.nkit.iso` directly
  (the `0x60`/`0x61` flags + `NKIT` magic tell them to bypass
  decryption / regenerate hashes in memory).

There is no Swift or Apple-native implementation; adding one to
`GODDESS` fills a real gap (no pun intended).

## References

- [NKit wiki (GBAtemp)](https://wiki.gbatemp.net/wiki/NKit) — overview
- [NKit/NKitFormat (GBAtemp)](https://wiki.gbatemp.net/wiki/NKit/NKitFormat) — format page
- [Nanook/NKitv1 source](https://github.com/Nanook/NKitv1) — reference implementation (C#)
- [Nanook/NKit (v2)](https://github.com/Nanook/NKit) — current version
- [Wii disc image formats explainer](https://cadence.moe/blog/2022-05-24-explanation-of-wii-disc-image-formats)
- [file magic patch](https://mailman.astron.com/pipermail/file/2020-April/000318.html) — confirms `NKIT` magic at `0x200`
