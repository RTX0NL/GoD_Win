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
  `slot[0x08..0x18)`, in the disasm's "low halfword first, then
  high halfword" pair-swapped order:
    - sum lane 0 → slot[0x14..0x17] (low @ 0x14, high @ 0x16)
    - sum lane 1 → slot[0x10..0x13] (low @ 0x10, high @ 0x12)
    - sum lane 2 → slot[0x0C..0x0F] (low @ 0x0C, high @ 0x0E)
    - sum lane 3 → slot[0x08..0x0B] (low @ 0x08, high @ 0x0A)
- Internal-consistency tests pass (`XDSaveCipherTests`):
  encrypt/decrypt symmetry, tag-corruption detection, key-seed
  sensitivity, determinism.

Open:
1. **Tail loop** — the 48 bytes at `slot[0x27FD0..0x27FFF]` aren't
   covered by the main 0x4FF9-iteration loop. We currently leave
   them untouched; whether the game expects them encrypted or zeroed
   wants checking against a real save.
2. **Fixture for end-to-end validation** — without a real encrypted
   XD `.gci` we can't prove byte-for-byte compatibility with the
   game's output. Self-inverse symmetry is verified, but a real
   fixture would catch any subtle bug (e.g. wrong tag layout, tail
   handling) that survives a synthetic round-trip. Tracked as task
   #12.

The cipher is wired into `xdSaveDump` / `xdSaveBuild` and runs by
default in projects produced by `Project.setup(gci:)`. Users with
slots already decrypted by external tools (`gcitool`, `pbrsavetool`)
can pass `decrypted: true` on the dump/build configs to bypass the
in-tree cipher.
