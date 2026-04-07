# GPT - Particle Effects

GPT and GPT1 are particle effect data formats used for visual effects throughout the games. They define particle system parameters for effects like sparks, energy beams, auras, trails, and explosions used in battle animations and overworld events.

## Identification

| Property | Value |
|----------|-------|
| Type ID (GPT) | `0x22` |
| Type ID (GPT1) | `0x14` |
| Magic (GPT1) | `GPT1` (4 bytes, ASCII) |
| Byte Order | Big-endian |

## GPT1

GPT1 is the more commonly encountered variant. It is identified by the `GPT1` magic string at the start of the data.

### Standalone vs. Embedded

GPT1 data appears in two contexts:

- **Standalone**: As a separate file entry in an FSYS archive (type `0x14`).
- **Embedded in PKX**: Within battle model files, positioned between the PKX header and the DAT model. The GPT1 length is specified in the PKX header. See [PKX - Battle Model](PKX%20-%20Battle%20Model.md).
- **Embedded in WZX**: Within move animation archives, located by scanning for the `GPT1` magic. See [WZX - Move Animation](WZX%20-%20Move%20Animation.md).

## GPT

GPT (type `0x22`) is a related particle data format stored as standalone FSYS entries. The relationship between GPT and GPT1 is not fully documented.

## Usage

Particle effects are used for:

- Battle move visual effects (fire, water, electricity, psychic energy)
- Impact effects (hit sparks, dust clouds)
- Persistent effects (status condition auras, weather)
- Environmental effects (overworld sparkles, light shafts)

## Runtime System

The GSparticle runtime system manages particle effect playback. Particle banks are linked to models via `GSmodelLinkToGSparticleBank`, which associates a GPT1 particle bank with a DAT/HSD model so that the model's animations can trigger particle emission at the appropriate times and positions.

## Current Status

The internal binary layout of GPT and GPT1 files has not been fully reverse-engineered. The particle system parameter encoding (emission rate, lifetime, velocity, color curves, texture references, etc.) remains to be documented.
