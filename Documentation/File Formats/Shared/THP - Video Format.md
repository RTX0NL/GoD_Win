# THP - Video Format

THP is Nintendo's standard video format for GameCube and Wii. In FSYS archives, THP videos are split into two separate entries: a THH header file and a THD data file. These must be recombined to produce a playable THP file.

## Identification

| Property | Value |
|----------|-------|
| Type ID (Header) | `0x2C` (THH) |
| Type ID (Data) | `0x2E` (THD) |
| Byte Order | Big-endian |

## Split Storage in FSYS

FSYS archives store THP videos as two separate entries:

- **THH** (type `0x2C`): The THP header containing video metadata and component descriptions.
- **THD** (type `0x2E`): The THP frame data containing the actual video and audio content.

This split allows the game to load the small header for metadata inspection without reading the large data payload.

## THH Header Structure

The THH header has a variable size based on the number of components.

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 0x20 | - | Base header | Standard THP header fields |
| 0x20 | var | - | Component data | Variable-length component descriptions |

### Component Types (at offset 0x20+)

Components are described sequentially. Each component entry has a type field at offset +4:

| Type Value | Component | Data Size | Description |
|------------|-----------|-----------|-------------|
| `0x00` | Video | 12 bytes | Video stream parameters (dimensions, framerate) |
| `0x01` | Audio | 16 bytes | Audio stream parameters (sample rate, channels) |
| `-1` | None | 0 | Terminator / unused slot |

## THD Data Structure

THD contains the raw frame data for the THP video. Frames are stored sequentially with each frame containing interleaved video and audio data as described by the component layout in the THH header.

## Recombining THH + THD

To produce a standard playable THP file:

1. Concatenate the THH header followed by the THD data.
2. Adjust the offset pointers at positions `0x28` and `0x2C` in the header to account for the header size, since the original pointers assume the data immediately follows (offset 0 = start of THD), but in the combined file the data starts after the header.

```
Combined offset = original THD offset + THH size
```

The resulting file is a standard Nintendo THP that can be played by standard THP players and demuxers.

## Runtime

THP videos are played during cutscenes, intro sequences, and title screens. The game loads the THH header first to determine video dimensions and audio format, then streams THD frame data during playback.
