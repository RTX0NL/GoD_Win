# FSYS - Archive Container

FSYS is the primary archive container format used by Genius Sonority in Pokemon Colosseum, Pokemon XD: Gale of Darkness, and Pokemon Battle Revolution. It bundles multiple game assets (models, textures, scripts, strings, audio, collision data) into a single file with optional LZSS compression per entry. FSYS archives are referenced by the Table of Contents (TOC) system, which maps group IDs to archive filenames on disc.

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x90` |
| Magic | `FSYS` (4 bytes, ASCII) |
| Extension | `.fsys` |
| Byte Order | Big-endian |

## FSYS Header

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | char[4] | Magic | Always `FSYS` |
| 0x04 | 4 | UInt32 | Unknown | |
| 0x08 | 4 | UInt32 | Group ID | Identifies this archive in the TOC |
| 0x0C | 4 | UInt32 | Entry count | Number of files in the archive |
| 0x10 | 4 | UInt32 | Unknown | |
| 0x14 | 4 | UInt32 | Unknown | |
| 0x18 | 4 | UInt32 | Unknown | |
| 0x1C | 4 | UInt32 | Unknown | |
| 0x20 | 4 | UInt32 | File size | Total size of the FSYS archive |
| 0x24 | 12 | - | Unknown | |
| 0x30 | 4 | UInt32 | Unknown | |
| 0x34 | 12 | - | Unknown | |
| 0x40 | 4 | UInt32 | Entry details pointer | Offset to the entry detail table |

## Entry Detail Table

Each entry describes one file contained in the archive. Entry size differs between games.

### Entry Size

| Game | Entry Size |
|------|-----------|
| Colosseum | 0x50 bytes |
| XD | 0x70 bytes |

### Entry Fields

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 2 | UInt16 | File identifier | Unique ID within the archive |
| 0x02 | 1 | UInt8 | File type ID | Identifies the format (e.g. 0x04 = DAT, 0x12 = GTX) |
| 0x03 | 1 | UInt8 | Flags | Compression and other flags |
| ... | ... | ... | ... | Remaining layout varies by game |
| varies | 4 | UInt32 | File offset | Absolute offset of file data within the FSYS |
| varies | 4 | UInt32 | Uncompressed size | Size of the file after decompression |
| varies | 4 | UInt32 | Compressed size | Size of the file as stored (equals uncompressed if not compressed) |
| varies | 4 | UInt32 | Filename offset | Pointer to null-terminated filename string |

## LZSS Compression

Files within FSYS archives may be individually LZSS-compressed. Compressed entries are identified by their magic bytes.

### LZSS Header

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | char[4] | Magic | `LZSS` |
| 0x04 | 4 | UInt32 | Uncompressed size | Size after decompression |
| 0x08 | 4 | UInt32 | Compressed size | Size of the compressed data (excluding header) |
| 0x0C | 4 | - | Padding | |

### LZSS Parameters

| Parameter | Symbol | Value | Description |
|-----------|--------|-------|-------------|
| Window bits | EI | 12 | Sliding window size = 2^12 = 4096 bytes |
| Length bits | EJ | 4 | Max match length = 2^4 + P = 18 bytes |
| Threshold | P | 2 | Minimum match length = 2 bytes |

The algorithm uses a 4096-byte sliding window with a lookahead buffer. Flag bytes indicate whether subsequent data is literal (1) or a back-reference (0). Back-references encode a 12-bit window offset and a 4-bit length (plus threshold of 2, giving a maximum match of 18 bytes).

## Known File Type IDs

These type IDs appear in entry details to identify the format of each contained file:

| Type ID | Format | Description |
|---------|--------|-------------|
| 0x02 | RDAT | Room model (DAT/HSD format) |
| 0x04 | DAT | Character model (DAT/HSD format) |
| 0x06 | CCD | Collision data |
| 0x0A | MSG | Message/string table |
| 0x0E | SCD | Script bytecode |
| 0x12 | GTX | Texture |
| 0x1C | REL | Relocatable module |
| 0x28 | ISD | Streamed audio data |
| 0x2A | ISH | Streamed audio header |

## Game-Specific Differences

- **Colosseum** uses 0x50-byte entry details with a more compact layout.
- **XD** uses 0x70-byte entry details with additional fields for extended metadata.
- **PBR** (Wii) also uses FSYS but may have further entry size differences.

The LZSS compression algorithm and parameters are identical across all three games.

## Runtime

FSYS archives are loaded by the GS file system layer at runtime. The TOC maps group IDs to disc filenames, and the FSYS loader parses the header, decompresses entries as needed, and provides file handles to the game engine.
