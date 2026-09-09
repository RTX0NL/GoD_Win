# WBFS - Wii Backup File System

WBFS is the container USB loaders (and wit, `wbfs_file`) store Wii discs in.
It is a tiny filesystem rather than a compression format: a header naming
the sector geometry, a table of up to 500 disc slots, and for each disc a
copy of its header plus a **block map** that sends every block of the
logical single-layer image to a block in the file, or to nothing. Blocks a
disc never used are simply absent and read back as zero. The disc data is
stored verbatim — still encrypted, exactly as on the disc.

GoD-Tool reads WBFS. Setup accepts a `.wbfs` at the same entry point as a
raw `.iso`; the restored image is a `GoDReadable` view resolved through the
block map on every read (`WBFSDiscImage`), so nothing is unpacked up front
and the copy into the project streams. Writing WBFS is not implemented.

## Identification

| Property | Value |
|----------|-------|
| Extension | `.wbfs` (a split image continues in `.wbf1`, `.wbf2`, …, not supported) |
| Magic | ASCII `"WBFS"` at offset 0x00 |
| Byte order | **Big-endian** |
| Disc size | Always single-layer: 143 432 × 0x8000 = `0x1_1824_0000` (4 699 979 776) bytes |

## Header

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | ASCII | Magic | `"WBFS"` |
| 0x04 | 4 | u32 | `n_hd_sec` | hd sectors the container spans |
| 0x08 | 1 | u8 | `hd_sec_sz_s` | log2 of the hd sector size; 9 (512 bytes) in practice |
| 0x09 | 1 | u8 | `wbfs_sec_sz_s` | log2 of the WBFS block size; 21 (2 MiB) in practice |
| 0x0A | 2 | — | Padding | |
| 0x0C | 500 | u8[] | Disc table | One byte per slot; non-zero = in use |

Derived (libwbfs names):

```
hd_sec_sz            = 1 << hd_sec_sz_s
wbfs_sec_sz          = 1 << wbfs_sec_sz_s
n_wbfs_sec           = n_hd_sec >> (wbfs_sec_sz_s - hd_sec_sz_s)   # blocks in the container
n_wbfs_sec_per_disc  = 143432 >> (wbfs_sec_sz_s - 15)               # entries per block map
disc_info_sz         = align(0x100 + 2 * n_wbfs_sec_per_disc, hd_sec_sz)
```

`n_wbfs_sec_per_disc` is a floor division — with 2 MiB blocks it is 2241,
covering 4 699 717 632 bytes. The last 256 KiB of the disc is never stored
and restores as zero.

## Disc records

Disc slot `i`'s record starts at `hd_sec_sz + i * disc_info_sz`:

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0x000 | 0x100 | Disc header | A copy of the image's first 0x100 bytes: game ID, disc number, title. wit overwrites 0xEC–0xFF with an ASCII `MD5#` tag followed by a 16-byte digest, so the copy is not byte-identical to the image in wit-written containers |
| 0x100 | 2 × `n_wbfs_sec_per_disc` | `wlba` | Block map, u16 BE per disc block: the WBFS block holding it, or 0 for none |

Block 0 of the container is the header block (this header, the disc
records, and libwbfs's free-block bitmap at its tail), so a `wlba` entry is
never 0 for stored data. The bytes for disc offset `x` are at:

```
file_offset = (wlba[x >> wbfs_sec_sz_s] << wbfs_sec_sz_s) + (x & (wbfs_sec_sz - 1))
```

## Measured

`Rhythm Heaven Fever [SOME01].wbfs`, 463 470 592 bytes: 512-byte hd
sectors, 2 MiB blocks, one disc in slot 0, 220 of 2241 blocks allocated
(indices 1–220, all distinct), `n_hd_sec × hd_sec_sz` equal to the file
size exactly, disc block 0 mapped to container block 1, and the record's
header copy carrying wit's `MD5#` tag at 0xEC.
