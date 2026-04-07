# GSW — Flash Menu Animation Format

## Overview

GSW files are Genius Sonority's proprietary compiled Flash-like animation format, used for menu animations, UI elements, and visual effects in Pokemon Colosseum and XD. The format shares conceptual similarities with Macromedia SWF (shapes, sprites, text, fonts, morphing, placement) but uses a completely custom binary layout — it does NOT contain standard SWF data.

**File type ID:** `0x30` (48)
**Extension:** `.gsw`
**Byte order:** Big-endian
**Typical size range:** 7 KB – 670 KB

## File Header (0x38 bytes)

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | u32 | Version/magic | Always `0x00000007` in observed files |
| 0x04 | 2 | u16 | Canvas width | In twips (1/20th of a pixel). Common value: `60` |
| 0x06 | 2 | u16 | Canvas height | In twips. Varies per file (41–253) |
| 0x08 | 4 | u32 | Tag data size | Size of the embedded tag/animation data section |
| 0x0C | 2 | u16 | Unknown | Always `0x0000` in observed files |
| 0x0E | 2 | u16 | Frame rate | `0x3200` = 12800. Likely fixed-point (50.0 fps or similar) |
| 0x10 | 4 | u32 | Unknown constant | Always `0x00002580` (9600) |
| 0x14 | 4 | u32 | Unknown | Always `0x00000000` |
| 0x18 | 2 | u16 | Sprite depth count | Number of depth layers for sprites. Used by `InitDataPointer` to allocate per-depth state. If zero, defaults to 40 (0x28). |
| 0x1A | 2 | u16 | Character count | Number of character definitions (shapes, sprites, etc.). If zero, defaults to 40 (0x28). |
| 0x1C | 16 | - | Zero padding | |
| 0x2C | 4 | u32 | Unknown | |
| 0x30 | 2 | u16 | Frame label section marker | `0x0009` in observed files |
| 0x32 | 2 | u16 | Unknown | |
| 0x34 | 4 | u32 | Frame label count | Number of frame labels that follow |

## Frame Label Table

Immediately after the header (offset 0x38), a variable-length frame label table:

Each label entry contains:
- 4 bytes: Frame number or marker (`0xFFFFFF00` = background color?)
- Variable: Null-terminated ASCII label string, padded to 4-byte alignment

Example from `test.gsw`:
```
0x38: FFFFFF00 0000002B 0000000A 00000004  ← marker, then structure  
0x48: 73746172 74000000                    ← "start\0\0\0"
```

The `GetFrameFromLabel` function searches this table to resolve label names to frame indices.

## Tag Data Section

After the frame labels, the tag data begins. Tags follow a format similar to SWF but with GS-specific encoding. The `ParseTag` function dispatches on tag type codes 0x00–0x30:

### Known Tag Types

Based on the `ParseTag` switch table and called functions:

| Code | Name | Handler |
|------|------|---------|
| 0x00 | End / ShowFrame | Decrements frame counter, advances read position |
| 0x01 | ShowFrame variant | Similar to 0x00 with frame counting |
| ~0x04 | DefineShape | `ParseDefineShapeSub` — vector shape definitions |
| ~0x08 | DefineText | `ParaseTextRecord` — text definitions |
| ~0x0C | PlaceObject2 | `ParsePlaceObject2` / `ParsePlaceObject2Sub` — positions sprites on stage |
| ~0x10 | DefineFont2 | `ParseDefineFont2Sub` — embedded font definitions |
| ~0x14 | DefineMorphShape | `ParseDefineMorphShapeSub` — shape tweening definitions |
| ~0x18 | DefineSprite | Sprite (movie clip) definitions |

*Exact tag code mappings require further analysis of the jump table at `lbl_8041A100`.*

## Texture Data Sections

Embedded textures appear within the tag data. They are identified by:

1. **Section header marker:** `[0x03, 0x00, 0x00, id]` where `id` is the texture's index (1–255)
2. **Texture identification:** 2 bytes at `header + 0x24` = `0x0801` (marks a texture section)
3. **Format ID:** 4 bytes at `header + 0x28` = GameCube texture format (`GoDTextureFormats` enum value)
4. **Texture data:** Starts at `header + 0x20`
5. **Palette offset:** 4 bytes at `header + 0x68` = offset to 512-byte palette within texture data

### Supported Texture Formats

