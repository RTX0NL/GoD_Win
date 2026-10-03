# File Format Documentation

Format specifications for file types used in Pokemon Colosseum and Pokemon XD: Gale of Darkness.

## Shared Formats

These formats are used by both Colosseum and XD with the same or very similar structure.

### Archives & Compression
- [FSYS - Archive Container](Shared/FSYS%20-%20Archive%20Container.md) — Main game archive with LZSS compression (type `0x90`). The 16-byte `LZSS` header + stream a compressed entry holds is also a standalone format (`LZSSHeaderedCompressor`, `CompressionFormat.lzss`), reachable through the `compress` / `decompress` operations as `lzss`; the bare stream is `lzss-raw`
- [Yaz0/Yay0 - Nintendo LZ77 Compression](Shared/Yaz0%20Yay0%20-%20Nintendo%20LZ77%20Compression.md) — Nintendo's own codec. Not used by Colosseum/XD/PBR; support exists for general GameCube/Wii titles and as a prerequisite for RARC and U8. Exposed by the `compress` / `decompress` operations
- Zstandard — RFC 8878. Decode only, in `GoDFoundation/Data/Compression/Zstd/`; present because RVZ group payloads are Zstandard frames. Pure Swift, like the package's other algorithms. Not in `CompressionFormat` and not reachable from the `compress` / `decompress` operations, which promise a codec that runs both ways
- [Binary Patches - UPS, IPS, BPS, xdelta](Shared/Binary%20Patches%20-%20UPS%20IPS%20BPS%20xdelta.md) — the four patch formats, created and applied by the `createPatch` / `applyPatch` operations. Not game formats: they describe the difference between any two files
- [U8/NARC - Nintendo Archives](Shared/U8%20NARC%20-%20Nintendo%20Archives.md) — Nintendo's own containers, big and little endian, discriminated by the direction their magic is spelled. PBR ships both (`.arc`/`.narc`)

### Disc Images
- [CISO - Compact ISO](Shared/CISO%20-%20Compact%20ISO.md) — Zero-block-omitting GC/Wii image; read and written
- [NKIT - Lossless Shrunk ISO](Shared/NKIT%20-%20Lossless%20Shrunk%20ISO.md) — Junk-stripped image; GameCube trailing-truncation restore only
- [WBFS - Wii Backup File System](Shared/WBFS%20-%20Wii%20Backup%20File%20System.md) — Block-mapped Wii disc container; restored as a lazy view
- [RVZ - Dolphin Disc Image](Shared/RVZ%20-%20Dolphin%20Disc%20Image.md) — WIA/RVZ; restored to a raw ISO by `rvzDump` (Zstandard and uncompressed images; bzip2/LZMA/PURGE refused by name). Read only — GoD-Tool has no Zstandard encoder to write one with

### 3D Models
- [DAT - HAL Model Format](Shared/DAT%20-%20HAL%20Model%20Format.md) — Character/room 3D models, HSD format (type `0x04`/`0x02`)
- [DATS - Multi-Model Archive](Shared/DATS%20-%20Multi-Model%20Archive.md) — Multiple DAT models bundled (type `0x10`)
- [PKX - Battle Model](Shared/PKX%20-%20Battle%20Model.md) — DAT with battle metadata, animations, shiny filter (type `0x1E`)
- [WZX - Move Animation](Shared/WZX%20-%20Move%20Animation.md) — Move effect archive with models and particles (type `0x20`)

### Textures & Graphics
- [GTX/ATX - Texture Formats](Shared/GTX%20ATX%20-%20Texture%20Formats.md) — GameCube textures: 11 pixel formats, palette encoding, block layout, animated frames (type `0x12`/`0x32`)
- [GSW - Flash Menu Animation](Shared/GSW%20-%20Flash%20Menu%20Animation.md) — Proprietary Flash-like UI animation (type `0x30`)
- [GPT - Particle Effects](Shared/GPT%20-%20Particle%20Effects.md) — Particle system data (type `0x14`/`0x22`)

### Audio & Video
- [ISH/ISD - Streamed Audio](Shared/ISH%20ISD%20-%20Streamed%20Audio.md) — DSP ADPCM streamed music (type `0x2A`/`0x28`)
- [SAMP - Sequenced Music](Shared/SAMP%20-%20Sequenced%20Music.md) — MusyX sequenced audio (type `0x08`)
- [THP - Video Format](Shared/THP%20-%20Video%20Format.md) — Nintendo video, split THH+THD (type `0x2C`/`0x2E`)

