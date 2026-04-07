# SAMP - Sequenced Music

SAMP is the sequenced music sample data format, part of the MusyX audio engine used by Genius Sonority. It works together with three companion formats (SDIR, PROJ, POOL) to provide sequenced music playback, as opposed to the ISH/ISD system used for streamed audio.

## Identification

| Property | Value |
|----------|-------|
| Type ID (SAMP) | `0x08` |
| Type ID (SDIR) | `0x86` |
| Type ID (PROJ) | `0x84` |
| Type ID (POOL) | `0x88` |
| Byte Order | Big-endian |

## MusyX Audio System

The four file types form a complete sequenced music system:

| Format | Type ID | Role |
|--------|---------|------|
| SAMP | `0x08` | Sample data (instrument waveforms, sound effects) |
| SDIR | `0x86` | Sound directory (index mapping sample IDs to SAMP offsets) |
| PROJ | `0x84` | Sound project (sequence definitions, instrument assignments, song structure) |
| POOL | `0x88` | Sound pool (shared sample bank for memory-efficient reuse) |

### SAMP

Contains the raw audio sample data (instrument waveforms) referenced by the other components. These are the actual sound recordings that get pitched and mixed during playback.

### SDIR

The sound directory provides an index that maps logical sample identifiers to byte offsets within the SAMP data, along with sample metadata (loop points, base pitch, etc.).

### PROJ

The sound project defines the musical sequences: note events, timing, instrument assignments, volume envelopes, and song structure. This is the "sheet music" that drives the sequencer.

### POOL

The sound pool provides a shared sample bank, allowing multiple sequences to reference common instrument samples without duplicating data.

## Sequenced vs. Streamed Audio

| Aspect | Sequenced (SAMP/SDIR/PROJ/POOL) | Streamed (ISH/ISD) |
|--------|----------------------------------|---------------------|
| Storage | Small (samples + sequences) | Large (full audio stream) |
| CPU cost | Higher (real-time mixing) | Lower (direct playback) |
| Flexibility | Dynamic (tempo, pitch, layers) | Fixed recording |
| Use case | BGM, jingles, sound effects | Voice acting, FMV audio, long tracks |

## Runtime System

The DSP subsystem (7 functions) handles low-level audio processing, while the sound system (30+ functions) provides high-level control:

### Sound Categories

| Category | Description |
|----------|-------------|
| BGM | Background music (looping sequences) |
| ME | Music effects (jingles, fanfares, one-shot sequences) |

### Key Capabilities

- Volume control per channel and master
- Environment effects (reverb, echo)
- Crossfading between BGM tracks
- Priority-based sound management
- Dynamic mixing of multiple simultaneous sequences

## Current Status

The internal binary layouts of all four MusyX formats have not been fully reverse-engineered. The MusyX engine was a middleware audio solution by Factor 5, and documentation of the file formats is limited. The runtime API is known from XD disassembly and symbol maps.
