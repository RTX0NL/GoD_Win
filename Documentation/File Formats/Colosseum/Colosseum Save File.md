# Pokémon Colosseum Save File

This is the working brief on Colosseum's `.gci` save format. It mirrors
the structure of `Documentation/File Formats/XD/XD Save Encryption.md`
for XD, but most of the encryption-side detail is still TBD — see
"Status / open work" below.

## What's confirmed

### Container

Colo and XD share the on-card / GCI envelope:

- File body size: `0x56000` (43 × 0x2000 blocks).
- Body framing: banner (0x2000) + hdr0 (0x2000) + hdr1 (0x2000) +
  slotA (0x28000) + slotB (0x28000), per
  `Documentation/Assembly Analysis/Overview/Save System.md` §1.

This is why `GSSaveCardFile` in `GeniusSonority/File Formats` works
for both games — the splitter is GS-specific, not XD-specific.

### GCI gamecodes

- `GC6E` — Colosseum US
- `GC6J` — Colosseum JP
- `GC6P` — Colosseum PAL/EU

(Detected by the `Project.setup(gci:)` dispatch in
`ProjectSetupGCI.swift`.)

### Slot layout differs from XD

The legacy GoD tool (`Objects/managers/XGSaveManager.swift`) lists the
following Colo-specific offsets (per-slot, post-decryption):

| Field | Colo offset | XD offset (reference) |
|-------|------------:|---------------------:|
| Player name | `0x078` | `0x148` |
| Player SID  | `0x0A4` | `0x174` |
| Player TID  | `0x0A6` | `0x176` |
| Party start | `0x0A8` | `0x178` |
| PC boxes start | `0x0B90` | `0xAD8` |
| Registered Pokémon | `0x19744` | — |
| PC items | `0x797C` | `0x1F9C8` |
| Bag items | — | `0x124B0` |
| Pokémon record size | `0x138` | `0xC4` |
| PC boxes count | 3 | 8 |

So the on-slot sub-block layout is **completely different** from XD's
TOC scheme. Colo doesn't appear to use the same `+0x38..+0x98` 24-entry
TOC that XD does — the legacy code addresses sub-blocks by hard-coded
absolute offsets instead.

This means `XDSaveSlot` from `Sources/Shared/Core/Engines/XD/SaveData/`
is **not reusable** for Colo. Colo needs its own `ColosseumSaveSlot`
type with its own offset table.

### Slot magic / header

Unverified, but the §1 layout (`01 01 01` magic + counter at +0x04)
likely applies — it lives in the unencrypted CARD header sectors, not
inside the slot. Worth confirming against an actual Colo save.

## Status / open work

What's known:
- File container shape (matches XD).
- Per-region gamecodes for routing.
- High-level sub-block offsets from the legacy tool.
- The sub-block layout is unique to Colo; XD's TOC scheme does not
  carry over.

What's not yet known:
1. **Colo memcard function entry points.** The Colo PowerPC
   disassembly under `scripts/Disassembly-Colosseum` is unsymbolised
   (`zz_<addr>_.s` filenames). Even cross-referencing `__CARDWriteAsync`
   / `__CARDReadAsync` callers is a manual hunt because the surrounding
   code is anonymous.
2. **Encryption algorithm.** Multi-pronged fingerprint search ruled
   out an exact-byte match to XD's cipher in the Colo disasm:
   - XD's SBOX `[0x43, 0x29, 0x17, 0x13]` does not appear as a
     16-byte data file under `data*/@*.bin`, nor as a contiguous
     8-byte sequence in any text1 file.
   - XD's `0x4FF9` / `0x4FFA` loop-count constants don't appear in
     any Colo text1 file.
   - The XD encrypt/decrypt instruction profile (~5 `rlwinm`,
     ~10–15 `rlwimi`, 1–2 `bdnz`, 200–250 lines, paired
     `addi r29, r29, 0x8` + `addi r30, r30, 0x4` lane stride) does
     not match any Colo function in the same size/profile range.
   - The legacy GoD tool also delegates Colo decryption to `gcitool`
     (same as XD) — they didn't reverse-engineer it either.
   So either Colo uses a substantially different cipher (different
   SBOX, different loop length, different shape), or the encryption
   path is split across multiple unsymbolised functions in a way
   our fingerprint search can't catch. **Resolution requires either
   Colo symbol-map data or a real `.gci` save to bisect against.**
3. **Slot picker / counter location.** Probably the same as XD given
   shared CARD framing, but unverified.
4. **Save sub-block identification.** Beyond the high-level field
   table above, no exhaustive sub-block boundary list exists. Future
   work would lift the legacy tool's offset constants into
   `ColosseumSaveSlot`'s sub-block enum.

### What would unblock the cipher hunt

In rough order of usefulness:
- **A real encrypted Colo `.gci` from a saved game.** With one in hand
  we can: dump the slots, eyeball whether the bytes look random
  (encrypted) or structured (plaintext); try XD's cipher on it and
  see if `01 01 01` magic falls out at slot[0..2]; bisect short
  experiments against known-good plaintext like the player name field
  at slot+0x78.
- **A Colo `.map` symbol file.** Even a partial map covering
  `_memcard_*` / `_memcardJobMain` would let us walk straight to the
  cipher function instead of fingerprint-fishing.
- **The original Colo dol with debug strings preserved**, if any
  build of the game has them.

## How we ship Colo support today

`ColoSaveOps` mirrors `XDSaveOps` but does only the safe passthrough:

- `dumpColosseumSave` reads `slot-a.bin` / `slot-b.bin` from the
  unpacked GCI body, parses the plaintext slot magic + counter, and
  emits each slot as `Slot N/raw-slot.bin` plus a `slot-metadata.json`.
- `buildColosseumSave` reads each `raw-slot.bin` back and writes it
  out unchanged.

No sub-block extraction, no encryption — same shape as XD's current
state. The two ops diverge once we (a) implement the encryption and
(b) carve the Colo slot into named sub-blocks. Until then the project
setup keeps these ops disabled-by-default in the generated configs.

## References

- Legacy tool: `/Users/stars/Documents/Projects/GoD Tool/Objects/managers/XGSaveManager.swift`
  (Colo offset constants, `decryptedSaveSlot` consumption pattern).
- `Documentation/Assembly Analysis/Overview/Save System.md` (XD-side
  reference, file-container layout — applies to Colo too).
- `Documentation/File Formats/XD/XD Save Encryption.md` (XD encryption
  brief — Colo's may follow the same shape).
- `scripts/Disassembly-Colosseum/text1/zz_800ff970_.s` (one of the
  files where `__CARDExiHandler` is referenced — possible entry point
  into the memcard pipeline).
