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
| 0x04 | 4 | UInt32 | Creation date | Hex-coded `0xYYYYMMDD` — `0x20040109` = 2004-01-09 (see below) |
| 0x08 | 4 | UInt32 | Sample rate | Samples per second (typically 32000 or 48000) |
| 0x0C | 4 | UInt32 | Sample count | Total number of audio samples |
| 0x10 | 4 | UInt32 | Stream size | Size of the ISD data in bytes |
| 0x14 | 4 | UInt32 | Channel count | Number of audio channels (1 = mono, 2 = stereo) |
| 0x18 | 4 | UInt32 | Interleave size | Block size in bytes for channel interleaving |
| 0x1C | 4 | UInt32 | Loop flag | 0 = no loop, non-zero = loop enabled |
| 0x20 | 4 | UInt32 | Loop start | **Nibble address** into one channel's stream |
| 0x24 | 4 | UInt32 | Loop end | **Nibble address**; used as the end when looping |
| 0x28 | 4 | UInt32 | Stream end | **Nibble address**; used as the end when not looping, and always converted to a sample total |
| 0x2C | 20 | - | Reserved | Zero on all 565 real headers measured |
| 0x40 | varies | Int16[] | DSP coefficients | 16 coefficient pairs per channel (see below) |

### Control points are nibble addresses

The three control words are **nibble addresses into one channel's ADPCM
stream**, not byte offsets into the ISD. A frame is 8 bytes = 16 nibbles, of
which the first 2 are the frame header byte, so the first sample lives at
nibble 2 — the value 477 of 477 non-looping real headers carry at 0x20.

The game's own stream setup pins both the unit and the roles.
`GSsndStreamPreFunc` hands the FSYS loader `stream + 0x40` as the buffer to
read the ISH into, so the stream struct's words at `+0x5C`, `+0x60`, `+0x64`
and `+0x68` are ISH `0x1C`, `0x20`, `0x24` and `0x28`. `GSsndStreamPostFunc`
then:

- reads `0x20` and `0x24` as the loop start and end when the flag is set,
- reads `0x28` as the end when the flag is clear (loop start 0),
- converts `0x28` through `_sndStreamNibble_HeaderON2OFF` — a multiply by
  14/16 — into a sample total at `+0x7C`, regardless of the flag,
- block-aligns what it passes on: the loop start rounds **down** and the end
  rounds **up** to a whole `0x10000`-nibble (one interleave block) boundary,
  which is why a looping track's `0x24` is always of the form `0x…FFFF`.

Inferring the roles from the stored values alone gets `0x24` and `0x28` the
wrong way round, because a looping track's authored loop end sits *past* its
`0x28`: on all 88 looping headers `2 ≤ 0x20 < 0x28 ≤ 0x24`, and on all 477
non-looping ones `0x20 == 2` and `0x24 == 0x28`.

### Stream size is derived, not carried