### Scripting & Text
- [SCD - Script Bytecode](Shared/SCD%20-%20Script%20Bytecode.md) — Compiled script with 18 opcodes (type `0x0E`)
- [MSG - Message String Table](Shared/MSG%20-%20Message%20String%20Table.md) — Game text and dialog strings (type `0x0A`)
- [FNT - Font Data](Shared/FNT%20-%20Font%20Data.md) — Character glyph definitions (type `0x0C`)

### World & Collision
- [CCD - Collision Data](Shared/CCD%20-%20Collision%20Data.md) — 3D collision mesh with interaction regions (type `0x06`)
- [CAM - Camera Data](Shared/CAM%20-%20Camera%20Data.md) — Camera animation sequences (type `0x18`)
- [REL - Relocatable Module](Shared/REL%20-%20Relocatable%20Module.md) — Runtime-linked code and data tables (type `0x1C`)

### Save Files
- [GCI - GameCube Memory Card Save](Shared/GCI%20-%20GameCube%20Memory%20Card%20Save.md) — Single-save export: a 0x40 directory entry plus the file's blocks. The entry describes the banner, animated icon and comment strings generically for any GameCube title; the body past that is the game's own
- [XD Save Slot - From-Scratch Rebuild plan](XD/XD%20Save%20Slot%20-%20From-Scratch%20Rebuild%20Plan.md) — The one save region that still can't be rebuilt from its artifacts: what is derivable, what is inter-save filler, and how to close it

### Executable data
- [main.dol Data Tables](Shared/main.dol%20Data%20Tables.md) — The tables both games keep in the executable rather than in `common.rel`: XD's 13 and Colosseum's 15, with the per-region addresses and how each was located
- [Colosseum common.rel Tables](Colosseum/common.rel%20Tables.md) — Colosseum's 28 `common.rel` tables, their strides and where the PAL build widens a record
- [XD common.rel Tables](XD/common.rel%20Tables.md) — The XD `common.rel` tables typed from their readers and the legacy tool's declarations: Battle Bingo, Battle CDs, Miror B's radar, story checkpoints, the world map, sound tables and the Colosseum flag-table leftovers
- [pocket_menu.rel - Shop Tables](Shared/pocket_menu.rel%20-%20Shop%20Tables.md) — Both games' mart list, mart goods (item data ids, not Items rows) and shop dialogue tables
- [Map REL - Floor Tables](Shared/Map%20REL%20-%20Floor%20Tables.md) — The per-map character, entry-point, render, camera, offscreen and berry tables, field by field

### Other
- [BIN - Generic Binary Data](Shared/BIN%20-%20Generic%20Binary%20Data.md) — Context-dependent binary data (type `0x34`)

## Battle Revolution Formats

PBR reuses the FSYS container but not much else — its own file-type
namespace, its own text format, its own fonts.

- [MESG - String Tables](Battle%20Revolution/MESG%20-%20String%20Tables.md) — Every string in the game, addressed by a global id through a directory in `common.fsys`. Unrelated to the Colosseum/XD `.msg` beyond the extension. Dumped and rebuilt by `pbrStringsDump` / `pbrStringsBuild`

## File Type ID Reference

| ID | Extension | Format |
|----|-----------|--------|
| 0x02 | .rdat | Room model (DAT) |
| 0x04 | .dat | Character model (DAT) |
| 0x06 | .ccd | Collision data (CCD) |
| 0x08 | .samp | Sequenced music (SAMP) |
| 0x0A | .msg | Message strings (MSG) |
| 0x0C | .fnt | Font data (FNT) |
| 0x0E | .scd | Script bytecode (SCD) |
| 0x10 | .dats | Multi-model (DATS) |
| 0x12 | .gtx | Texture (GTX) |
| 0x14 | .gpt1 | Particle effects (GPT1) |
| 0x18 | .cam | Camera data (CAM) |
| 0x1C | .rel | Relocatable module (REL) |
| 0x1E | .pkx | Battle model (PKX) |
| 0x20 | .wzx | Move animation (WZX) |
| 0x22 | .gpt | Particle data (GPT) |
| 0x26 | .drel | Debug REL |
| 0x28 | .isd | Streamed audio data (ISD) |
| 0x2A | .ish | Streamed audio header (ISH) |
| 0x2C | .thh | Video header (THH) |
| 0x2E | .thd | Video data (THD) |
| 0x30 | .gsw | Flash menu animation (GSW) |
| 0x32 | .atx | Animated texture (ATX) |
| 0x34 | .bin | Generic binary (BIN) |
