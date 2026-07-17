# CISO - Compact ISO (GameCube / Wii variant)

CISO ("compact ISO", a.k.a. "Wiimms CISO") is a minimal space-saving
format that omits zero-filled regions of a disc image. It has no
compression, no checksums, and no metadata beyond a fixed-size header
and a per-block presence bitmap. Dolphin, Swiss, and Nintendon't all
read it directly.

CISO shares its name (and magic bytes) with the PSP "CSO" format, but
the two are **incompatible**. PSP CSO stores per-block offsets and
uses zlib compression; GC/Wii CISO stores a 1/0 presence bitmap and
never compresses. Distinguish by the block-size field at offset 0x04
(see below): `0x00200000` (2 MiB) is the GC/Wii variant; `0x800`
(2 KiB) is PSP.

## Identification

| Property | Value |
|----------|-------|
| Extension | `.ciso` (or `.cso` — same format, different filename convention) |
| Magic | ASCII `"CISO"` at offset 0x00 |
| Byte order | **Little-endian** (the only little-endian field in the file) |
| Header size | `0x8000` (32 KiB) |
| GC discriminator | `0xC2339F3D` at file offset `0x801C` (original disc's GC magic, shifted by the header) |
| Wii discriminator | `0x5D1C9EA3` at file offset `0x8018` (original disc's Wii magic, shifted by the header) |

## Header (32 KiB)

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x0000 | 4 | ASCII | Magic | Exactly `"CISO"` |
| 0x0004 | 4 | UInt32 LE | Block size | Fixed at `0x0020_0000` (2 MiB) for GC/Wii |
| 0x0008 | 32760 | UInt8[] | Block map | One byte per block; `0x01` = present, `0x00` = omitted |

The block map spans exactly `0x8000 - 0x0008 = 0x7FF8 = 32760 bytes`,
yielding a maximum disc size of `32760 × 2 MiB = 63.98 GiB`. More than
enough for any GC (1.4 GiB) or Wii (dual-layer 8.5 GiB) image.

## Body

Immediately after the header, at file offset `0x8000`, the body is a
simple concatenation of every **present** block in ascending index
order. Omitted blocks contribute nothing to the file.

For block `N` (0-indexed), its file offset is:

```
file_offset(N) =
    0x8000
  + 2 MiB × (count of map[0..N-1] that are == 1)
```

…if `map[N] == 1`; otherwise the block is logically `2 MiB` of `0x00`
and not stored anywhere.

To map back the other way — to find which disc offset a particular
file offset represents — scan the map, accumulating stored-block count
until the cursor hits `(file_offset - 0x8000) / 2 MiB`.

## Producing a CISO

```
for each 2 MiB block of the source ISO:
    if block is entirely 0x00:
        map[block_index] = 0
    else:
        map[block_index] = 1
        append the 2 MiB block to the output body
```

The writer doesn't need to know anything about disc structure —
it's purely a byte-level omit-zero pass.

## Restoring to ISO

```
for each block index N from 0 to (disc_size / 2 MiB - 1):
    if map[N] == 1:
        copy 2 MiB from the body stream
    else:
        write 2 MiB of 0x00
```

## Quirks worth knowing

- **No original size is stored.** The decoder has to either trust the
  game-header disc-size field (0x801C/0x8028 area), align to a known
  disc size (1.4 GiB GC, 4.7 GiB Wii SL, 8.5 GiB Wii DL), or require
  the caller to pass a target size. Most tools stop after the last
  present block — which strictly isn't round-trip-identical to a disc
  whose tail was zero-padded.
- **Blocks must be stored in ascending order** in the body. The
  format doesn't support reordering.
- **No network byte order.** The 4-byte block-size field is
  little-endian, so a big-endian reader must byte-swap it. Every
  other file format we handle is big-endian; this is the outlier.
- **Minimum block size is 32 KiB.** Any power of 2 between 32 KiB and
  2 MiB is technically valid per Wiimms' spec, but in practice every
  GC/Wii CISO in the wild uses 2 MiB.
- **No checksums, no versioning.** A corrupted CISO is
  indistinguishable from a valid one until you inspect the disc
  contents directly.
- **Blocks with a single non-zero byte defeat the compression.** A
  "junk" (PRNG) region in a GC disc won't compress at all, unlike
  NKit — CISO only removes pure-zero runs.

## Size comparison

CISO on a typical game is usually **larger** than NKit or RVZ because
GC/Wii discs contain very few pure-zero runs; most padding is Nintendo
junk PRNG output, not zeros. Expect savings of ~30-50% for Wii dual-
layer discs (where the second layer is often mostly unused), but
negligible savings on Wii single-layer or most GC games.

CISO's advantages:
- **No crypto, no decompression** — loaders can stream directly
- **Trivial implementation** — fits in ~100 lines of Swift
- **Broad support** — Swiss, Nintendon't, Dolphin, USBLoader all
  handle it

## References

- [Wiimms ISO Tools reference](https://wit.wiimm.de/info/iso-images.html)
- [libmagic GC/Wii CISO signature](https://github.com/file/file/blob/master/magic/Magdir/console)
- [Picori CISO docs](https://docs.rs/picori/latest/picori/ciso/index.html)