`0x10` is the stream's content length — the ADPCM before the ISD is padded
out to whole interleave blocks (the padded length differs from it on 464 of
565 real files, so the ISD's own size is not the answer either).

It is a property of the audio rather than an authored choice, so a rebuild
derives it from the stream it encodes. The games' value is **0-13 bytes
smaller** on those 464 files, always smaller and always by less than one
frame per channel: their packer stops mid-frame, writing `1 + ceil(r/2)`
bytes for a last frame holding `r` samples, where a whole-frame encoder
emits 8. Replaying their number would describe a stream the rebuild didn't
write.

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

`interleave_size` is a **transport granularity, not an audio one**: it is
how much of one channel the streamer reads at a time, and deinterleaving
concatenates a channel's blocks back into one contiguous stream. A block
boundary falling mid-frame therefore costs nothing — the frame reassembles
either side of the other channel's block. Verified: encoding the same PCM at
interleave sizes of 1, 3, 7, 8, 100, 0x800, 0x8000, 0x8001 and 0xFFFF decodes
to bit-identical samples. **Zero is the only invalid value** (it divides by
zero while padding).

It is 32768 (`0x8000`, 32 KiB) on all 565 real headers — the DVD read and
ARAM buffer granularity.

**It is dumped as a raw byte count**, not as a frame count (`size / 8`) or an
exponent (`log2`). Both of those would read as encoding a rule the format
does not have, and would make legal values inexpressible: a frame count
cannot spell 100, and an exponent cannot spell anything but a power of two.
One observed value is no basis for declaring either constraint. Decimal
rather than hex follows the house style for magnitudes — hex strings are
reserved for addresses you would cross-reference against a disassembly, as
in the REL manifest.

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

### Control Point Conversion

A nibble address names a sample:

```
frame, position = divmod(nibble, 16)
sample = frame * 14 + (position - 2)        # position >= 2
nibble = (sample / 14) * 16 + (sample % 14) + 2
```

This is exact in both directions for every address that names a sample, and
the only addresses that don't are a frame's two header nibbles — which no
control word in the corpus uses (0 of 1,695).

The game itself uses `floor(nibble * 14/16)` instead
(`_sndStreamNibble_HeaderON2OFF`), which agrees to within one sample but is
not injective, so it cannot be used to store a control point.

**The editable manifest stores seconds**, at **6 decimal places**, and the
three control points are the authored metadata a rebuild takes from it.
See "Editable artifacts" below for the full field list.
Recovering the sample needs better than `0.5 / sampleRate` — 1.13e-5 s at
the corpus's highest rate of 44.1 kHz — and six places give 5e-7, a 22x
margin; the decoder rounds `seconds * rate` to the nearest sample, so the
printed precision is all that has to be right. Five places are also exact on
the whole corpus, four are not (863 of 1,695 words come back wrong, drifting
up to 1.86 samples) and three drift up to 19.5.

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

## Editable artifacts

A stream dumps as `<name>.isf.json` beside `<name>.wav`. The manifest holds
only what the audio cannot say:

| Field | ISH offset | Meaning |
|---|---|---|
| `loop.enabled` | `0x1C` | Whether the stream loops |
| `loop.startSeconds` | `0x20` | Where the loop jumps back **to** |
| `loop.endSeconds` | `0x24` | Where the loop jumps back **from** |
| `streamEndSeconds` | `0x28` | Where the stream ends |
| `interleaveSize` | `0x18` | Bytes of one channel per ISD block — 32768 on 565/565 |
| `creationDate` | `0x04` | When the packer built the file, as an ISO 8601 date |
| `wavPath` | — | The companion WAV |

```json
{
  "creationDate" : "2004-01-09",
  "interleaveSize" : 32768,
  "loop" : { "enabled" : true, "startSeconds" : 0.533425, "endSeconds" : 25.196629 },
  "streamEndSeconds" : 24.671113,
  "wavPath" : "stm_bgm_stand.wav"
}
```

**Sample rate (`0x08`) and channel count (`0x14`) are not in the manifest** —
the WAV header carries both, so the WAV is the authority. Repeating them
would create a pair that can fall out of step, and swapping in audio at
another rate is an ordinary edit, not a mismatch to refuse.

Everything else in the header is a function of the audio and is re-derived:
the magic, the sample count (`0x0C`), the content length (`0x10`), the
reserved run (`0x2C..0x3F`, written as zeros) and the coefficient table.

**What is *not* derivable, despite looking it.** `loop.endSeconds` equals
the last sample on 548 of 565 headers — but 17 looping tracks end their loop
early and not marginally (`stm_bgm_XD_lastbattle` by 24,170 nibbles, about
13 seconds of audio; `stm_me_me_news` by 12,056), so deriving it would
relocate the loop on exactly the tracks that chose not to take the default.
`streamEndSeconds` is the mirror case: it equals the loop end on all 477
non-looping files and on **0 of 88** looping ones. And `loop.enabled` is
inferable from `0x20 == 2 && 0x24 == 0x28` on 565/565, which is a convention
the packer followed rather than a derivation — a track looping the whole
stream from its first sample would satisfy the test and silently lose its
loop.

### The creation date

`0x04` is a date with its digits written in hex — `0x20040109` is
2004-01-09 — and the manifest spells it `"2004-01-09"`. A word that isn't a
valid hex-coded date is written as a `0x`-prefixed literal instead so it
still round-trips, the same rule the typed-table exporters use for a value
whose spelling can't carry it.

Every other encoding is numerically impossible for this value:

| Reading | Gives |
|---|---|
| Hex-coded `0xYYYYMMDD` | **2004-01-09** |
| Unix epoch seconds | 1987-01-08 — before the GameCube existed |
| Seconds since 2000-01-01 | 2017-01-07 — after all three games shipped |
| DOS/FAT date+time pair | year 1996, **month 0** — invalid |
| GameCube `OSTime` ticks | 13 seconds past midnight, 2000-01-01 |
| Decimal digits | `537133321` — nine digits, not a date |

2004 is also where it has to be: between Colosseum's Japanese release
(2003-11-21) and XD's (2005-08-04), and a few months before the SDK
apploader shipped on XD's own disc.

**Month before day follows the platform.** That apploader stores its date as
ASCII `YYYY/MM/DD` at disc offset `0x2440`, and XD's reads `2004/05/21` —
the `21` can only be a day, so Nintendo's convention on the same disc is
unambiguous (Colosseum's and Pokémon Channel's both read `2002/09/05`). It
is also the only field order that leaves the packed word chronologically
sortable, which is the reason to pack a date into one integer at all.

Strictly, a single observed value cannot *prove* month before day: **every
ISH on every disc carries `0x20040109`**, and XD is the only one of the
three games that uses the format at all — Colosseum and Battle Revolution
ship none. A scan of all 13,699 files in an XD dump for hex-coded-date-shaped
words found no other field carrying one, so there is no second data point to
be had. This rests on the convention, not on a measurement.

## Round-trip status

The **0x40-byte header is byte-identical apart from `0x10`** through
`ISFFile`, both at the binary level and through the editable JSON + WAV pair
(`ISFHeaderRealCorpusTests`, skips without a corpus, `GODDESS_ISF_CORPUS`).
Pairs are found by magic rather than extension, because the legacy tool's
dump names the stream `.ish` and the header `.isd` for every unnamed entry.

Both halves are rebuilt from scratch from the WAV and the manifest; nothing
of the original is consulted. Three things are therefore re-derived and do
**not** come back byte-identically, by design — ISF is not a declared 1:1
target:

- the **content length** at `0x10` (above),
- the **coefficient table** at `0x40`, rebuilt by LPC analysis of the
  decoded PCM, and
- the **ADPCM body**, a lossy 4-bit codec.

What the header costs if it is got wrong is worth recording, since all three
of these shipped: treating the control words as byte offsets puts every one
of them a byte out (48/48 and then 565/565 of the corpus), zeroing `0x28`
leaves a looping track with `loopFlag = 1` and a stream end of 0, and
writing the padded ISD length at `0x10` overstates the content length on
464 of 565 files.

## References

- Nintendo GameCube SDK: DSP ADPCM documentation
- vgmstream: `src/coding/ngc_dsp_decoder.c` (decode), `src/meta/ish_isd.c` (ISH/ISD metadata parsing)
- gc-dspadpcm-encode (MIT license): DSP ADPCM encoder with LPC coefficient calculation
- VGAudio (MIT license, C#): Full encode and decode implementation
