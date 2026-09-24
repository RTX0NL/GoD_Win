# XD Save Encryption — additive stream cipher

This is the working brief on Pokémon XD's save-slot encryption,
synthesised from `_memcard_Decryption__FPv.s`,
`_memcard_Encryption__FPv.s`, and `_memcardDuplicateSaveData_multi__FPv.s`
under `scripts/Disassembly-XD/text1/memcard/`. It supersedes the §4
sketch in `Documentation/Assembly Analysis/Overview/Save System.md`
where the two disagree.

## Where it applies

- Each slot (slot A and slot B) is a 0x28000-byte buffer.
- The first 8 bytes are plaintext (magic + reserved + counter).
- The next 0x4FF9 × 8 = 163,784 bytes are encrypted as 8-byte blocks.
- A 48-byte tail (`slot[0x27FD0..0x27FFF]`) is handled by a separate
  loop — TBD whether it is also encrypted.

## State

The cipher carries an 8-byte (4 × u16) **key state**, kept at
`r13 - 0x4740` in the live game. At the start of every encrypt or
decrypt call, the four halfwords are loaded directly from `slot[0..7]`:

```
key[0] = slot[0..1]       # part of the magic
key[1] = slot[2..3]       # reserved byte + first counter byte
key[2] = slot[4..5]       # counter middle two bytes
key[3] = slot[6..7]       # counter low bytes
```

So the plaintext slot header *is* the per-save key seed. Saving with
`HSD_Rand`-rolled bytes in those positions (per
`_memcardDuplicateSaveData_multi__FPv` lines 22–31) is what produces
fresh ciphertext on every save while still letting
`memcardExamineHeader` pick the newer slot before decrypting.

## SBOX

Despite the §4 sketch describing a "256-bit substitution table", the
real lookup table at symbol `@3110` is just **four u32 constants**:

| Index | Hex | Decimal |
|------:|----:|--------:|
| 0 | `0x00000043` | 67 |
| 1 | `0x00000029` | 41 |
| 2 | `0x00000017` | 23 |
| 3 | `0x00000013` | 19 |

(All four are small primes. The legacy tool's encryption code uses the
same constants — see `XGSaveManager` in the legacy repo for the
equivalent values.)

The table is loaded once per call (`addi r12, r5, @3110@l`) and read
as `lwz r11, 0x0(r12)`, `lwz r10, 0x4(r12)`, etc.

## Loop shape

The encrypt and decrypt loops are mirror images. Each iteration
processes one 8-byte block (4 lanes × u16) of the slot. Per iteration,
for each lane `j` in 0..3:

1. Read the lane halfword `h` from the slot.
2. Encrypt: `h = h + key[j]`.
   Decrypt: `h = h - key[j]`.
3. Write `h` back to the slot.

Then the key state is updated using the four SBOX values plus the four
just-processed `h` values, via a sequence of `rlwinm` / `rlwimi`
nibble-shuffles. The exact shuffle is TBD (see below).

`r29` walks the lane-0 byte offset (starts at 8, increments by 8 per
iteration); `r30` walks the lane-{1,2,3} index in halfword-stride
units of 4 (starts at 4, increments by 4). Loop count is fixed at
`0x4FF9` iterations.

## Running-sum tag

The encrypt direction additionally accumulates four `u32` running
sums into `slot[0x10..0x1F]` after the loop completes. The decrypt
direction recomputes these and returns `1` only if all four match
the values it found there. That's how the game distinguishes "wrong
key" from "right key, valid slot" without trusting any in-band magic
inside the encrypted payload.

The accumulation runs in the tail block at `lbl_801C9FF8` and
following — it walks `slot[0x14], slot[0x16], slot[0x10], slot[0x12]`
(re-reading the same 8-byte tag area into four u32 lanes) and folds
each subsequent halfword into the running totals via `add` chains.

## Status

