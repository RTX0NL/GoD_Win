# Binary Patches — UPS, IPS, BPS, xdelta

Four formats for "the difference between two files", all implemented in
`GoDFoundation/Data/Patching/` and all reachable through the `createPatch` /
`applyPatch` operations. None is a game format: they describe any two files.

| Format | Magic | Shape | Verifies | Reversible |
|---|---|---|---|---|
| UPS | `UPS1` | the XOR of the two files, as hunks at fixed offsets | source, target, itself | **yes** |
| BPS | `BPS1` | an instruction stream: read from source, read literals, copy from either | source, target, itself | no |
| IPS | `PATCH` | offset-and-size records; three-byte offsets cap it at 16 MiB | **nothing** | no |
| xdelta | `D6 C3 C4` | VCDIFF (RFC 3284): windows of copy/add/run instructions | each window, where the writer stamped a checksum | no |

UPS and BPS are byuu's, and share a variable-width integer
(`PatchVariableLengthInteger`) that is **not** the one VCDIFF uses
(`VCDIFFInteger`) — see each section below. IPS predates all of them and carries
no integrity information whatsoever.

What each writer here can express:

- **UPS, IPS**: the target's bytes where they sit. Data that moved is a
  difference, and costs its own bytes.
- **BPS**: runs shared with the source and runs that aren't — byuu's "linear"
  creator. Correct and compact, but it does not search for moved data; the
  *reader* handles all four actions, because other tools emit them.
- **xdelta**: a real search over the source, which is the reason to reach for
  it. A region that moved becomes one copy instruction.

---

## UPS

### Layout

```
offset  size  field
0x00    4     "UPS1"
0x04    VLV   source file size
 …      VLV   target file size
 …            hunks, repeated until (file length - 12):
                VLV   relative offset — positions to skip from the current one
                n×1   XOR bytes       — output[i] = input[i] ^ byte
                1     0x00            — closes the hunk; counts as a position
 …      4     CRC-32 of the source file   (little-endian)
 …      4     CRC-32 of the target file   (little-endian)
 …      4     CRC-32 of the patch, over every byte ahead of this word
```

The shortest legal patch is 18 bytes: magic, two one-byte sizes and the
footer. That is what two empty files produce.

### Variable-width integer

Not LEB128. byuu's encoder, verbatim:

```
loop {
    x = offset & 0x7f
    offset >>= 7
    if (offset == 0) { write(0x80 | x); break; }
    write(x);
    offset--;
}
```

The `offset--` makes the encoding canonical — the ranges each byte count can
express are disjoint rather than overlapping, so every value has exactly one
spelling. Decoding has to add the running multiplier back:

```
value = 0; shift = 1
loop {
    x = read()
    value += (x & 0x7f) * shift
    if (x & 0x80) break
    shift <<= 7
    value += shift
}
```

A plain base-128 decoder reads every multi-byte value short, by an amount that
grows with the byte count: small patches decode correctly and large ones go
subtly wrong. Spellings worth keeping to hand: `0` → `80`, `0x7F` → `FF`,
`0x80` → `00 80` (a base-128 encoder would write `01 80`), `0x4080` →
`00 00 80`.

### Three rules an implementation has to get right

1. **A hunk's terminating `0x00` occupies an output position.** A hunk spans
   `payload + 1` positions, so the next hunk's relative offset is measured from
   one past the payload's end. Treat the terminator as free and every hunk
   after the first lands a byte early.
2. **The XOR space is `max(sourceSize, targetSize)`**, not either file's own
   length; bytes past the shorter file read as zero. That is how the patch
   carries the longer file's tail.
3. **The footer words are little-endian.** The third covers everything before
   itself, including the first two.

### Symmetry

XOR is its own inverse and the patch stores both sizes and both checksums, so
one patch works in both directions: applying it to the target reproduces the
source. Only the output length changes. Applying forward writes `targetSize`
bytes, so when the target is the shorter side the patch holds hunk data past
the end of the output — those bytes exist to rebuild the longer side and are
dropped rather than treated as corruption.

This is what lets `applyPatch` derive its own direction: an input matching one
side's size and checksum settles it, and `direction` only has to be named when
both sides are the same length and neither checksum matches.

### Implementation

| file | role |
|---|---|
| `UPSVariableLengthInteger` | the integer above, both ways |
| `UPSPatchByteStream` | sequential windowed byte reads, for the forward walk a parse has to make |
| `UPSPatch` | parse (header, hunk index, footer) and `plan` (diff two files into runs) |
| `UPSPatchedView` | the patched output, as a `GoDReadable` |
| `UPSPatchView` | the patch itself, as a `GoDReadable` over the two files |
| `UPSPatchCodec` | `PatchCodec` conformance: create, apply, validate |

Neither direction holds a file. A patch is applied by XORing hunks over the
input as the result is written, hunk payloads read from the patch on demand;
one is created by walking both files to record differing *ranges*, then
deriving each payload byte as `source ^ target` when the writer asks for it.
Creating a patch takes two passes over the inputs rather than one because the
footer stores the CRC-32 of every byte ahead of it, so the patch's own bytes
have to exist before its last word can be written.

