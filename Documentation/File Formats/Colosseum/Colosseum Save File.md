# Pokémon Colosseum Save File

Colosseum's `.gci` save is implemented and round-trips byte-identically:
20 of 20 real saves across US, PAL and JP rebuild to the original bytes
with the source file deleted first, so the rebuild derives everything
rather than copying it forward. See
`Documentation/Plans/Save-Round-Trip-Audit-2026-09.md`, an untracked
working document.

This brief is the Colosseum-specific detail. The envelope it sits in —
the directory entry, the banner, the animated icon and the comment
strings, all of which are generic to any GameCube title — is in
[`GCI - GameCube Memory Card Save.md`](../Shared/GCI%20-%20GameCube%20Memory%20Card%20Save.md).

## Container

Colosseum's body is **`0x60000` (48 × 0x2000 blocks) with three
`0x1E000` slots** — not XD's `0x56000` with two `0x28000` slots. An
earlier revision of this document claimed the two games shared a body
shape; they do not, and `ColoSaveCardFile` exists precisely because of
it.

| Region | Offset | Length |
|---|---|---|
| card metadata | `0x00000` | `0x6000` |
| slot 1 | `0x06000` | `0x1E000` |
| slot 2 | `0x24000` | `0x1E000` |
| slot 3 | `0x42000` | `0x1E000` |

That split is declared as engine data
(`GeniusSonorityEngine.Data.colosseumSaveCard`), not hardcoded in the
operations. The metadata region is identical in shape to XD's: the two
comment strings at `0x0`, the banner and icon frames from `0x40` to
`0x3A40`, a `u32` word sum of everything before it at `0x3A40`, then
zero to the first slot.

### GCI gamecodes

- `GC6E` — Colosseum US
- `GC6J` — Colosseum JP
- `GC6P` — Colosseum PAL/EU

One engine serves all three: the 7 sections have the same names,
offsets and lengths on every region, which is why Colosseum needs no
per-region struct variants the way XD does.

## Slot header

The 8 bytes before the sections, typed as `ColoSaveSlotHeader`
(`Colosseum/Structs/entries/SaveDataStructs.swift`) and dumped as
`slot-header.json`:

| Offset | Field | Observed on 8 real saves |
|---|---|---|
| `0x00` | `magic` | `01 01 00` on every one |
| `0x03` | `reserved` | `0` on every one |
| `0x04` | `counter` | small `u32` (2…77), picks the latest slot |

> **Corrected.** An earlier revision guessed `01 01 01` by analogy with
> XD and called it unverified. Measured, byte 2 is `00` on every
> Colosseum save and `01` on every XD save. It is also **not** the
> gamecode, which is what an 8-byte header starting a `GC6E` save
> invites you to assume — the existing synthetic test fixture writes
> `"GC6E"` there and is misleading on that point.

## Slot layout

The slot is addressed by fixed offsets rather than XD's 16-entry table
of contents, so `XDSaveSlot` is not reusable and `ColosseumSaveSlot`
exists separately. Its 7 sections all tile their structs exactly, so
all 7 dump as editable JSON on every region, with none demoted.

Legacy offsets from the original tool's `XGSaveManager.swift`, kept as
the historical reference that seeded the layout:

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

## Encryption

Solved. `ColoSaveCipher` implements the PKHeX-aligned SHA-1 XOR
cascade; the latest slot is decrypted at dump and re-encrypted from
scratch at build. The "cipher hunt" section this document used to carry
— asking for a real encrypted save to bisect against — is obsolete.

## What ships today

`ColoSaveOps` dumps the **latest slot only**, decrypted, as per-section
artifacts plus `slot-header.json` and `slot-metadata.json`. The build
reconstructs that one slot from scratch from those artifacts,
re-encrypts it, and leaves the other two slots byte-untouched. The ops
are enabled by default in generated configs.

A blank never-saved card is rejected at dump with `noValidSlot` rather
than being "parsed" into a save whose checksums are then valid. All 13
blank cards in the audit corpus are refused.

## References

- `Documentation/Plans/Save-Round-Trip-Audit-2026-09.md` — the round-trip measurements (untracked).
- [`GCI - GameCube Memory Card Save.md`](../Shared/GCI%20-%20GameCube%20Memory%20Card%20Save.md) — the envelope, generic to every GameCube game.
- [`XD Save Encryption.md`](../XD/XD%20Save%20Encryption.md) — XD's cipher, a different algorithm from Colosseum's.
- `Documentation/Assembly Analysis/Overview/Save System.md` — XD-side disassembly notes; its card-layout table applies to both games.
- Legacy tool: `Objects/managers/XGSaveManager.swift` (the Colo offset constants above).
