import Structs
import GoDFoundation

/// Struct definitions for XD save-slot sections. Field offsets cross-
/// referenced against PKHeX's `SAV3XD.cs` and the legacy GoD tool's
/// `XGSaveManager.swift` constants. XD's section sizes are read from
/// the slot's own size table at runtime, so these structs only need
/// to cover the *known* prefix of each section — trailing bytes are
/// preserved through the build path's pad-from-raw-slot logic.
public extension XDStructDefaults {

    // MARK: - Pokemon sub-structs

    /// One move slot inside a `Pokemon`. 4 bytes. See
    /// `Documentation/Assembly Analysis/Data Structures/Waza.md`.
    static let saveWazaStruct = StructMap(
        name: "XDWaza",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "moveId"),        // +0x0 wazaDataId
            .uint8(name: "pp"),             // +0x2 current PP
            .uint8(name: "ppUpCount"),      // +0x3 PP Ups applied (0..3)
        ]
    )

    /// One inventory slot (itemDataId + quantity). 4 bytes. See Item.md.
    static let saveItemStruct = StructMap(
        name: "XDItem",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "itemId"),        // +0x0 itemDataId
            .uint16(name: "count"),         // +0x2 quantity
        ]
    )

    // MARK: - Pokemon

    /// XD save-side Pokémon record — **0xC4 bytes**. Field layout from
    /// `Documentation/Assembly Analysis/Data Structures/Pokemon.md`
    /// (cross-referenced to the game's own `pokemonBiosGet*` accessors).
    static let savePokemonStruct = StructMap(
        name: "XDPokemon",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "species"),               // +0x00 pokemonDataId
            .uint16(name: "heldItem"),              // +0x02 itemDataId
            .uint16(name: "hp"),                    // +0x04 current HP
            .uint16(name: "friendship"),            // +0x06 friendLevel
            .uint16(name: "catchFloorId"),          // +0x08
            .uint16(name: "amari"),                 // +0x0A
            .uint16(name: "para1Amari"),            // +0x0C
            .uint8(name: "catchLevel"),             // +0x0E
            .uint8(name: "catchBallId"),            // +0x0F
            .uint8(name: "catchTrainerSex"),        // +0x10 OT gender
            .uint8(name: "level"),                  // +0x11
            .uint8(name: "fur"),                    // +0x12
            .uint8(name: "pokerus"),                // +0x13
            .uint8(name: "pcboxMark"),              // +0x14
            .uint8(name: "mailId"),                 // +0x15
            .uint8(name: "condition"),              // +0x16 status condition
            .uint8(name: "conditionCount"),         // +0x17
            .uint8(name: "conditionTurn"),          // +0x18
            .uint8(name: "conditionTurnNow"),       // +0x19
            .uint8(name: "flagAmari"),              // +0x1A
            .array(name: "unknown1", count: 2, of: .uint8),  // +0x1B..0x1D undocumented
            .uint8(name: "packedFlags"),            // +0x1D fusei(0x20)/tamago-egg(0x80)/…
            .padding(length: 2),                    // +0x1E..0x20 alignment before exp
            .uint32(name: "exp"),                   // +0x20
            .uint32(name: "catchTrainerRnd"),       // +0x24
            .uint32(name: "pid"),                   // +0x28 rnd (personality value)
            .uint32(name: "conditionAmari"),        // +0x2C
            .uint32(name: "eventGetFlag"),          // +0x30
            .uint32(name: "attest"),                // +0x34 validation hash
            .string(name: "otName", format: .gsXD, length: 11),            // +0x38..0x4E
            .string(name: "nickname", format: .gsXD, length: 11),          // +0x4E..0x64
            .string(name: "nicknameOriginal", format: .gsXD, length: 12),  // +0x64..0x7C
            .uint32(name: "ribbon"),                // +0x7C packed ribbon flags
            .array(name: "moves", count: 4, of: .subStruct(name: "XDWaza")),  // +0x80..0x90
            .uint16(name: "maxHp"),                 // +0x90 computed stats
            .uint16(name: "phyAtk"),                // +0x92
            .uint16(name: "phyDef"),                // +0x94
            .uint16(name: "speAtk"),                // +0x96
            .uint16(name: "speDef"),                // +0x98
            .uint16(name: "nimbleness"),            // +0x9A Speed
            .uint16(name: "maxHpEV"),               // +0x9C EVs
            .uint16(name: "phyAtkEV"),              // +0x9E
            .uint16(name: "phyDefEV"),              // +0xA0
            .uint16(name: "speAtkEV"),              // +0xA2
            .uint16(name: "speDefEV"),              // +0xA4
            .uint16(name: "nimblenessEV"),          // +0xA6
            .uint8(name: "hpIV"),                   // +0xA8 IVs (PokemonStatusRnd)
            .uint8(name: "atkIV"),                  // +0xA9
            .uint8(name: "defIV"),                  // +0xAA
            .uint8(name: "spAtkIV"),                // +0xAB
            .uint8(name: "spDefIV"),                // +0xAC
            .uint8(name: "speedIV"),                // +0xAD
            .array(name: "unknown2", count: 10, of: .uint8),  // +0xAE..0xB8 ExpandStatus (undocumented)
            .uint16(name: "fightTrainerPokemonDataId"),  // +0xB8
            .uint16(name: "shadowId"),              // +0xBA darkpokemonDataId (0 ⇒ not Shadow)
            .array(name: "unknown3", count: 8, of: .uint8),  // +0xBC..0xC4 unmapped tail
        ]
    )

    // MARK: - Section 0: Config

    /// XD save section 0 — Config. Per `SAV3XD.cs` exposes:
    ///   - `gcGameIndex`     @ +0x00
    ///   - `currentRegion`   @ +0x01
    ///   - `originalRegion`  @ +0x02
    ///   - `gcLanguage`      @ +0x03
    ///   - `playTimeJP`      @ +0x20 (f32 BE, Japanese saves)
    ///   - `playTimeIntl`    @ +0x30 (f64 BE, US/PAL saves)
    /// `playTimeJP` and `playTimeIntl` cover the same logical "time
    /// played" field — the runtime picks one based on the `Japanese`
    /// flag, but on-disk both slots exist. Editing one changes only
    /// the play-time recorded for that region.
    static let saveConfigStruct = StructMap(
        name: "XDSaveConfig",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "gcGameIndex"),
            .uint8(name: "currentRegion"),
            .uint8(name: "originalRegion"),
            .uint8(name: "gcLanguage"),
            .array(name: "unknown1", count: 0x1C, of: .uint8),   // +0x04..0x20 Gamedata (memcard ID / save counter / floor IDs — TBD)
            .losslessFloat(name: "playTimeJP"),          // +0x20  (f32 BE, JP saves)
            .array(name: "unknown2", count: 0x0C, of: .uint8),   // +0x24..0x30 Gamedata (options / PAR checksum — TBD)
            .losslessDouble(name: "playTimeIntl"),       // +0x30  (f64 BE, US/PAL)
            .array(name: "unknown3", count: 0x50, of: .uint8),   // +0x38..0x88 Gamedata (sys-header checksum / Pokédex playdata — TBD)
        ]
    )

    // MARK: - Section 1: Trainer1 / Hero (0x978)

    /// XD save section 1 — the `Hero` record (the player). Full 0x978
    /// layout from `Documentation/Assembly Analysis/Data Structures/Hero.md`
    /// (cross-referenced to the `heroBios*` accessors). Embeds the party
    /// (6 × XDPokemon) and 8 inventory arrays (262 slots × XDItem).
    static let saveTrainer1Struct = StructMap(
        name: "XDSaveTrainer",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .string(name: "playerName", format: .gsXD, length: 11),        // +0x000 (22)
            .string(name: "playerNameAlt", format: .gsXD, length: 11),     // +0x016 (22) mirror/alt
            .uint16(name: "SID16"),                                        // +0x02C rnd hi (secret ID)
            .uint16(name: "TID16"),                                        // +0x02E rnd lo (trainer ID)
            .array(name: "party", count: 6, of: .subStruct(name: "XDPokemon")),      // +0x030..0x4C8
            .array(name: "itemsNormal", count: 30, of: .subStruct(name: "XDItem")),  // +0x4C8..0x540
            .array(name: "itemsKey", count: 43, of: .subStruct(name: "XDItem")),     // +0x540..0x5EC
            .array(name: "itemsBall", count: 16, of: .subStruct(name: "XDItem")),    // +0x5EC..0x62C
            .array(name: "itemsTM", count: 64, of: .subStruct(name: "XDItem")),      // +0x62C..0x72C
            .array(name: "itemsBerry", count: 46, of: .subStruct(name: "XDItem")),   // +0x72C..0x7E4
            .array(name: "itemsCologne", count: 3, of: .subStruct(name: "XDItem")),  // +0x7E4..0x7F0
            .array(name: "itemsBattleCD", count: 60, of: .subStruct(name: "XDItem")),// +0x7F0..0x8E0
            .uint8(name: "gender"),                                        // +0x8E0 sexDataId
            .uint8(name: "homePlace"),                                     // +0x8E1
            .padding(length: 2),                                           // +0x8E2..0x8E4 alignment before money
            .uint32(name: "money"),                                        // +0x8E4 pokedoru
            .uint32(name: "coupons"),                                      // +0x8E8 pokecoupon
            .uint32(name: "couponsLifetime"),                             // +0x8EC pokecouponAll
            .array(name: "badges", count: 8, of: .uint8),                  // +0x8F0..0x8F8
            .uint8(name: "joviFlag"),                                      // +0x8F8 hizukiFlag
            .padding(length: 1),                                           // +0x8F9 alignment before joviItems
            .array(name: "joviItems", count: 10, of: .subStruct(name: "XDItem")),    // +0x8FA..0x922
            .string(name: "joviName", format: .gsXD, length: 11),          // +0x922 (22) hizukiName
            .uint8(name: "meetShadowCount"),                               // +0x938 meetDarkPokemonCount
            .array(name: "unknown1", count: 0x3F, of: .uint8),             // +0x939..0x978 undocumented tail
        ]
    )

    // MARK: - Section 2: PCBox (8 storage boxes)

    /// One XD PC box: 16-byte name + 4 unknown bytes + 30 × XK3.
    /// Total 0x170C.
    static let saveBoxStruct = StructMap(
        name: "XDBox",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            // Box name — 8 chars × 2 bytes (UTF-16 BE), zero-padded.
            .string(name: "name", format: .gsXD, length: 8),         // +0x00..0x10
            .array(name: "unknown1", count: 4, of: .uint8),          // +0x10..0x14 undocumented
            .array(name: "pokemon", count: 30, of: .subStruct(name: "XDPokemon")),
        ]
    )

    /// XD save section 2 — PCBox (0xBC50). Per PCBOX.md: 8 boxes ×
    /// 0x170C, then a shared 235-slot item pool, a flag word, and a
    /// 0x40 on-card trailing region (the RAM `PCBOX` class is 0xBC10;
    /// the on-card section copies 0x40 more).
    static let savePCBoxStruct = StructMap(
        name: "XDSavePCBox",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "boxes", count: 8, of: .subStruct(name: "XDBox")),          // 0x0000..0xB860
            .array(name: "storedItems", count: 235, of: .subStruct(name: "XDItem")), // 0xB860..0xBC0C
            .uint32(name: "flag"),                                                    // 0xBC0C..0xBC10
            .array(name: "unknown1", count: 0x40, of: .uint8),                        // 0xBC10..0xBC50 on-card trailing region (undocumented)
        ]
    )

    // MARK: - Section 7: Shadow Pokemon Status table

    /// One entry in XD's global Shadow-Pokémon status table — **0x48
    /// bytes** (72), per `DarkPokemon::init`'s `memset(this, 0, 0x48)`
    /// (the game's internal symbol is `DarkPokemon`, from the Japanese
    /// term; we surface it with the English "Shadow Pokémon" name).
    /// Section 7 is a run of exactly 128 of these (128 × 0x48 = 0x2400 =
    /// the real on-card section size), matching `darkPokemonGetDark-
    /// Pokemon`'s `savedata + idx * 0x48` with its 0x80-bound. Layout
    /// from `Documentation/Assembly Analysis/Data Structures/
    /// DarkPokemon.md`, cross-referenced to the get/set accessors.
    ///
    /// This is the XD-unique record: Shadow status, purification
    /// bookkeeping (poolExp / heart-gauge), Snatch metadata, and
    /// Reverse ("Hyper") Mode state. Bytes 0x00/0x01 are dense
    /// bitfields (kept as raw `u8` — the sub-bit accessors don't
    /// decompose into byte fields); undocumented gaps are `unknown<n>`
    /// byte arrays (alignment-only gaps stay `padding`).
    static let saveShadowPokemonStruct = StructMap(
        name: "ShadowPokemonStatus",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "statusFlags"),        // +0x00 packed: status(3b)/snatchFromWho(2b)/where
            .uint8(name: "packedFlags"),        // +0x01 reverseMode(0x20)/isUpdate(0x10)/isInformation(0x80)/isWazaNew
            .padding(length: 2),                // +0x02..0x04 alignment before poolExp
            .uint32(name: "poolExp"),           // +0x04 pooled EXP awaiting purification
            .array(name: "unknown1", count: 3, of: .uint8),  // +0x08..0x0B undocumented
            .uint8(name: "statusRnd"),          // +0x0B per-status random salt
            .array(name: "unknown2", count: 7, of: .uint8),  // +0x0C..0x13 undocumented
            .uint8(name: "snatchIndex"),        // +0x13
            .uint16(name: "orgTrainer"),        // +0x14 original-trainer ID
            .uint16(name: "catchFloorId"),      // +0x16
            .uint16(name: "poolFriendLevel"),   // +0x18
            .uint16(name: "statusID"),          // +0x1A this record's own table ID
            .uint32(name: "rnd"),               // +0x1C the shadow record's own PID
            .array(name: "unknown3", count: 4, of: .uint8),  // +0x20..0x24 undocumented
            .uint32(name: "heartGauge"),        // +0x24 heart gauge (raw i32, counts down)
            .string(name: "trainerName", format: .gsXD, length: 11),  // +0x28..0x3E (22)
            .uint16(name: "shadowPokemonID"),   // +0x3E index into the shadow-Pokémon deck set (species-in-set)
            .uint8(name: "reversePattern"),     // +0x40
            .padding(length: 3),                // +0x41..0x44 alignment before walkCount
            .uint32(name: "walkCount"),         // +0x44 step accumulator toward next heart-gauge drop
        ]
    )

    // MARK: - Section 4: Daycare

    /// XD save section 4 — Daycare. Per PKHeX:
    ///   - occupied          @ +0x00 (u8)
    ///   - depositLevel      @ +0x01 (u8)
    ///   - depositedEXP      @ +0x04 (u32 BE)
    ///   - pokemon (XK3)     @ +0x08
    /// Total 0xCC, matches the section length in our fixture.
    static let saveDaycareStruct = StructMap(
        name: "XDSaveDaycare",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "occupied"),
            .uint8(name: "depositLevel"),
            .padding(length: 2),                // alignment before depositedEXP
            .uint32(name: "depositedEXP"),
            .subStruct(name: "pokemon", typeName: "XDPokemon"),
        ]
    )

    // MARK: - Section 5: StrategyMemo

    /// One Strategy-Memo entry — **0xC bytes**. Same layout as
    /// Colosseum's (`text1/memo/*` matches byte-for-byte): a species +
    /// the identity of the Pokémon logged into the Pokédex-like memo.
    static let saveMemoEntryStruct = StructMap(
        name: "XDMemoEntry",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "speciesAndFlags"),   // +0x0 species (low 14 bits) | 0x8000 "new/unviewed"
            .padding(length: 2),                // +0x2 reserved (never read/written)
            .uint32(name: "catchTrainerRnd"),   // +0x4 OT identity (catch-trainer rnd)
            .uint32(name: "pid"),               // +0x8 the logged Pokémon's rnd / PID
        ]
    )

    /// XD save section 5 — the PDA "Strategy Memo" (Pokédex-like seen/
    /// caught log). On-card size 0x1774: a `count`-prefixed array of
    /// exactly 500 `XDMemoEntry` records (`savedataGetStatus(0,0xC)`;
    /// entry stride 0xC). Header `count` (u16) + reserved (u16), then
    /// entries from +0x4. 2 + 2 + 500×0xC = 0x1774 (no tail).
    static let saveStrategyMemoStruct = StructMap(
        name: "XDSaveStrategyMemo",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "count"),             // +0x000 number of populated entries
            .padding(length: 2),                // +0x002 reserved (only the count halfword is read)
            .array(name: "entries", count: 500, of: .subStruct(name: "XDMemoEntry")),  // +0x004..0x1774
        ]
    )

    // MARK: - Section 6: BattleMode (Taisen rule save)

    /// One Battle-Mode rule slot — **0x90 bytes**. Field widths from the
    /// slot-by-slot copy in `menuCBBios_RuleConstRuleSet` /
    /// `menuCB_RULE_INIT`. Slots 0–2 are seeded from constant templates;
    /// 3–5 are the user-editable custom slots. Most header/tail params
    /// are battle-rule parameters whose individual meanings aren't
    /// pinned down (kept as `unknown<n>` byte arrays of the exact
    /// widths); the named fields are the ones the disassembly identifies.
    static let saveBattleRuleStruct = StructMap(
        name: "XDBattleRule",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "unknown1", count: 0x1A, of: .uint8),  // +0x00..0x1A rule header params (semantics TBD)
            .uint16(name: "participationCount"),// +0x1A RULE_INIT sets 4 for custom slots
            .array(name: "unknown2", count: 2, of: .uint8),     // +0x1C..0x1E (RULE_INIT sets 0)
            .array(name: "regulationIds", count: 21, of: .uint16),  // +0x1E..0x48 regulation-ID list
            .array(name: "unknown3", count: 8, of: .uint8),     // +0x48..0x50 (u32 ×2, semantics TBD)
            .uint16(name: "signature"),         // +0x50 per-slot validity magic (RuleEditSaveON marks slot "on")
            .array(name: "unknown4", count: 0x3E, of: .uint8),  // +0x52..0x90 parameter block (semantics TBD)
        ]
    )

    /// XD save section 6 — the **Battle Mode** ("Taisen") saved rule
    /// configuration (game symbol `_TOOL_SAVEDATA`; reached via
    /// `savedataGetStatus(0,0xE)`). NOT an item store — the player's
    /// item inventory lives in the Trainer section. On-card size 0x364:
    /// 6 rule slots (0x90 each) + the active-slot index byte + padding.
    /// Proof: `menuCB_RULE_INIT` does `memset(block,0,0x364)` then fills
    /// 6 slots and `stb 0x360`.
    static let saveBattleModeStruct = StructMap(
        name: "XDSaveBattleMode",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "rules", count: 6, of: .subStruct(name: "XDBattleRule")),  // +0x000..0x360
            .uint8(name: "currentSlot"),        // +0x360 active battle-mode index/flag
            .padding(length: 3),                // +0x361..0x364 reserved tail (memset-zeroed, never written)
        ]
    )
}
