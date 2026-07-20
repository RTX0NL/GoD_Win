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

    /// One move slot inside a `ColoPokemon`. 4 bytes: move id + PP +
    /// PP-Ups. Matches PKHeX CK3's `0x78`-region move layout.
    static let saveWazaStruct = StructMap(
        name: "ColoWaza",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "moveId"),        // +0x0
            .uint8(name: "pp"),             // +0x2 current PP
            .uint8(name: "ppUpCount"),      // +0x3 PP Ups applied (0..3)
        ]
    )

    /// Colo save-side Pokémon record — **0x138 bytes (312)**, the CK3
    /// format (`PokeCrypto.SIZE_3CSTORED`). Field offsets from PKHeX's
    /// `CK3.cs`. Larger than XD's XK3 (0xC4) chiefly because Colosseum
    /// reserves three separate 22-byte name buffers (OT + a display
    /// nickname + the stored nickname) and stores stats/IVs/EVs as
    /// 16-bit each. All multi-byte fields are big-endian. Undocumented
    /// gaps (incl. the 0xE0.. shadow/battle tail) are padding so rows
    /// round-trip byte-for-byte regardless of field naming.
    static let savePokemonStruct = StructMap(
        name: "ColoPokemon",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "species"),                   // +0x00 internal species index
            .padding(length: 2),                        // +0x02..0x04
            .uint32(name: "pid"),                       // +0x04 personality value
            .uint8(name: "version"),                    // +0x08 origin version
            .uint8(name: "currentRegion"),              // +0x09
            .uint8(name: "originalRegion"),             // +0x0A
            .uint8(name: "language"),                   // +0x0B
            .uint16(name: "metLocation"),               // +0x0C
            .uint8(name: "metLevel"),                   // +0x0E
            .uint8(name: "ball"),                       // +0x0F
            .uint8(name: "otGender"),                   // +0x10
            .padding(length: 3),                        // +0x11..0x14
            .uint16(name: "SID16"),                     // +0x14
            .uint16(name: "TID16"),                     // +0x16
            .string(name: "otName", format: .gsColo, length: 11),          // +0x18..0x2E (22)
            .string(name: "nicknameDisplay", format: .gsColo, length: 11), // +0x2E..0x44 (22)
            .string(name: "nickname", format: .gsColo, length: 11),        // +0x44..0x5A (22)
            .padding(length: 2),                        // +0x5A..0x5C
            .uint32(name: "exp"),                       // +0x5C total EXP
            .uint8(name: "level"),                      // +0x60
            .padding(length: 0x17),                     // +0x61..0x78
            .array(name: "moves", count: 4, of: .subStruct(name: "ColoWaza")),  // +0x78..0x88
            .uint16(name: "heldItem"),                  // +0x88 itemDataId
            .uint16(name: "currentHp"),                 // +0x8A
            .uint16(name: "maxHp"),                     // +0x8C computed stats
            .uint16(name: "phyAtk"),                    // +0x8E
            .uint16(name: "phyDef"),                    // +0x90
            .uint16(name: "speAtk"),                    // +0x92
            .uint16(name: "speDef"),                    // +0x94
            .uint16(name: "nimbleness"),                // +0x96 Speed
            .uint16(name: "maxHpEV"),                   // +0x98 EVs (16-bit each)
            .uint16(name: "phyAtkEV"),                  // +0x9A
            .uint16(name: "phyDefEV"),                  // +0x9C
            .uint16(name: "speAtkEV"),                  // +0x9E
            .uint16(name: "speDefEV"),                  // +0xA0
            .uint16(name: "nimblenessEV"),              // +0xA2
            .uint16(name: "hpIV"),                      // +0xA4 IVs (16-bit each)
            .uint16(name: "atkIV"),                     // +0xA6
            .uint16(name: "defIV"),                     // +0xA8
            .uint16(name: "spAtkIV"),                   // +0xAA
            .uint16(name: "spDefIV"),                   // +0xAC
            .uint16(name: "speedIV"),                   // +0xAE
            .uint16(name: "friendship"),                // +0xB0
            .uint8(name: "contestCool"),                // +0xB2 contest stats (legacy GoD names)
            .uint8(name: "contestBeauty"),              // +0xB3
            .uint8(name: "contestCute"),                // +0xB4
            .uint8(name: "contestSmart"),               // +0xB5
            .uint8(name: "contestTough"),               // +0xB6
            .uint8(name: "contestRankCool"),            // +0xB7 contest achievements / ranks
            .uint8(name: "contestRankBeauty"),          // +0xB8
            .uint8(name: "contestRankCute"),            // +0xB9
            .uint8(name: "contestRankSmart"),           // +0xBA
            .uint8(name: "contestRankTough"),           // +0xBB
            .uint8(name: "contestLuster"),              // +0xBC contest sheen ("luster")
            .array(name: "ribbons", count: 12, of: .uint8),  // +0xBD..0xC9 ribbon flags
            .padding(length: 1),                        // +0xC9 unused / fateful (JP)
            .uint8(name: "pokerusStrain"),              // +0xCA
            .uint8(name: "isEgg"),                      // +0xCB
            .uint8(name: "abilityBit"),                 // +0xCC 0/1 → ability slot
            .uint8(name: "validFlag"),                  // +0xCD
            .padding(length: 1),                        // +0xCE
            .uint8(name: "marking"),                    // +0xCF
            .uint8(name: "pokerusDays"),                // +0xD0
            .padding(length: 6),                        // +0xD1..0xD7
            .uint8(name: "partySlot"),                  // +0xD7
            .uint16(name: "shadowId"),                  // +0xD8 shadow-Pokémon id (0 ⇒ not Shadow)
            .padding(length: 2),                        // +0xDA..0xDC
            .uint32(name: "purification"),              // +0xDC purification / heart progress
            .padding(length: 0x58),                     // +0xE0..0x138 shadow/battle tail (undocumented)
        ]
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
        name: "ColoSaveTrainer",
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
        name: "ColoSavePCBox",
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
        name: "ColoSaveBattleMode",
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
        name: "ColoSaveDaycare",
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

    // MARK: - Section 5: StrategyMemo

    /// One Strategy-Memo entry — **0xC bytes**. The memo is the
    /// Pokédex-like "seen/caught" log; each entry records a species plus
    /// the identity of the Pokémon that was logged. Layout confirmed
    /// from the `memoDataSet` / `memoDataGet*` accessors in the
    /// Colosseum disassembly (entry stride `mulli …,0xC`; XD's
    /// `text1/memo/*` routines match byte-for-byte).
    static let saveMemoEntryStruct = StructMap(
        name: "ColoMemoEntry",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "speciesAndFlags"),   // +0x0 species (low 14 bits) | 0x8000 "new/unviewed"
            .padding(length: 2),                // +0x2 reserved (never read/written)
            .uint32(name: "catchTrainerRnd"),   // +0x4 OT identity (catch-trainer rnd)
            .uint32(name: "pid"),               // +0x8 the logged Pokémon's rnd / PID
        ]
    )

    /// Colo save section 5 (slot+0x82B0, length 0xB10) — the Strategy
    /// Memo: a `count`-prefixed array of up to 235 `ColoMemoEntry`
    /// records. Header `count` (u16) + reserved (u16), entries from
    /// +0x4, then an 8-byte tail. 2 + 2 + 235×0xC + 8 = 0xB10.
    static let saveStrategyMemoStruct = StructMap(
        name: "ColoSaveStrategyMemo",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "count"),             // +0x000 number of populated entries
            .padding(length: 2),                // +0x002 reserved (only the count halfword is read)
            .array(name: "entries", count: 235, of: .subStruct(name: "ColoMemoEntry")),  // +0x004..0xB08
            .padding(length: 8),                // +0xB08..0xB10 tail (untouched by code)
        ]
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
