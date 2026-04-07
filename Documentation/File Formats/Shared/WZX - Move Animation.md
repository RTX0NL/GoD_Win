# WZX - Move Animation

WZX is the move animation archive format containing the visual effect assets for battle moves. Each WZX file bundles multiple sub-files (DAT models and GPT1 particle data) into a single blob without a formal header or directory structure. Contents are discovered by pattern matching against known magic bytes and structural signatures.

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x20` |
| Byte Order | Big-endian |

## Structure

WZX has no fixed header. The file is a concatenation of sub-files that must be located by scanning for known patterns.

### DAT Model Detection

DAT models within a WZX are identified by the following signature:

| Offset | Size | Value | Description |
|--------|------|-------|-------------|
| +0x00 | 4 | `0x00000001` | DAT identifier |
| +0x04 | 16 | `0x00...` | 16 null bytes |

Once a candidate is found, it is validated by checking for the string `scene_data` or `bound_box` at the expected offset within the model structure. The model length is read as a UInt32 at offset +0 from the model start. A minimum valid model size of 32 bytes is enforced to filter false positives.

### GPT1 Data Detection

GPT1 particle data sections are identified by the `GPT1` magic string (4 bytes ASCII). See [GPT - Particle Effects](GPT%20-%20Particle%20Effects.md) for the GPT1 format.

## Contents

A typical WZX file contains a combination of:

- **Impact models**: Visual effects displayed at the point of contact
- **Projectile models**: Animated objects traveling from attacker to target
- **Particle systems** (GPT1): Energy beams, sparks, trails, explosions, elemental effects

The number and type of sub-files varies per move. Simple moves may contain only particle data, while complex moves include multiple models and particle banks.

## Parsing Strategy

1. Scan the file for the DAT signature pattern (`0x00000001` + 16 null bytes).
2. For each candidate, validate by checking for `scene_data` or `bound_box` at the expected string table offset.
3. Read the model length from offset +0 and extract the model data.
4. Scan for `GPT1` magic to locate particle data sections.
5. Any remaining data between identified sub-files is treated as additional metadata or padding.

## Runtime

Move animation data is loaded during battle when a move is executed. The battle system instantiates the contained models and particle effects, positioning and timing them according to the move's animation script. Particle banks are linked to models via `GSmodelLinkToGSparticleBank`.