Validation is by cross-check rather than round trip: `ReferenceUPSPatcher` in
the test target is an independently transcribed applier, patch reader and
CRC-32, and every patch the encoder produces is applied through it as well as
through `UPSPatchedView`. `UPSPatchTests` also pins the on-wire layout against
hand-authored bytes.

---

## IPS

The oldest of the four, and the only one that verifies nothing.

```
"PATCH"
records, until the three bytes "EOF" appear where a record would:
    3   offset, big-endian
    2   size, big-endian
    if size == 0:  2  run length, big-endian
                   1  the byte to repeat
    else:          n  the bytes to write
"EOF"
3   optional: the length to truncate the file to
```

Four consequences, each of which the implementation has to handle:

1. **A three-byte offset caps the format at 16 MiB.** Nothing past `0xFFFFFF`
   can be addressed, which rules out a disc image. `plan` refuses, naming the
   offset, rather than wrapping.
2. **An offset of `0x454F46` spells "EOF".** A record there would end the patch
   for every reader, so one is never written: the record starts a byte earlier
   and covers one byte that didn't need patching.
3. **Nothing identifies the file a patch belongs to** — no checksums, no source
   size, no metadata. Applying one cannot be checked, by us or by any other
   tool, and `apply` reports that rather than letting the absence pass for a
   pass.
4. **Records are applied in order and may overlap**, so a later record wins
   where two cover the same byte. They are applied, not merged.

A run record costs three payload bytes whatever its length, so a repeat longer
than three bytes is written as one; shorter repeats stay literal. A target
shorter than its source becomes the trailing truncation field, which is the only
way the format can express shrinkage.

| file | role |
|---|---|
| `IPSPatch` | records, parse, and the diff that plans them |
| `IPSPatchedView` | the patched output, as a `GoDReadable` |
| `IPSPatchView` | the patch itself, over the target |
| `IPSPatchCodec` | `PatchCodec` conformance |

---

## BPS

byuu's successor to UPS: a small instruction stream, which is what lets it
describe data that moved.

```
"BPS1"
VLV   source size
VLV   target size
VLV   metadata size
n×    metadata (UTF-8, usually XML; no terminator)
actions, until (patch length - 12):
    VLV   data — command = data & 3, length = (data >> 2) + 1
      0  SourceRead  take `length` bytes from the source at the output's own offset
      1  TargetRead  `length` literal bytes follow in the patch
      2  SourceCopy  a signed VLV moves a cursor in the source; take from there
      3  TargetCopy  the same, over the output written so far
footer, three little-endian UInt32:
    CRC-32 of the source, of the target, and of the patch ahead of it
```

Three things decide whether an implementation is right:

- **A signed VLV is `sign | (magnitude << 1)`** — the low bit is the sign, not
  part of the value. The cursor it moves is relative to the last copy *of that
  kind*, not to the output position, and the two cursors are independent and
  persist across actions.
- **TargetCopy may overlap its own output.** A copy of 300 bytes from one byte
  back is how the format spells a repeat, so it has to be copied a byte at a
  time; a block move would read bytes that aren't written yet.
- **The actions must fill the target exactly.** Anything else is a malformed
  patch, and checking it is what catches a stream that desynchronised earlier.

The VLV is UPS's, unchanged.

**Applying a BPS patch builds the whole target in memory**, and that is the
format rather than a shortcut: a TargetCopy can take its bytes from any earlier
part of the output, so answering "what is byte N" can depend on an arbitrarily
long chain of earlier output. Every tool that reads the format does the same.

| file | role |
|---|---|
| `BPSPatch` | actions, parse, and the linear plan |
| `BPSPatchedView` | the target, built once on first read |
| `BPSPatchView` | the patch itself, over the target |
| `BPSPatchCodec` | `PatchCodec` conformance |

---

## xdelta (VCDIFF, RFC 3284)

What an `.xdelta` file holds, and what xdelta3 writes.

```
header:  D6 C3 C4 00
         Hdr_Indicator                 VCD_DECOMPRESS 1, VCD_CODETABLE 2, VCD_APPHEADER 4
         [secondary compressor id]     when VCD_DECOMPRESS
         [code table data]             when VCD_CODETABLE
         [app header length + bytes]   when VCD_APPHEADER
windows, to the end of the file:
         Win_Indicator                 VCD_SOURCE 1, VCD_TARGET 2, (xdelta3) VCD_ADLER32 4
         [source segment length, position]
         length of the delta encoding
         target window length
         Delta_Indicator               per-section secondary compression
         data / instruction / address section lengths
         [adler32 of the target window] xdelta3's extension
         the three sections
```

**Its integers are not UPS's.** Base 128, most significant digit first, with the
high bit set on every byte *but* the last — the opposite convention in both
respects. `123456789` is `BA EF 9A 15`.