Done:
- Constants captured (`@3110.bin` → 4 × u32 SBOX above).
- Slot layout corrected on `Save System.md`.
- Loop shape and iteration count identified.
- Initialization sequence (slot[0..7] → key state) verified.
- Key-update bit-splicing translated line-for-line into Swift
  (`Sources/Shared/Core/Engines/XD/SaveData/XDSaveCipher.swift`).
  The encrypt and decrypt sequences in
  `_memcard_{En,De}cryption__FPv.s` use the *same* 31-instruction
  rlwinm/rlwimi block (lines 68–106 of the decrypt file, 159–197 of
  the encrypt file) — confirmed by side-by-side comparison.
- Running-sum tag location confirmed: 4 × u32 stored at
  **`slot[0x10..0x20)`**, low halfword first, with the lanes written in
  reverse order:
    - sum lane 3 → slot[0x10..0x13] (low @ 0x10, high @ 0x12)
    - sum lane 2 → slot[0x14..0x17]
    - sum lane 1 → slot[0x18..0x1B]
    - sum lane 0 → slot[0x1C..0x1F]

  `slot[0x08..0x10)` is the **plaintext key seed**, not tag storage —
  an earlier revision of this list said the tags lived there, which
  contradicted the prose above and the implementation. The coverage the
  sums coverage *starts* at 0x08 so the key seed is included in what is
  summed, which is probably where the confusion came from.
- Internal-consistency tests pass (`XDSaveCipherTests`):
  encrypt/decrypt symmetry, tag-corruption detection, key-seed
  sensitivity, determinism.

Open:
1. **Tail loop** — the 48 bytes at `slot[0x27FD0..0x27FFF]` aren't
   covered by the main 0x4FF9-iteration loop. We currently leave
   them untouched; whether the game expects them encrypted or zeroed
   wants checking against a real save.
2. ~~**Fixture for end-to-end validation**~~ — **closed.** 42 real XD
   saves across US, PAL and JP decrypt with all four tags matching and
   re-encrypt cleanly, and the decrypted slot's declared sections come
   back byte-identical on every one. A wrong tag layout or a wrong lane
   order would fail the tag check on the first real save, so the layout
   above is validated against the game's own output rather than only
   against itself. See `Documentation/Save-Round-Trip-Audit-2026-09.md`.

3. **No rebuilt save has been booted in an emulator.** The tags
   validate and the sections round-trip, but nothing has yet confirmed
   the game itself accepts a rebuilt slot.

## Where the tags live is engine data

`XDSaveSlot.Layout.checksumOffset` is an optional `Int`. The stock
engine carries the retail `0x10` explicitly, so ordinary saves are
tagged exactly as described above. A modified save format can move the
tag region and the encrypt path will clear and rewrite the tags where
they actually live.

**`nil` means the format has no checksum**, so none is written and
`decrypt` returns `nil` for "not checked" rather than a pass or a fail.
It does *not* mean "fall back to 0x10": writing four sums at a guessed
offset would corrupt whatever lives there. A relocated region has to
stay inside `cipherRange` or the cipher throws, since the game reads
its tags from inside the encrypted range.

## Status of the surrounding header

The 0xA8 bytes before the sub-blocks are now typed as
`XDSaveSlotHeader` and dumped as `slot-header.json` — magic, save
counter, the key seed at `0x08`, the tag region at `0x10`, the 16 × u16
sub-block sizes at `0x20` and the 16 offsets at `0x40` (each a `u32`
stored low half first). Layout and measurements in
[`XD Save Slot - From-Scratch Rebuild Plan.md`](./XD%20Save%20Slot%20-%20From-Scratch%20Rebuild%20Plan.md).

The cipher is wired into `xdSaveDump` / `xdSaveBuild` and runs by
default in projects produced by `Project.setup(gci:)`. Users with
slots already decrypted by external tools (`gcitool`, `pbrsavetool`)
can pass `decrypted: true` on the dump/build configs to bypass the
in-tree cipher.