| Value | Format | Description |
|-------|--------|-------------|
| 0 | I4 | 4-bit intensity (grayscale) |
| 1 | I8 | 8-bit intensity |
| 2 | IA4 | 4-bit intensity + 4-bit alpha |
| 3 | IA8 | 8-bit intensity + 8-bit alpha |
| 4 | RGB565 | 16-bit color, no alpha |
| 5 | RGB5A3 | 16-bit color with alpha |
| 6 | RGBA32 | 32-bit full color |
| 8 | C4 | 4-bit indexed |
| 9 | C8 | 8-bit indexed (most common in GSW) |
| 10 | C14X2 | 14-bit indexed |
| 14 | CMPR | DXT1-like compressed |

## Runtime Data Structures

### FlashMenu Object (runtime, 0x48+ bytes)

Based on disassembly of `Init__9FlashMenuFPvUl`:

| Offset | Size | Field |
|--------|------|-------|
| 0x00 | 4 | Current read position (offset into tag data) |
| 0x04 | 4 | Unknown |
| 0x08 | 4 | Pointer to GSW file data |
| 0x0C | 4 | Total frame count |
| 0x10 | 4 | Unknown |
| 0x14 | 4 | Frame skip counter (for seeking) |
| 0x18 | 2 | Unknown |
| 0x1A | 2 | Unknown |
| 0x1C | 2 | Current frame display list depth |
| 0x1E | 1 | Has background flag |
| 0x24 | 1 | Playing flag |
| 0x25 | 1 | Loop flag |
| 0x28 | 4 | Play start frame |
| 0x2C | 4 | Play end frame |
| 0x30 | 4 | Play frame count |
| 0x34 | 4 | GS graphics layer pointer |
| 0x38 | 4 | Character definitions array pointer (allocated, 0x640 bytes) |
| 0x3C | 4 | Sprite work array pointer |
| 0x40 | 4 | Display list array pointer |
| 0x44 | 2 | Target frame (for conditional stop) |

### Sprite Work Entry (0x40 bytes each)

Each sprite depth has a 0x40-byte state block:

| Offset | Size | Field |
|--------|------|-------|
| 0x00 | 2 | Character ID |
| 0x04 | 24 | FLASHMATRIX (2D transformation matrix) |
| 0x1C | 4 | Depth/Z-order (float) |
| 0x20 | 12 | FLASHCXFORM (color transform) |
| 0x30 | 4 | Unknown |
| 0x34 | 4 | Unknown |
| 0x3C | 1 | Visibility flag |

### Character Definition Entry (0x08 bytes each)

| Offset | Size | Field |
|--------|------|-------|
| 0x00 | 1 | Type (0x20 = text, others = shape/sprite) |
| 0x04 | 4 | Pointer to definition data |

## Flash System API

The game's flash system provides these functions for script/game code:

| Function | Purpose |
|----------|---------|
| `FlashSystemInitAll` | Initialize all flash menu slots |
| `FlashSystemInit` | Load and initialize a specific GSW file |
| `FlashSystemPlay` | Start animation playback |
| `FlashSystemPlayAndWait` | Play and block until complete |
| `FlashSystemSetLoopFlag` | Enable/disable animation looping |
| `FlashSystemGetNowFrame` | Query current frame number |
| `FlashSystemGetEndFrame` | Query total frame count |
| `FlashSystemGetFrameFromLabel` | Resolve frame label to index |
| `FlashSystemGetGStexture` | Extract a GStexture for external use |
| `FlashSystemDraw` | Render current frame |
| `FlashSystemRelease` | Unload and free resources |

## Loading Pipeline

1. `floorReadGSWPreFunc` — Pre-load hook during room loading
2. GSW data loaded from FSYS archive into memory
3. `FlashSystemInit` → `FlashMenu::Init` — Parses header, allocates runtime structures
4. `InitDataPointer` — Initializes per-depth sprite work and display lists
5. `ParseTag` loop — Processes all tags in the frame, building shapes/sprites/text
6. `FlashSystemPlay` — Begins frame-by-frame animation
7. `FlashSystemDraw` → `FlashMenu::Draw` → `DrawSprite`/`DrawText` — Renders each frame
8. `floorReadGSWPostFunc` / `FlashSystemRelease` — Cleanup on room exit

## Open Questions

- Exact tag type codes (need to dump the jump table at `lbl_8041A100`)
- Full frame label table format (alignment, termination)
- FLASHMATRIX and FLASHCXFORM exact field layouts
- How embedded textures interact with shape definitions
- Relationship between canvas dimensions (twips) and screen pixels
- Whether the format changed between Colosseum and XD
- Full tag data encoding for each tag type

## References

- **Disassembled code:** `text1/flashmenu/` and `text1/flashsystem/` in DOL disassembly
- **Old GoD tool:** `Objects/file formats/XGGSWTextures.swift` — texture extraction only
- **File type registration:** `GeniusSonority/Enums/entries/FileTypes.swift` — type ID 0x30