**An instruction byte is an index into a code table, and each entry holds up to
two instructions.** That is the format's compression: "a few new bytes then a
copy" is one byte. A size of zero in the table means the real size follows in
the instruction stream. The default table's 256 entries are generated from the
RFC's rules rather than transcribed, and the index arithmetic is the check that
the shape is right: 1 RUN + 18 ADD + 144 COPY (9 modes × 16) = 163, then 72
ADD+COPY (modes 0-5 × 4 add sizes × 3 copy sizes) + 12 (modes 6-8, copy size 4)
= 247, then 9 COPY+ADD = 256.

**A COPY's address is usually relative to something.** Two caches — four "near"
slots and three 256-entry "same" rows — let an address be spelled as an offset
from a recent one or as a single byte. Both are reset per window and **both are
updated after every address whatever mode produced it**; a reader that only
updates them for cache modes drifts out of step with the writer and then decodes
addresses that are wrong but plausible.

**A window's addresses span its source segment followed by the part of that
window already written**, so a copy can cross the boundary, and one taking bytes
it is still writing is a repeat. Windows are otherwise independent, which is why
applying one of these streams: only the window a read lands in has to be
decoded, and the last one is kept.

**VCD_ADLER32 is xdelta3's, not the RFC's.** It adds four bytes after the
section lengths. Skip it and every window after the first is read from the wrong
offset — which is exactly how a first attempt at this read window two of a real
patch as indicator `0x88`. It is verified when present and never written, since
a strict reader would reject a window flag it does not know.

Refused by name rather than misread: secondary compression (xdelta3's `-S`), a
custom code table, and a window whose segment comes from the target
(`VCD_TARGET`) — reading one means holding every byte decoded so far.

The writer searches the source with a hash index, sampled every `stride` bytes
so the index stays bounded; the stride grows with the source, which finds fewer
short matches and all the long ones. It emits three instruction codes, each
carrying its size, with every address in SELF mode — so nothing it writes
depends on the caches' state. It holds the patch it is building, because a
window's length isn't known until its matches are found.

| file | role |
|---|---|
| `VCDIFFInteger` | the format's own integer encoding |
| `VCDIFFCodeTable` | the default code table and the instruction model |
| `VCDIFFAddressCache` | the near and same caches |
| `VCDIFFPatch` | header and window parsing |
| `VCDIFFWindowDecoder` | one window's instruction stream |
| `VCDIFFPatchedView` | the output, a window at a time |
| `VCDIFFEncoder` | the match search and the window writer |
| `VCDIFFPatchCodec` | `PatchCodec` conformance |

---

## Sizes, measured

**Measured on a real pair** — two 199,163,904-byte GameCube demo images that
differ in exactly one byte (a game-ID mod), patched and re-applied through the
operations, every output byte-identical to the target:

| format | patch |
|---|---:|
| IPS | 14 bytes |
| UPS | 27 bytes |
| BPS | 32 bytes |
| xdelta | 849 bytes |

xdelta is the largest here because its patch is a sequence of windows, each
carrying a header and at least one instruction whatever the window contains;
the others say "one byte changed" once. It was 148,250 bytes until the source
index was sampled at a power-of-two stride: a window starts at a multiple of the
window size, so any other stride leaves most windows beginning a few dozen bytes
before their first sampled offset, and an unchanged window pays for those bytes
as literals.

---

## Validation

By cross-check, not round trip: a writer and a reader that are wrong in matching
ways pass a round trip. For each format the test target carries an independently
transcribed reader — `ReferenceUPSPatcher`, `ReferenceIPSPatcher`,
`ReferenceBPSPatcher`, `ReferenceVCDIFFDecoder`, the last of which derives the
code table arithmetically from the RFC's ranges rather than building it in the
same order the production code does. Every patch the writers produce is applied
through both. The on-wire layouts are also pinned against hand-authored bytes,
including the cases that catch a forgotten hunk terminator, a missed IPS
terminator offset, and a BPS copy that overlaps itself.

**Against other people's patches** (`PatchRealCorpusTests`, which skips without
a corpus; `GODDESS_PATCH_CORPUS` points at a folder,
`GODDESS_PATCH_CORPUS_ALL` includes disc-sized ones):

- **UPS — 7 release patches** parse and pass their own stored CRC-32, and the
  two small enough to apply in memory come out identical through both appliers.
  Beyond that, one full end-to-end run: XG Remix v1.15's own 373 MB patch
  applied to a real 1,459,978,240-byte Pokémon XD (US) ISO produced exactly the
  CRC-32 the patch declares for its target, in 18 s.
- **IPS — 153 release patches**, 26,228 records including 10,138 run records,
  applied identically by both appliers.
- **xdelta — one real patch** (a 64 MB DS ROM translation, 8 windows, every
  window checksummed): every window decodes to exactly the length it declares,
  consuming its sections exactly. The ROM it was cut against is not on hand, so
  the bytes themselves are unverified.
- **BPS — nothing.** No third-party BPS patch is available here, so that format
  rests on its specification and its reference reader alone.
