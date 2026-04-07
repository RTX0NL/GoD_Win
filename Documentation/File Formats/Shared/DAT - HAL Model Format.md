# DAT / RDAT - HAL Model Format

DAT is the 3D model format used in Pokemon Colosseum and Pokemon XD, based on HAL Laboratory's HSD (HAL Sysdolphin) library -- the same model system used in Super Smash Bros. Melee. It stores hierarchical scene graphs containing joint trees, mesh objects, materials, texture references, vertex data, and animation data. Character models use the `.dat` extension (type ID 0x04), while room/environment models use `.rdat` (type ID 0x02).

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x04` (character DAT), `0x02` (room RDAT) |
| Extension | `.dat`, `.rdat` |
| Byte Order | Big-endian |
| Base Format | HAL Sysdolphin (HSD) |

## File Header (0x20 bytes)

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | UInt32 | File size | Total size of the file |
| 0x04 | 4 | UInt32 | Data size | Size of the data block (from end of header to relocation table) |
| 0x08 | 4 | UInt32 | Node count | Number of relocation entries |
| 0x0C | 4 | UInt32 | Public root count | Number of public (exported) root nodes |
| 0x10 | 4 | UInt32 | External root count | Number of external (imported) root nodes |
| 0x14 | 4 | UInt32 | Version | Format version identifier |
| 0x18 | 4 | - | Padding | |
| 0x1C | 4 | - | Padding | |

## File Layout

The file is organized into sequential sections following the header:

```
+------------------+ 0x00
| Header (0x20)    |
+------------------+ 0x20
| Data Block       |  <- All node/object data; pointers are relative to 0x20
+------------------+ 0x20 + data_size
| Relocation Table |  <- node_count * 4 bytes (UInt32 offsets)
+------------------+
| Public Roots     |  <- public_root_count * 8 bytes
+------------------+
| External Roots   |  <- external_root_count * 8 bytes
+------------------+
| String Table     |  <- Null-terminated strings referenced by root nodes
+------------------+
```

## Root Node Entries (8 bytes each)

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | UInt32 | Node pointer | Offset into the data block (relative to 0x20) |
| 0x04 | 4 | UInt32 | Name pointer | Offset into the string table |

Public roots are the entry points into the scene graph. Common root node names include joint trees (`*_joint`), animation tracks (`*_matanim_joint`), and shape sets.

## Relocation Table

The relocation table contains `node_count` UInt32 entries. Each entry is an offset within the data block that contains a pointer needing relocation. When the file is loaded into memory, the loader adds the data block base address to the value at each relocation offset, converting file-relative pointers to absolute memory addresses.

## Data Block Contents

All object data lives in the data block. Pointers within the data block are relative to offset 0x20 (the start of the data block). The HSD format uses a hierarchical node structure:

### Joint Nodes (JObj)
Skeletal joints forming the bone hierarchy. Each joint references child joints, sibling joints, and attached display objects. Contains transform data (translation, rotation, scale).

### Display Objects (DObj)
Linked to joints. Each display object references a material (MObj) and a polygon object (PObj).

### Material Objects (MObj)
Material properties including color, alpha, and texture references (TObj). Materials can chain multiple textures for multi-texturing.

### Texture Objects (TObj)
References to embedded texture data with format, dimensions, wrapping modes, and filtering parameters. Textures use the same GX texture formats as GTX files.

### Polygon Objects (PObj)
Vertex data in GameCube GX display list format. Contains vertex position, normal, color, and UV coordinate arrays referenced by index.

### Vertex Colors
Vertex color data embedded directly in the data block, referenced by polygon objects. Stored in GX-native formats (RGB8, RGBA8, etc.).

### Palette Metadata
Palette (TLUT) data for indexed texture formats (C4, C8, C14X2). Contains the color lookup table entries.

## Game-Specific Differences

- **Character DAT (0x04)**: Contains a single character model with skeleton, mesh, textures, and animations. Used for Pokemon models, trainer models, and UI elements.
- **Room RDAT (0x02)**: Contains environment geometry, typically with multiple root nodes for different map layers (opaque geometry, transparent geometry, skybox). Paired with CCD collision data.
- Both Colosseum and XD use the same underlying HSD format. Differences are in the specific node structures and root node naming conventions rather than the file format itself.

## Runtime System: GSmodel

The game accesses DAT/RDAT files through the `GSmodel` runtime system, which wraps the lower-level HSD library. Disassembly of XD reveals 48+ functions in the GSmodel module:

- Model loading and initialization
- Joint tree traversal and animation
- Material and texture binding
- Render state management
- LOD (level of detail) selection
- Animation blending and playback control

The HSD library itself provides the core scene graph traversal, GX display list submission, and matrix stack operations.

## References

- HAL Laboratory's Sysdolphin SDK (proprietary, not publicly documented)
- Super Smash Bros. Melee modding community documentation of the HSD format
- XD disassembly: GSmodel module functions
