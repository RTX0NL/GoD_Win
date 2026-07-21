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
            .array(name: "party", count: 6, of: .subStruct(name: "ColoPokemon")),   // +0x030..0x780
            // Bag pockets — stride-4 ColoItem {itemId,count}. Offsets from
            // the Hero dispatcher (`zz_trainer_get_value_with_index` idx 4–9);
            // the legacy tool never located these (kSaveFileBagItemsOffset=-1).
            .array(name: "itemsNormal",  count: 20, of: .subStruct(name: "ColoItem")),  // +0x780..0x7D0
            .array(name: "itemsKey",     count: 43, of: .subStruct(name: "ColoItem")),  // +0x7D0..0x87C
            .array(name: "itemsBall",    count: 16, of: .subStruct(name: "ColoItem")),  // +0x87C..0x8BC
            .array(name: "itemsTM",      count: 64, of: .subStruct(name: "ColoItem")),  // +0x8BC..0x9BC
            .array(name: "itemsBerry",   count: 46, of: .subStruct(name: "ColoItem")),  // +0x9BC..0xA74
            .array(name: "itemsCologne", count: 3,  of: .subStruct(name: "ColoItem")),  // +0xA74..0xA80
            .uint8(name: "unknownA"),                               // +0xA80 (dispatcher idx 0xB)
            .uint8(name: "unknownB"),                               // +0xA81 (dispatcher idx 0x19)
            .padding(length: 2),                                    // +0xA82..0xA84 alignment
            .uint32(name: "money"),                                 // +0xA84 pokedoru (heroAddPokedoru)
            .uint32(name: "coupons"),                               // +0xA88 pokecoupon
            .uint32(name: "couponsLifetime"),                       // +0xA8C pokecoupon total
            // 9 story/battle boolean flags (dispatcher idx 0xF–0x16, 0x18);
            // three are consumed as damage-modifier bools. Colosseum has no
            // player gender or badges, so there are no such fields here.
            .array(name: "storyFlags", count: 9, of: .uint8),      // +0xA90..0xA99
            .padding(length: 1),                                   // +0xA99..0xA9A alignment
            .array(name: "unknownEntries", count: 10, of: .uint32),// +0xA9A..0xAC2 (dispatcher idx 0xA; semantics TBD)
            .string(name: "ruiName", format: .gsColo, length: 11), // +0xAC2..0xAD8 (22 bytes) RUI's name
            .padding(length: 0x40),                                // +0xAD8..0xB18 unmapped tail
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

    // MARK: - Section 3: PC Item Storage + Mailbox

    /// One inventory slot (itemDataId + quantity). 4 bytes.
    static let saveItemStruct = StructMap(
        name: "ColoItem",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "itemId"),        // +0x0 itemDataId
            .uint16(name: "count"),         // +0x2 quantity
        ]
    )

    /// The PDA Mailbox — **0x448 bytes** (slot 0x7D28..0x8170). Layout
    /// from `mailMainInit` (`zz_01d1fa8_`) in the Colosseum disassembly:
    /// a 512-slot received-mail list, a count, a 512-bit "received"
    /// bitfield indexed by mail ID (byte `id>>3`, bit `7-(id&7)`), and
    /// 6 trailing flag bytes.
    static let saveMailboxStruct = StructMap(
        name: "ColoMailbox",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "mailIds", count: 512, of: .uint16),   // +0x000..0x400 (0xFFFF = empty)
            .uint16(name: "count"),                             // +0x400
            .array(name: "receivedBits", count: 0x40, of: .uint8),  // +0x402..0x442 512-bit bitfield
            .array(name: "flagBytes", count: 6, of: .uint8),    // +0x442..0x448
        ]
    )

    /// Colo save section 3 (slot+0x797C, length 0x7F4). Despite PKHeX's
    /// "BattleData"/"BattleMode" guess, the disassembly shows this
    /// section is two adjacent save blocks: the **PC Item Storage**
    /// (tail of the PCBox block — 235 × `ColoItem`, `pcboxGetNbItemSlot`
    /// = 0xEB) followed by the **PDA Mailbox**. 235×4 + 0x448 = 0x7F4.
    /// (The genuine battle-mode registered teams — `toolentryTaisen` —
    /// live separately at slot 0x19744, inside `Tail`.)
    static let savePCItemsMailboxStruct = StructMap(
        name: "ColoSavePCItemsMailbox",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "pcItems", count: 235, of: .subStruct(name: "ColoItem")),  // +0x000..0x3AC
            .subStruct(name: "mailbox", typeName: "ColoMailbox"),                    // +0x3AC..0x7F4
        ]
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

    /// Colo save section 5 (slot+0x82B0, length **0x1774**) — the
    /// Strategy Memo: a `count`-prefixed array of 500 `ColoMemoEntry`
    /// records. Header `count` (u16) + reserved (u16), entries from
    /// +0x4. 2 + 2 + 500×0xC = 0x1774 (no tail) — identical geometry to
    /// XD's memo. NOTE: PKHeX undersized this block to 0xB10; the game's
    /// own dispatcher (`zz_trainer_get_data_pointer` case 12 @ 0x82B0 →
    /// next block card-e @ 0x9A24) proves it is 0x1774. Correcting it
    /// shifts the Tail section's start from 0x8DC0 to 0x9A24.
    static let saveStrategyMemoStruct = StructMap(
        name: "ColoSaveStrategyMemo",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "count"),             // +0x000 number of populated entries
            .padding(length: 2),                // +0x002 reserved (only the count halfword is read)
            .array(name: "entries", count: 500, of: .subStruct(name: "ColoMemoEntry")),  // +0x004..0x1774
        ]
    )

    // MARK: - Section 6: Tail (now decomposed into named blocks)

    /// Trailing slot region, section 6 — **0x145DC** bytes, slot
    /// 0x9A24..0x1E000. (Shrunk from the old PKHeX 0x15240 catch-all now
    /// that StrategyMemo is correctly 0x1774.) The game's save-block
    /// dispatcher (`zz_trainer_get_data_pointer`) resolves several
    /// distinct blocks in here; this struct names them and keeps genuine
    /// gaps as padding. The section stays a raw `.bin` dump for now, so
    /// these named fields document the layout (and locate the flag banks
    /// for the future flag op) without inflating the dump into JSON. All
    /// offsets are absolute slot offsets; sub-block sizes total 0x145DC.
    ///
    /// Blocks (dispatcher block id in parens):
    ///  - Card-e save data (13) — e-Reader payload
    ///  - Tool / battle-entry (14) — hdr + 4 registered battle teams
    ///    (`toolentryTaisen`, 0x1660 each, party 6×CK3 at entry +0x5C) +
    ///    tool misc / Pokécoupon mirror
    ///  - Shadow monitor (15) — 97 shadow-Pokémon purification records
    ///  - Flag bit-banks (4/5/6) — FlagLevel0/1/2; raw, decode via the
    ///    future flag op (see [[gs-flag-system]])
    ///  - ExRibbon (16) — bonus-disc ribbons (11 bytes)
    static let saveTailStruct = StructMap(
        name: "ColoSaveTail",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .padding(length: 0x49CC),           // 0x9A24..0xE3F0  Card-e save data (block 13)
            .padding(length: 0xCC2C),           // 0xE3F0..0x1B01C Tool/battle-entry (block 14): hdr 0x24 + 4×0x1660 registered teams @0xE414 + tool misc
            .padding(length: 0xDA8),            // 0x1B01C..0x1BDC4 Shadow monitor (block 15): 97 records
            .array(name: "flagLevel0", count: 0x20, of: .uint8),   // 0x1BDC4 (block 4)
            .array(name: "flagLevel1", count: 0x80, of: .uint8),   // 0x1BDE4 (block 5)
            .array(name: "flagLevel2", count: 0x600, of: .uint8),  // 0x1BE64 (block 6) — JP bonus-disc flags near 0x1C120
            .array(name: "exRibbon", count: 0xB, of: .uint8),      // 0x1C464 (block 16) bonus-disc ribbons
            .padding(length: 0x1B91),           // 0x1C46F..0x1E000 reserved/unknown + cipher trailer (last 0x20)
        ]
    )
}
