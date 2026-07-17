import Structs
import GoDFoundation

/// Struct definitions for Colosseum save-slot sections. Field offsets
/// cross-referenced against PKHeX's `SAV3Colosseum.cs` and the legacy
/// GoD tool's `XGSaveManager.swift` constants. Colo's slot has no
/// in-slot TOC, so each section's length comes from the engine —
/// concretely, from a registered `StructDefinition` looked up via
/// `ColosseumEngine.Data.sectionStructTypes`. That requires every
/// Colo section to have a struct binding, even when its internal
/// layout isn't fully known yet.
///
/// Sections that aren't yet broken down internally use placeholder
/// padding for the unknown remainder. As reverse-engineering
/// progresses, those padding regions get replaced with named fields
/// in place; the section's total byte length stays the same so
/// existing dumps round-trip.
///
/// Layout summary (slot-relative):
///
///     +0x0000   slot header   — 8 bytes (slot magic + counter)
///     +0x0008   Config         — 0x70 bytes
///     +0x0078   Trainer1       — 0xB18
///     +0x0B90   PCBox          — 0x6DEC (3 boxes × 0x24A4)
///     +0x797C   BattleData     — 0x7F4   (unknown region)
///     +0x8170   Daycare        — 0x140
///     +0x82B0   StrategyMemo   — 0xB10
///     +0x8DC0   Tail           — 0x15240
///
public extension ColosseumStructDefaults {

    // MARK: - Pokemon

    /// Colo Pokemon record (CK3 in PKHeX). 312 bytes per
    /// `PokeCrypto.SIZE_3CSTORED`. Field layout (species, stats,
    /// moves, IVs, EVs, shadow data, etc.) is a separate
    /// reverse-engineering effort — for now expose the raw bytes
    /// so party/box arrays at least have the correct length.
    static let savePokemonStruct = StructMap(
        name: "ColoPokemon",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [.padding(length: 0x138)]
    )

    // MARK: - Section 0: Config

