# PKX - Battle Model

PKX is the battle model format used for Pokemon and trainer models during battle sequences. It wraps a DAT/HSD model with an extended header containing battle-specific metadata such as animation tables, shiny color filter data, and GPT1 particle effects. The header layout differs significantly between Colosseum and XD.

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x1E` |
| Byte Order | Big-endian |

## Header Structure (XD)

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | UInt32 | DAT length | Size of the embedded DAT model |
| 0x04 | 4 | UInt32 | GPT1 length | Size of the GPT1 particle data |
| 0x08 | 16 | - | Unknown | |
| 0x18 | 2 | UInt16 | Pokemon species index | National dex-adjacent index |
| 0x1A | 2 | - | Unknown | |
| 0x1C | 4 | UInt32 | Trainer flag | `0` if this is a trainer model |
| 0x20 | 4 | UInt32 | Format ID | `0xFFFFFFFF` for XD format |

### DAT Model Location (XD)

The embedded DAT model begins at:

```
0xE60 + GPT1Length (padded to 0x20-byte alignment)
```

The region between the header and the DAT model start contains animation metadata and the GPT1 particle data.

## Header Structure (Colosseum)

Colosseum uses a more compact header layout. The format ID field at offset 0x20 will not be `0xFFFFFFFF`, which distinguishes it from XD.

### DAT Model Location (Colosseum)

The embedded DAT model begins at:

```
0x40 + GPT1Length (padded to 0x20-byte alignment)
```

## Animation Metadata

Animation entries are stored in the header region between the fixed header fields and the DAT model. Each entry is 0xD0 bytes.

| Offset (within entry) | Size | Type | Field | Notes |
|------------------------|------|------|-------|-------|
| 0x90 | 4 | UInt32 | Animation index | Index into the model's animation bank |
| ... | ... | ... | ... | Remaining fields control timing, blending, transitions |

## Shiny Filter Data

Pokemon that can be shiny have color filter data that modifies the model's appearance for the shiny variant.

| Game | Location | Contents |
|------|----------|----------|
| XD | Offset `0x70` from file start | 4 integer modifiers + RGBA color values |
| Colosseum | `fileLength - 0x14` from file start | Same format, stored at end of file |

The filter applies color adjustments to the base model textures at runtime to produce the shiny coloration.

## GPT1 Particle Effects

The GPT1 section contains particle effect definitions used during battle animations (energy auras, sparkle effects, etc.). It is identified by the `GPT1` magic string and its length is specified in the header. See [GPT - Particle Effects](GPT%20-%20Particle%20Effects.md) for details.

## Game-Specific Differences

- **XD** uses the larger 0xE60-byte header region with format ID `0xFFFFFFFF` at offset 0x20.
- **Colosseum** uses a compact 0x40-byte header region with a different format ID value.
- Shiny filter data is located at a fixed header offset in XD but at a fixed offset from the end of the file in Colosseum.
- The format can be distinguished at parse time by checking the format ID field at offset 0x20.

## Runtime

PKX models are loaded by the battle rendering system. The loader reads the header to determine the DAT model offset, extracts animation metadata for battle pose/attack/faint sequences, and links the GPT1 particle bank to the model via `GSmodelLinkToGSparticleBank`.
