import Structs
import GoDFoundation

/// Struct definitions for XD save-slot sections. Field offsets cross-
/// referenced against PKHeX's `SAV3XD.cs` and the legacy GoD tool's
/// `XGSaveManager.swift` constants.
///
/// Convention: undocumented regions are `unknown<n>` byte arrays.
/// Inter-field "gaps" are NOT zero alignment padding — the game
/// serializes these structs from a reused I/O buffer without memset, so
/// the gaps carry non-zero leftover that must round-trip byte-for-byte.
/// Hence `.none` alignment + explicit `unknown<n>` fields (the auto-
/// aligning `.cStyle` mode would zero the gaps and break round-trip).
/// `.padding` is only for genuinely dead space the game memset-zeroes
/// and never writes (e.g. the BattleMode section's trailing bytes).
public extension XDStructDefaults {

    // MARK: - Pokemon sub-structs

    /// One move slot inside a `Pokemon`. 4 bytes. See
    /// `Documentation/Assembly Analysis/Data Structures/Waza.md`.
    static let saveWazaStruct = StructMap(
        name: "XDWaza",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "moveId", typeName: "Moves"),        // +0x0 wazaDataId
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
            .abstraction(name: "itemId", typeName: "Items"),        // +0x0 itemDataId
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
            .abstraction(name: "species", typeName: "PokemonSpecies"),               // +0x00 pokemonDataId
            .abstraction(name: "heldItem", typeName: "Items"),              // +0x02 itemDataId
            .uint16(name: "hp"),                    // +0x04 current HP
            .uint16(name: "friendship"),            // +0x06 friendLevel
            .uint16(name: "catchFloorId"),          // +0x08
            .uint16(name: "amari"),                 // +0x0A
            .uint16(name: "para1Amari"),            // +0x0C
            .uint8(name: "catchLevel"),             // +0x0E
            .uint8(name: "catchBallId"),            // +0x0F
            .abstraction(name: "catchTrainerSex", typeName: "Gender"),  // +0x10 OT gender
            .uint8(name: "level"),                  // +0x11
            .uint8(name: "fur"),                    // +0x12
            .uint8(name: "pokerus"),                // +0x13
            .uint8(name: "pcboxMark"),              // +0x14
            .uint8(name: "mailId"),                 // +0x15
            .abstraction(name: "condition", typeName: "StatusCondition"),  // +0x16 status condition
            .uint8(name: "conditionCount"),         // +0x17
            .uint8(name: "conditionTurn"),          // +0x18
            .uint8(name: "conditionTurnNow"),       // +0x19
            .uint8(name: "flagAmari"),              // +0x1A
            .array(name: "unknown1", count: 2, of: .uint8),  // +0x1B..0x1D undocumented
            // +0x1D. Masks from the `rlwinm`s in `pokemonBiosGetTamagoFlag`
            // and `…GetFuseiFlag`; the rest are probably single-bit flags
            // too (`pokemonBiosGetTokuseiFlag` delegates elsewhere), but no
            // accessor pins one, so they stay unnamed.
            .bits(name: "packedFlags", fields: [
                .flag(name: "isEgg", bit: 0, description: "tamagoFlag, 0x80"),
                .flag(name: "unknownBit1", bit: 1, description: "0x40"),
                .flag(name: "isInvalid", bit: 2, description: "fuseiFlag, 0x20 — fails the save's validation"),
                .number(name: "unknownBits3_7", bits: 3...7, description: "0x1F"),
            ]),
            .array(name: "unknown2", count: 2, of: .uint8),  // +0x1E..0x20 undocumented (non-zero leftover)
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
            .array(name: "unknown3", count: 10, of: .uint8),  // +0xAE..0xB8 ExpandStatus (undocumented)
            .uint16(name: "fightTrainerPokemonDataId"),  // +0xB8
            .uint16(name: "shadowId"),              // +0xBA darkpokemonDataId (0 ⇒ not Shadow)
            .array(name: "unknown4", count: 8, of: .uint8),  // +0xBC..0xC4 unmapped tail
        ]
    )

    // MARK: - Section 0: Config

    /// XD save section 0 — Config. Per `SAV3XD.cs` exposes:
    ///   - `gcGameIndex`     @ +0x00
    ///   - `currentRegion`   @ +0x01
    ///   - `originalRegion`  @ +0x02
    ///   - `gcLanguage`      @ +0x03 — we name it `langAreaId` (the actual
    ///     player-selected language is our `playerLanguage` @ +0x2B)
    ///   - `playTimeJP`      @ +0x20 (f32 BE, Japanese saves)
    ///   - `playTimeIntl`    @ +0x30 (f64 BE, US/PAL saves)
    /// `playTimeJP` and `playTimeIntl` cover the same logical "time
    /// played" field — the runtime picks one based on the `Japanese`
    /// flag, but on-disk both slots exist. Editing one changes only
    /// the play-time recorded for that region.
    /// The 0xA8 slot header that precedes the sub-blocks.
    ///
    /// Everything the game needs to find a sub-block lives here, so it is
    /// real save data and is dumped as editable JSON rather than a blob.
    /// Layout measured across 24 real saves spanning all three regions
    /// (`scripts/analysis/scan_gci.py` plus a direct byte comparison):
    ///
    /// | Offset | Field | Observed |
    /// |---|---|---|
    /// | `0x00` | `magic` | `01 01 01` on 23 of 24; one save has `01 01 00` |
    /// | `0x03` | `reserved` | `0` on every save |
    /// | `0x04` | `saveCounter` | small `u32`, 1…279 in the corpus |
    /// | `0x08` | `cipherKey` | the plaintext key seed, fresh per save |
    /// | `0x10` | `checksumTags` | zero in a decrypted slot — the cipher clears it before recomputing, and `XDSaveCipher` rewrites it on encrypt |
    /// | `0x20` | `subBlockSizes` | 16 × `u16`; region-dependent (JP's Config is 0x80 vs 0x88, PCBox 0xBC0C vs 0xBC50) |
    /// | `0x40` | `subBlockOffsets` | 16 × two `u16`, **low half first**, relative to 0xA8 |
    /// | `0x80` | `reservedConstant` | `00 20 00 80 06 00 00 08 00 00 00 08` on all 24, JP included |
    /// | `0x8C` | `unidentified` | high-entropy and different on every save; halfwords repeat at +16 offset by the cipher's own sbox biases, so it reads as leftover cipher state rather than save data |
    ///
    /// The offset table is the game's own placement of each sub-block and
    /// has to stay consistent with it — XD relocates sub-blocks on every
    /// save, so these are not constants.
    static let saveSlotHeaderStruct = StructMap(
        name: "XDSaveSlotHeader",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "magic", count: 3, of: .uint8),                 // +0x00
            .uint8(name: "reserved"),                                    // +0x03
            .uint32(name: "saveCounter"),                                // +0x04
            .array(name: "cipherKey", count: 4, of: .uint16),            // +0x08 plaintext key seed
            .array(name: "checksumTags", count: 8, of: .uint16),         // +0x10 rewritten on encrypt
            .array(name: "subBlockSizes", count: 16, of: .uint16),       // +0x20
            .array(name: "subBlockOffsets", count: 32, of: .uint16),     // +0x40 pairs: low half, high half
            .array(name: "reservedConstant", count: 12, of: .uint8),     // +0x80 constant on every save measured
            .array(name: "unidentified", count: 28, of: .uint8),         // +0x8C leftover cipher state
        ]
    )

    static let saveConfigStruct = StructMap(
        name: "XDSaveConfig",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "gcGameIndex", typeName: "GameVersion"),
            .uint8(name: "genId"),                              // fixed build marker (always 3), NOT a region
            .abstraction(name: "region", typeName: "Region"),   // areaId — the actual build region (jp=1/us=2/pal=3)
            .abstraction(name: "langAreaId", typeName: "Language"),   // +0x03 GamedataAttest area/language grouping (US=2/JP=1/PAL=8→Language_8). The player's *selected* language is `playerLanguage` below.
            .array(name: "unknown1", count: 0x1C, of: .uint8),   // +0x04..0x20 Gamedata (memcard ID / save counter / floor IDs — TBD)
            .losslessFloat(name: "playTimeJP"),          // +0x20  (f32 BE, JP saves)
            // +0x24..0x30 GamedataSave tail (base = section start; GamedataSave = base+0x08, so these are GamedataSave+0x1C..0x28).
            .uint32(name: "prevFloorId"),                       // +0x24  GamedataSave+0x1C
            .uint8(name: "floorPosIndex"),                      // +0x28  GamedataSave+0x20
            .uint8(name: "optionNoVibration"),                 // +0x29  GamedataSave+0x21
            .uint8(name: "optionAudio"),                       // +0x2A  GamedataSave+0x22
            .abstraction(name: "playerLanguage", typeName: "Language"), // +0x2B  GamedataSave+0x23 — the player-selected in-game language (getStatus/setStatus index 11; "ParChecksum" symbol is a misnomer). US default = englishUS(2).
            .array(name: "unknown2", count: 0x04, of: .uint8),   // +0x2C..0x30 Gamedata (TBD)
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
            .uint16(name: "sid16"),                                        // +0x02C rnd hi (secret ID)
            .uint16(name: "tid16"),                                        // +0x02E rnd lo (trainer ID)
            .array(name: "party", count: 6, of: .subStruct(name: "XDPokemon")),      // +0x030..0x4C8
            .array(name: "itemsNormal", count: 30, of: .subStruct(name: "XDItem")),  // +0x4C8..0x540
            .array(name: "itemsKey", count: 43, of: .subStruct(name: "XDItem")),     // +0x540..0x5EC
            .array(name: "itemsBall", count: 16, of: .subStruct(name: "XDItem")),    // +0x5EC..0x62C
            .array(name: "itemsTM", count: 64, of: .subStruct(name: "XDItem")),      // +0x62C..0x72C
            .array(name: "itemsBerry", count: 46, of: .subStruct(name: "XDItem")),   // +0x72C..0x7E4
            .array(name: "itemsCologne", count: 3, of: .subStruct(name: "XDItem")),  // +0x7E4..0x7F0
            .array(name: "itemsBattleCD", count: 60, of: .subStruct(name: "XDItem")),// +0x7F0..0x8E0
            .abstraction(name: "gender", typeName: "Gender"),             // +0x8E0 sexDataId
            .uint8(name: "homePlace"),                                     // +0x8E1
            .array(name: "unknown1", count: 2, of: .uint8),                // +0x8E2..0x8E4 undocumented (non-zero leftover)
            .uint32(name: "money"),                                        // +0x8E4 pokedoru
            .uint32(name: "coupons"),                                      // +0x8E8 pokecoupon
            .uint32(name: "couponsLifetime"),                             // +0x8EC pokecouponAll
            .array(name: "badges", count: 8, of: .uint8),                  // +0x8F0..0x8F8
            .uint8(name: "joviFlag"),                                      // +0x8F8 hizukiFlag
            .array(name: "unknown2", count: 1, of: .uint8),                // +0x8F9 undocumented
            .array(name: "joviItems", count: 10, of: .subStruct(name: "XDItem")),    // +0x8FA..0x922
            .string(name: "joviName", format: .gsXD, length: 11),          // +0x922 (22) hizukiName
            .uint8(name: "meetShadowCount"),                               // +0x938 meetDarkPokemonCount
            .array(name: "unknown3", count: 0x3F, of: .uint8),             // +0x939..0x978 undocumented tail
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
    /// bitfields, split into their named bits below;
    /// undocumented gaps are `unknown<n>`
    /// byte arrays — the gaps carry non-zero leftover, not zero
    /// alignment, so they can't be dropped or `.cStyle`-auto-aligned.
    static let saveShadowPokemonStruct = StructMap(
        name: "ShadowPokemonStatus",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            // +0x00 and +0x01. Bit positions are the `rlwinm`/`rlwimi`
            // masks in the individual `DarkPokemon::` getters and setters —
            // see `Documentation/Assembly Analysis/Data Structures/
            // DarkPokemon.md`.
            .bits(name: "statusFlags", description: "Shadow status, and who it was snatched from", fields: [
                .flag(name: "unknownBit0", bit: 0, description: "0x80"),
                .number(name: "snatchFromWho", bits: 1...2, description: "0x60; whose trainer it was taken from"),
                .number(name: "status", bits: 3...5, description: "0x1C; the 3-bit darkPokemonStatus (getStatus/setStatus/addStatus)"),
                .number(name: "unknownBits6_7", bits: 6...7, description: "0x03"),
            ]),
            .bits(name: "packedFlags", description: "Reverse Mode and bookkeeping", fields: [
                .flag(name: "isInformation", bit: 0, description: "0x80"),
                .flag(name: "unknownBit1", bit: 1, description: "0x40"),
                .flag(name: "isReverseMode", bit: 2, description: "0x20; Reverse (\"Hyper\") Mode"),
                .flag(name: "isUpdate", bit: 3, description: "0x10; changed since the last save"),
                .flag(name: "unknownBit4", bit: 4, description: "0x08; the fourth move's isWazaNew would sit here, but no accessor reads it"),
                .flag(name: "isMoveNew3", bit: 5, description: "0x04; isWazaNew for move slot 3"),
                .flag(name: "isMoveNew2", bit: 6, description: "0x02; move slot 2"),
                .flag(name: "isMoveNew1", bit: 7, description: "0x01; move slot 1"),
            ]),
            .array(name: "unknown1", count: 2, of: .uint8),  // +0x02..0x04 undocumented (non-zero leftover)
            .uint32(name: "poolExp"),           // +0x04 pooled EXP awaiting purification
            .array(name: "unknown2", count: 3, of: .uint8),  // +0x08..0x0B undocumented
            .uint8(name: "statusRnd"),          // +0x0B per-status random salt
            .array(name: "unknown3", count: 7, of: .uint8),  // +0x0C..0x13 undocumented
            .uint8(name: "snatchIndex"),        // +0x13
            .uint16(name: "orgTrainer"),        // +0x14 original-trainer ID
            .uint16(name: "catchFloorId"),      // +0x16
            .uint16(name: "poolFriendLevel"),   // +0x18
            .uint16(name: "statusID"),          // +0x1A this record's own table ID
            .uint32(name: "rnd"),               // +0x1C the shadow record's own PID
            .array(name: "unknown4", count: 4, of: .uint8),  // +0x20..0x24 undocumented
            .uint32(name: "heartGauge"),        // +0x24 heart gauge (raw i32, counts down)
            .string(name: "trainerName", format: .gsXD, length: 11),  // +0x28..0x3E (22)
            .uint16(name: "shadowPokemonID"),   // +0x3E index into the shadow-Pokémon deck set (species-in-set)
            .uint8(name: "reversePattern"),     // +0x40
            .array(name: "unknown5", count: 3, of: .uint8),  // +0x41..0x44 undocumented (non-zero leftover)
            .uint32(name: "walkCount"),         // +0x44 step accumulator toward next heart-gauge drop
        ]
    )

    // MARK: - Section 3: Mailbox

    /// XD save section 3 — the **Mailbox** (0x4A). Identified from
    /// `savedataBiosGetMailboxPtr` / status index 0xA and the `mail`
    /// module's own accessors; `mailInitMailbox` memsets exactly 0x4A
    /// bytes and seeds all 32 id slots with 0x00FF, which is what an
    /// empty slot reads as (not 0xFFFF — the game does `li r0, 0xFF`
    /// then `sth`). See `Documentation/Assembly Analysis/Data
    /// Structures/Mailbox.md`.
    ///
    /// Mail *contents* are not here: an entry is an id into the game's
    /// static mail table, and the mail attached to a Pokémon lives on
    /// the Pokémon (`XDPokemon.mailId`).
    static let saveMailboxStruct = StructMap(
        name: "XDSaveMailbox",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            // +0x00..0x40 — the received-mail ids, in arrival order.
            // `mailAddMailbox` writes at `base + count * 2`, so slots at
            // and past `count` stay 0x00FF. Verified on every real save.
            .array(name: "mailIDs", count: 32, of: .uint16),
            .uint16(name: "count"),                          // +0x40 mailGetNbMailInMailbox
            // +0x42..0x46 — one bit per mail id, MSB-first within each
            // byte (`1 << (7 - (id & 7))` at `+0x42 + (id >> 3)`).
            // `mailAddMailbox` *clears* the bit for the id it stores.
            .array(name: "mailSeenBits", count: 4, of: .uint8),
            .uint8(name: "sortMode"),                        // +0x46 mailGetSortMode
            .array(name: "unknown1", count: 1, of: .uint8),  // +0x47 alignment before sendCount
            .uint16(name: "sendCount"),                      // +0x48 mailGetSendCnt
        ]
    )

    // MARK: - Section 8: Flags

    /// XD save section 8 — the **flag banks** (0x6B4). Not one blob:
    /// `_memcardStoreSaveData_multi` writes five separate regions back to
    /// back whenever the section is the expected 0x6B4, with the piece
    /// sizes in the slot header at +0x80/+0x82/+0x84/+0x86/+0x8A (0x20,
    /// 0x80, 0x600, 0x8, 0x8 on every real save of every region).
    ///
    /// The banks stay byte arrays here: decoding individual flags needs
    /// `common.rel`'s `GeneralFlags` descriptor table (2324 × 6 bytes),
    /// which a save project doesn't carry. What this buys is the
    /// boundaries — editing the wrong bank is the easy mistake. Each
    /// bank's size is exactly what `GSflagInit` declares to the flag
    /// system: 8, 0x20 and 0x180 *words*.
    static let saveFlagsStruct = StructMap(
        name: "XDSaveFlags",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "flagLevel0", count: 0x20, of: .uint8),   // +0x000 savedataBiosGetFlagLevel0Ptr
            .array(name: "flagLevel1", count: 0x80, of: .uint8),   // +0x020 …Level1
            .array(name: "flagLevel2", count: 0x600, of: .uint8),  // +0x0A0 …Level2 — exactly the bank's size
            // +0x6A0 — one bit per battle disk, MSB-first, via
            // `savedataGet/SetBattleDiskSellOut` (status index 0x18).
            .array(name: "battleDiskSellOut", count: 8, of: .uint8),
            // +0x6A8 — `bingo_bios` clear state (getClearLv / isClear /
            // isClearPlus), status index 0x1B.
            .array(name: "bingo", count: 8, of: .uint8),
            // +0x6B0 — the serializer writes 0x6B0 bytes into a 0x6B4
            // section, so these four are never written by the game.
            .array(name: "unknown1", count: 4, of: .uint8),
        ]
    )

    /// The `0x14` bytes of save section 8 that sit past the three flag banks.
    /// Not flags — no entry of `GeneralFlags` reaches them — so they are the
    /// section's own fields, and `_memcardStoreSaveData_multi` writes them as
    /// two separate blocks (`savedataGetStatus` indices 0x18 and 0x1B) with
    /// their sizes in the slot header at +0x86 and +0x8A.
    static let saveFlagsTailStruct = StructMap(
        name: "XDSaveFlagsTail",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // +0x00..0x08 — one bit per Battle CD, addressed exactly as
            // `savedataGet`/`SetBattleDiskSellOut` do: word `id >> 5`, bit
            // `id & 0x1F`. 64 bits for the 68 `NumberOfBattleCDs` the game
            // declares, so the top four ids have no bit here.
            .array(name: "battleDiskSellOut", count: 2, of: .uint32),
            // +0x08 — two bits per Battle Bingo card, 11 of them
            // (`NumberOfBingoCards`): bit `2n` is cleared
            // (`isClear__10bingo_biosFUl`) and bit `2n + 1` is selected
            // (`isSelect`). `getClearLv` walks the same word, skipping card 10.
            .uint32(name: "bingoCardState"),
            // +0x0C — one bit per card, and a different field despite the
            // name: `setClear__10bingo_biosFUl` sets bit `n` here while
            // `isClear` reads bit `2n` of the word above. What distinguishes
            // the two isn't established, so the name says only what writes it.
            .uint32(name: "bingoSetClearMask"),
            // +0x10..0x14 — the serializer copies 0x6B0 bytes into a 0x6B4
            // section, so the game never writes these four.
            .array(name: "unknown1", count: 4, of: .uint8),
        ],
        description: "Save section 8's non-flag tail: Battle CD sell-out bits + Battle Bingo state"
    )

    // MARK: - Section 9: ExRibbon

    /// XD save section 9 — the **extra-ribbon slots** (0xB). One byte per
    /// slot holding a ribbon id, 0 = not earned; `exribbonInit` zeroes
    /// exactly 0xB bytes and `pokeconv` copies all 11. Writes are
    /// once-only: `exribbonSetNo` stores only into a slot that is still 0.
    ///
    /// Two slots are named by the game: 4 is the National Ribbon
    /// (`exribbonSetNarionalRibbon` — the game's own spelling — stores
    /// 0x2C) and 5 the Earth Ribbon (`exribbonSetEarthRibbon`, 0x2D).
    /// Both were confirmed on the real corpus: slot 4 holds 44 on almost
    /// every save, slot 5 holds 45 only on a completed one. Slots 0-6 are
    /// the ones the status screen draws (`menuPokemonStatusDrawRibbon`
    /// bounds its lookup at 7).
    static let saveExRibbonStruct = StructMap(
        name: "XDSaveExRibbon",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "ribbonIDs", count: 11, of: .uint8),
        ]
    )

    // MARK: - Section 15: AnywaySave

    /// The `0x20`-byte header on save section 15, the "save anywhere"
    /// snapshot (`AnywaySave` to the game).
    ///
    /// Only the header is a struct. Everything from `+0x20` on is a
    /// `GSBinWriteStream` payload — `peopleMakeAnywaySaveData` writes it and
    /// `peopleRestoreAnywaySaveData` plays it back — so it is a stream, not a
    /// record, and its length varies per save. It stays raw.
    ///
    /// Fields marked "reader" are confirmed by
    /// `getStateData__12FloorManagerFP12StateDataPtr`; the rest come from a
    /// census of all 42 XD saves in the audit corpus.
    static let saveAnywaySaveHeaderStruct = StructMap(
        name: "XDAnywaySaveHeader",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // Spells "ANSW" on every save that has a snapshot, and is zero on
            // the ones that don't. Kept as bytes rather than a string: the
            // field is exactly four characters with no terminator, and it
            // isn't something anyone should be editing.
            .array(name: "magic", count: 4, of: .uint8),                    // +0x00
            // Reader: non-zero here is the whole of `floorCheckAnywaySaveData`
            // — it is how the game knows a quicksave exists. Reads 9705-11797
            // across the corpus, so it is a size rather than a flag.
            .uint32(name: "payloadSize"),                                   // +0x04
            // Reader: `ptr->extra = body + this`, an offset from `+0x20`.
            .uint32(name: "secondRegionOffset"),                            // +0x08
            .uint32(name: "unknown1"),                                      // +0x0C 820-2752, another size
            .uint32(name: "unknown2"),                                      // +0x10 zero on every save
            // Reader: FloorManager keeps the *maximum* of this across loads
            // (at +0x9DC), which is what a buffer high-water mark looks like.
            .uint32(name: "maxStateSize"),                                  // +0x14
            // Reader: copied to FloorManager +0x9E0 whenever the field above
            // raises that maximum. Reads 100-153, the range of XD's floor ids.
            .uint16(name: "floorID"),                                       // +0x18
            .uint16(name: "unknown3"),                                      // +0x1A zero on every save
            .uint32(name: "unknown4"),                                      // +0x1C zero on every save
        ],
        description: "Header of the save-anywhere snapshot; the body after it is a GSBinWriteStream payload"
    )

    // MARK: - Section 14: Purify Chamber

    /// One Purify Chamber set — 0x3D8, per
    /// `getStage__11CReliveHallFl`'s `stage = hall + index * 0x3D8`.
    /// Four "dancer" slots (`getDancerPointer` indexes them at 0xC4, the
    /// `XDPokemon` stride, and every quantity loop bounds at 4) then the
    /// centre Pokémon (`getVisitorPointer` at +0x310 = 4 × 0xC4).
    ///
    /// Nothing else is stored: flow/tempo, set state and how many sets
    /// are open are all *computed* from the Pokémon and their types each
    /// time (`getPassion`, `getTempo`, `getState`,
    /// `getReliveGiveStageQuantity`), and whether the chamber is open at
    /// all is a game flag (`isOpen` reads `GSflagGet(0x3C4)`).
    static let saveReliveStageStruct = StructMap(
        name: "XDReliveStage",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "dancers", count: 4, of: .subStruct(name: "XDPokemon")),  // +0x000..0x310
            .subStruct(name: "visitor", typeName: "XDPokemon"),                     // +0x310..0x3D4
            // +0x3D4 — a *signed* dancer index: `getPassionWoBonus` reads
            // it with `lbz`/`extsb`, multiplies by 0xC4 (the `XDPokemon`
            // stride) and adds it to the set's base to pick one dancer out
            // for the flow calculation. `debugPokemonSetup` stores 0.
            // Reads 0-3 on real saves, as a dancer index should.
            .int8(name: "flowDancerIndex"),
            // +0x3D5..0x3D8 — carries non-zero bytes on real saves, so
            // live data of some kind rather than alignment padding, but
            // nothing in the module reads them.
            .array(name: "unknown1", count: 3, of: .uint8),
        ]
    )

    /// XD save section 14 — the **Purify Chamber** (`Relive` to the game;
    /// 0x2298). Nine sets of 0x3D8: `getReliveGiveStageQuantity` walks
    /// exactly 9, stepping 0x3D8, and 9 × 0x3D8 = 0x2298 to the byte.
    /// Confirmed on the corpus — set occupancy runs 0-5 and a completed
    /// save shows all nine sets holding five Pokémon each.
    static let saveReliveStruct = StructMap(
        name: "XDSaveRelive",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "stages", count: 9, of: .subStruct(name: "XDReliveStage")),
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
            .array(name: "unknown1", count: 2, of: .uint8),  // +0x02..0x04 undocumented
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
            .array(name: "unknown1", count: 2, of: .uint8),  // +0x2 undocumented (holds non-zero leftover, not alignment)
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
            .array(name: "unknown1", count: 2, of: .uint8),  // +0x002 undocumented (only count is read, but not zeroed)
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
            // +0x1E..0x48 the player-visible rule name (21 units). Was
            // declared as a 21-entry `regulationIds` u16 list; the saves
            // disagree — every custom slot holds readable UTF-16 BE text
            // here ("Edit Rule 1".."Edit Rule 3" on US/PAL, the same three
            // names in katakana on JP), and slots 0-2, the preset rules,
            // leave it empty. Checked across all 42 real saves in the save
            // audit corpus: no slot carries bytes after the terminator, so
            // it round-trips as a string.
            .string(name: "ruleName", format: .gsXD, length: 21),  // +0x1E..0x48
            .array(name: "unknown3", count: 8, of: .uint8),     // +0x48..0x50 (u32 ×2, semantics TBD)
            .uint16(name: "signature"),         // +0x50 per-slot validity magic (RuleEditSaveON marks slot "on")
            .array(name: "unknown4", count: 0x3E, of: .uint8),  // +0x52..0x90 parameter block (semantics TBD)
        ]
    )

    // MARK: - Japanese-build variants

    // XD shipped in Japan first (Aug 2005) and the international builds
    // widened four save sections. Every JP section is the same layout with
    // one field resized, so the JP structs below differ from their
    // international counterparts in exactly one property each — offsets
    // before and after that property are unchanged. Derived from the real
    // JP save in the audit corpus and cross-checked against a US save of
    // the same sections; see `Documentation/Save-Round-Trip-Audit-2026-09.md`.

    /// JP `XDBattleRule` — 0x7C, 20 bytes shorter than the international
    /// 0x90. The rule name is 11 units here rather than 21; everything
    /// else keeps its offset, confirmed by the trailing `unknown4` flag
    /// byte landing at the same position from the end of the record on
    /// both builds.
    static let saveBattleRuleStructJP = StructMap(
        name: "XDBattleRuleJP",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "unknown1", count: 0x1A, of: .uint8),  // +0x00..0x1A
            .uint16(name: "participationCount"),// +0x1A
            .array(name: "unknown2", count: 2, of: .uint8),     // +0x1C..0x1E
            .string(name: "ruleName", format: .gsXD, length: 11),  // +0x1E..0x34
            .array(name: "unknown3", count: 8, of: .uint8),     // +0x34..0x3C
            .uint16(name: "signature"),         // +0x3C
            .array(name: "unknown4", count: 0x3E, of: .uint8),  // +0x3E..0x7C
        ]
    )

    /// JP save section 6 — 6 × `XDBattleRuleJP` (0x7C) + the active-slot
    /// byte + padding = 0x2EC, against the international 0x364.
    static let saveBattleModeStructJP = StructMap(
        name: "XDSaveBattleModeJP",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "rules", count: 6, of: .subStruct(name: "XDBattleRuleJP")),  // +0x000..0x2E8
            .uint8(name: "currentSlot"),        // +0x2E8
            .padding(length: 3),                // +0x2E9..0x2EC
        ]
    )

    /// JP `ShadowPokemonStatus` — 0x3C, 12 bytes shorter than the
    /// international 0x48. `trainerName` is 6 units rather than 11 (−10),
    /// and the alignment padding before the 4-byte `walkCount` shrinks
    /// from 3 bytes to 1 (−2) as a result. Offsets up to the name are
    /// identical: `heartGauge` at +0x24 reads the same round multiples of
    /// 100 on both builds, and the record's own id is the entry index at
    /// +0x34 here versus +0x3E internationally.
    static let saveShadowPokemonStructJP = StructMap(
        name: "ShadowPokemonStatusJP",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "statusFlags"),        // +0x00
            .uint8(name: "packedFlags"),        // +0x01
            .array(name: "unknown1", count: 2, of: .uint8),  // +0x02..0x04
            .uint32(name: "poolExp"),           // +0x04
            .array(name: "unknown2", count: 3, of: .uint8),  // +0x08..0x0B
            .uint8(name: "statusRnd"),          // +0x0B
            .array(name: "unknown3", count: 7, of: .uint8),  // +0x0C..0x13
            .uint8(name: "snatchIndex"),        // +0x13
            .uint16(name: "orgTrainer"),        // +0x14
            .uint16(name: "catchFloorId"),      // +0x16
            .uint16(name: "poolFriendLevel"),   // +0x18
            .uint16(name: "statusID"),          // +0x1A
            .uint32(name: "rnd"),               // +0x1C
            .array(name: "unknown4", count: 4, of: .uint8),  // +0x20..0x24
            .uint32(name: "heartGauge"),        // +0x24
            .string(name: "trainerName", format: .gsXD, length: 6),  // +0x28..0x34
            .uint16(name: "shadowPokemonID"),   // +0x34
            .uint8(name: "reversePattern"),     // +0x36
            .array(name: "unknown5", count: 1, of: .uint8),  // +0x37 alignment before walkCount
            .uint32(name: "walkCount"),         // +0x38..0x3C
        ]
    )

    /// JP save section 0 — 0x80, 8 bytes shorter than the international
    /// 0x88. The international builds added the f64 `playTimeIntl`; the JP
    /// build only has the f32 `playTimeJP` at +0x20, which is the live
    /// field on a JP save (the US save's f32 there is 0 while its f64
    /// holds the real total, and vice versa). Every named field keeps its
    /// offset; the trailing `unknown3` is opaque on both builds, so the
    /// 8 bytes are accounted for either way.
    static let saveConfigStructJP = StructMap(
        name: "XDSaveConfigJP",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "gcGameIndex", typeName: "GameVersion"),
            .uint8(name: "genId"),
            .abstraction(name: "region", typeName: "Region"),
            .abstraction(name: "langAreaId", typeName: "Language"),
            .array(name: "unknown1", count: 0x1C, of: .uint8),   // +0x04..0x20
            .losslessFloat(name: "playTimeJP"),                  // +0x20 the live play time on JP
            .uint32(name: "prevFloorId"),                        // +0x24
            .uint8(name: "floorPosIndex"),                       // +0x28
            .uint8(name: "optionNoVibration"),                   // +0x29
            .uint8(name: "optionAudio"),                         // +0x2A
            .abstraction(name: "playerLanguage", typeName: "Language"), // +0x2B
            .array(name: "unknown2", count: 0x04, of: .uint8),   // +0x2C..0x30
            .array(name: "unknown3", count: 0x50, of: .uint8),   // +0x30..0x80
        ]
    )

    /// JP save section 2 — 0xBC0C, 68 bytes shorter than the
    /// international 0xBC50. The boxes are identical (8 × 0x170C, same
    /// 8-unit names — JP ships them as ボックス１..ボックス８) and the
    /// shared 235-slot item pool is unchanged; the JP section simply ends
    /// there, without the international build's trailing flag word and
    /// 0x40 on-card region.
    static let savePCBoxStructJP = StructMap(
        name: "XDSavePCBoxJP",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "boxes", count: 8, of: .subStruct(name: "XDBox")),          // 0x0000..0xB860
            .array(name: "storedItems", count: 235, of: .subStruct(name: "XDItem")), // 0xB860..0xBC0C
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