    /// Colo save section 0 (slot+0x08, length 0x70). Per PKHeX's
    /// `SAV3Colosseum.cs`:
    ///   - `gcGameIndex`     @ +0x00 (u8)
    ///   - `currentRegion`   @ +0x01 (u8)
    ///   - `originalRegion`  @ +0x02 (u8)
    ///   - `gcLanguage`      @ +0x03 (u8)
    ///   - `playTimeSeconds` @ +0x20 (f32 BE — TimeSpan from seconds)
    static let saveConfigStruct = StructMap(
        name: "ColoSaveConfig",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "gcGameIndex"),
            .uint8(name: "currentRegion"),
            .uint8(name: "originalRegion"),
            .uint8(name: "gcLanguage"),
            .padding(length: 0x1C),                     // +0x04..0x20
            .losslessFloat(name: "playTimeSeconds"),    // +0x20  (f32 BE)
            .padding(length: 0x4C),                     // +0x24..0x70
        ]
    )

    // MARK: - Section 1: Trainer1

    /// Colo save section 1 (slot+0x78, length 0xB18). Per PKHeX:
    ///   - OT name           @ +0x000 (20 bytes / 10 chars `gsColo`)
    ///   - OT2               @ +0x014 (20 bytes / 10 chars `gsColo`)
    ///   - SID16             @ +0x02C (u16)
    ///   - TID16             @ +0x02E (u16)
    ///   - Party (6 × CK3)   @ +0x030 (6 × 0x138 = 0x750)
    ///   - Gender            @ +0x780 (u8)
    ///   - Money             @ +0x784 (u32)
    ///   - Coupons           @ +0x788 (u32)
    ///   - CouponsTotal      @ +0x78C (u32)
    ///   - RUI_Name          @ +0xAC2 (20 bytes / 10 chars `gsColo`)
    /// Total length matches the section's hardcoded 0xB18 size.
    static let saveTrainer1Struct = StructMap(
        name: "ColoTrainer1",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            // 10 chars × 2 bytes (UTF-16 BE), zero-padded.
            .string(name: "OT",      format: .gsColo, length: 10),  // +0x000  (20 bytes)
            .string(name: "OT2",     format: .gsColo, length: 10),  // +0x014  (20 bytes)
            .padding(length: 4),                                    // +0x028..0x02C
            .uint16(name: "SID16"),                                 // +0x02C
            .uint16(name: "TID16"),                                 // +0x02E
            .array(name: "party", count: 6, of: .subStruct(name: "ColoPokemon")),
            .uint8(name: "gender"),                                 // +0x780
            .padding(length: 3),                                    // +0x781..0x784
            .uint32(name: "money"),                                 // +0x784
            .uint32(name: "coupons"),                               // +0x788
            .uint32(name: "couponsTotal"),                          // +0x78C
            .padding(length: 0x332),                                // +0x790..0xAC2
            .string(name: "RUI_Name", format: .gsColo, length: 10), // +0xAC2  (20 bytes)
            .padding(length: 0x42),                                 // +0xAD6..0xB18
        ]
    )

    // MARK: - Section 2: PCBox (3 storage boxes)

    /// One Colo PC box: 16-byte name + 4 unknown bytes + 30 × CK3.
    /// Total 0x24A4. Per PKHeX `SAV3Colosseum.cs`, box stride is
    /// `0x24A4` and box names live in the first 16 bytes.
    static let saveBoxStruct = StructMap(
        name: "ColoBox",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .string(name: "name", format: .gsColo, length: 8),       // +0x00..0x10
            .padding(length: 4),                                      // +0x10..0x14
            .array(name: "pokemon", count: 30, of: .subStruct(name: "ColoPokemon")),
        ]
    )

    /// Colo save section 2 (slot+0xB90, length 0x6DEC). Three
    /// `ColoBox` entries packed back-to-back. Total 3 × 0x24A4 =
    /// 0x6DEC, matches the section length exactly.
    static let savePCBoxStruct = StructMap(
        name: "ColoPCBox",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "boxes", count: 3, of: .subStruct(name: "ColoBox")),
        ]
    )

    // MARK: - Section 3: BattleData (unknown)

    /// Unknown region between PCBox end (0x797C) and Daycare start
    /// (0x8170). Likely Battle Mode / registered party data per the
    /// legacy GoD tool's `kSaveFileRegisteredPokemonStartOffset`,
    /// but unverified — placeholder name + size only.
    static let saveBattleDataStruct = StructMap(
        name: "ColoBattleData",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [.padding(length: 0x7F4)]
    )

    // MARK: - Section 4: Daycare

    /// Colo save section 4 (slot+0x8170, length 0x140). Per PKHeX:
    ///   - occupied          @ +0x00 (u8)
    ///   - depositLevel      @ +0x01 (u8)
    ///   - depositedEXP      @ +0x04 (u32 BE)
    ///   - pokemon (CK3)     @ +0x08
    /// Total 0x08 + 0x138 = 0x140, matches the section length.
    static let saveDaycareStruct = StructMap(
        name: "ColoDaycare",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "occupied"),
            .uint8(name: "depositLevel"),
            .padding(length: 2),
            .uint32(name: "depositedEXP"),
            .subStruct(name: "pokemon", typeName: "ColoPokemon"),
        ]
    )

    // MARK: - Section 5: StrategyMemo (placeholder)

    /// Colo save section 5 (slot+0x82B0, length 0xB10) — Pokédex /
    /// strategy memo entries. Internal layout TBD.
    static let saveStrategyMemoStruct = StructMap(
        name: "ColoStrategyMemo",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [.padding(length: 0xB10)]
    )

    // MARK: - Section 6: Tail (large unknown region)

    /// Trailing slot region after StrategyMemo — runs from 0x8DC0
    /// to 0x1E000 minus the cipher's 0x20-byte hash trailer. Holds
    /// JP bonus-disc flags (`Data[0x1C118..0x1C11A]`) and large
    /// unstructured payload areas; full layout TBD.
    static let saveTailStruct = StructMap(
        name: "ColoSaveTail",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [.padding(length: 0x15240)]
    )
}
