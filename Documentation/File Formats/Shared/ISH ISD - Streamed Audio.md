# ISH / ISD - Streamed Audio

ISH and ISD are a paired audio format used in Pokemon Colosseum and Pokemon XD for streamed music and sound effects. The ISH file contains the header with metadata and DSP ADPCM decoding coefficients, while the ISD file contains the raw interleaved audio sample data. The format uses Nintendo's GameCube DSP ADPCM codec, a 4-bit adaptive differential pulse-code modulation scheme with linear prediction.

## Identification

| Property | Value |
|----------|-------|
| ISH Type ID | `0x2A` |
| ISD Type ID | `0x28` |
| ISH Extension | `.ish` |
| ISD Extension | `.isd` |
| ISH Magic | `I_SF` (4 bytes, ASCII) |
| Byte Order | Big-endian |

## ISH Header

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | char[4] | Magic | `I_SF` |
| 0x04 | 4 | UInt32 | Tool date | Build tool date in hex (e.g. `0x20040109` = 2004-01-09) |
| 0x08 | 4 | UInt32 | Sample rate | Samples per second (typically 32000 or 48000) |
| 0x0C | 4 | UInt32 | Sample count | Total number of audio samples |
| 0x10 | 4 | UInt32 | Stream size | Size of the ISD data in bytes |
| 0x14 | 4 | UInt32 | Channel count | Number of audio channels (1 = mono, 2 = stereo) |
| 0x18 | 4 | UInt32 | Interleave size | Block size in bytes for channel interleaving |
| 0x1C | 4 | UInt32 | Loop flag | 0 = no loop, non-zero = loop enabled |
| 0x20 | 4 | UInt32 | Loop start | Loop start point as byte offset into ISD data |
| 0x24 | 4 | UInt32 | Loop end | Loop end point as byte offset into ISD data |
| 0x28 | 24 | - | Reserved | |
| 0x40 | varies | Int16[] | DSP coefficients | 16 coefficient pairs per channel (see below) |

### DSP Coefficients

Starting at offset 0x40, each channel has 16 pairs of signed 16-bit coefficients (0x40 bytes per channel = 32 Int16 values). These coefficients are precomputed during encoding using Linear Predictive Coding (LPC) analysis and are required for decoding.

For a stereo file:
- Channel 0 coefficients: offset 0x40 to 0x7F (0x40 bytes)
- Channel 1 coefficients: offset 0x80 to 0xBF (0x40 bytes)

## ISD Data Layout

The ISD file contains raw DSP ADPCM frames with channel data interleaved in blocks of `interleave_size` bytes:

```
+---------------------------+
| Ch0 block 0               |  interleave_size bytes
+---------------------------+
| Ch1 block 0               |  interleave_size bytes (if stereo)
+---------------------------+
| Ch0 block 1               |  interleave_size bytes
+---------------------------+
| Ch1 block 1               |  interleave_size bytes (if stereo)
+---------------------------+
| ...                       |
+---------------------------+
```

For mono audio, there is no interleaving -- the data is one continuous stream.

## DSP ADPCM Decoding

Each 8-byte frame decodes to 14 PCM samples.

### Frame Structure

| Byte | Content |
|------|---------|
| 0 | Header: high nibble = coefficient index, low nibble = scale exponent |
| 1-7 | 14 nibbles of sample data (high nibble first per byte) |

### Decode Algorithm

```
For each 8-byte frame:
    scale = 1 << (frame[0] & 0x0F)
    coef_index = (frame[0] >> 4) & 0x0F
    coef1 = coefficients[coef_index * 2]
    coef2 = coefficients[coef_index * 2 + 1]

    For each of 14 nibbles (high nibble first per byte):
        nibble = sign-extend 4-bit value to signed integer
        sample = ((nibble * scale) << 11 + 1024 + coef1 * hist1 + coef2 * hist2) >> 11
        sample = clamp(sample, -32768, 32767)
        hist2 = hist1
        hist1 = sample
        output sample as 16-bit signed PCM
```

Two history values (`hist1`, `hist2`) are maintained per channel across frames, initialized to zero at the start of decoding (or restored from saved state at loop points).

### Loop Point Conversion

To convert byte offsets to sample positions:

```
samples = (byte_offset * 14) / 8 / channel_count
```

## Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| Frame size | 8 bytes | Each ADPCM frame |
| Samples per frame | 14 | Decoded output per frame |
| Bits per sample | 4 | ADPCM encoded |
| Coefficient pairs | 16 | Per channel |
| Bytes per coefficient set | 0x40 | 32 Int16 values |

## WAV Conversion

To convert ISH/ISD to standard WAV:

1. Read ISH header for sample rate, sample count, channel count, and coefficients
2. De-interleave ISD data into per-channel streams
3. Decode each channel's DSP ADPCM frames to 16-bit signed PCM
4. Write standard 44-byte RIFF WAV header (PCM format, 16-bit, little-endian)
5. Interleave decoded channels as 16-bit LE PCM samples

## Game-Specific Differences

The ISH/ISD format is identical between Colosseum and XD. Both games use the same DSP ADPCM codec and file layout. Differences are limited to the specific audio content (different music tracks, sound effects).

## References

- Nintendo GameCube SDK: DSP ADPCM documentation
- vgmstream: `src/coding/ngc_dsp_decoder.c` (decode), `src/meta/ish_isd.c` (ISH/ISD metadata parsing)
- gc-dspadpcm-encode (MIT license): DSP ADPCM encoder with LPC coefficient calculation
- VGAudio (MIT license, C#): Full encode and decode implementation
