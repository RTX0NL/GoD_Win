//
//  XDCommonRelStructTests.swift
//  XDTests
//
//  Pins the four common.rel tables that used to dump as raw chunks —
//  PokemonStats, Battles, Pokespots, Rooms — to the layouts the game's own
//  accessors read. Every stride is the multiplier in the table's `GetPtr`
//  routine and every offset is the displacement in a field getter, so a
//  drift here means the definition no longer describes the disc.
//

import XCTest
import Structs
import GoDEngine
@testable import XD

final class XDCommonRelStructTests: XCTestCase {

    private func definition(_ name: String) throws -> StructDefinition {
        try XDEngine.defaults().getStruct(name)
    }

    private func length(_ name: String) throws -> Int {
        try definition(name).length
    }

    private func assertOffsets(_ name: String, _ expected: [(field: String, offset: Int)]) throws {
        let definition = try definition(name)
        for (field, offset) in expected {
            XCTAssertEqual(definition.offset(for: field), offset, "\(name).\(field)")
        }
    }

    // MARK: - Species (pokemonDataBios*)

    func testSpeciesStructsTileTheAccessorStrides() throws {
        XCTAssertEqual(try length("PokemonBaseStats"), 0x0C, "pokemonDataBiosGetBasisStatusPtr stride")
        XCTAssertEqual(try length("PokemonEvolution"), 0x06, "pokemonDataBiosGetSinkaPtr stride")
        XCTAssertEqual(try length("PokemonLevelUpMove"), 0x04, "pokemonDataBiosGetGetWazaPtr stride")
        XCTAssertEqual(try length("PokemonSprite"), 0x08, "pokemonDataBiosGetCgDataPtr stride")
        XCTAssertEqual(try length("PokemonStat"), 0x124, "pokemonDataBiosGetPtr stride")
    }

    func testSpeciesFieldOffsetsMatchTheAccessors() throws {
        try assertOffsets("PokemonStat", [
            ("exp_rate", 0x00),            // pokemonDataBiosGetGrowDataId
            ("catch_rate", 0x01),          // pokemonDataBiosGetGet
            ("gender_ratio", 0x02),        // pokemonDataBiosGetSexRatio
            ("base_exp_yield", 0x04),      // pokemonDataBiosGetGiveExp
            ("base_friendship", 0x06),     // pokemonDataBiosGetInitFriend
            ("height", 0x08),              // pokemonDataBiosGetHeight
            ("weight", 0x0A),              // pokemonDataBiosGetWeight
            ("cry_id", 0x0C),              // pokemonDataBiosGetVoice
            ("pokemon_number", 0x12),      // pokemonDataBiosGetNumPokemon
            ("pokedex_number", 0x14),      // pokemonDataBiosGetNumZukan
            ("name_id", 0x18),             // pokemonDataBiosGetName
            ("species_name_id", 0x1C),     // pokemonDataBiosGetTypeName
            ("description_id", 0x20),      // pokemonDataBiosGetDoc
            ("seen_flag_id", 0x24),        // pokemonDataBiosGetMitaFlag
            ("caught_flag_id", 0x28),      // pokemonDataBiosGetTukamaetaFlag
            ("model_index", 0x2C),         // pokemonDataBiosGetPkxDataId
            ("type_1", 0x30),              // pokemonDataBiosGetZokuseiDataId
            ("ability_1", 0x32),           // pokemonDataBiosGetTokuseiDataId
            ("learnable_tms", 0x34),       // pokemonDataBiosGetWazaMcn
            ("learnable_tutor_moves", 0x6E), // pokemonDB_GetTeachWaza
            ("wild_item_1", 0x7A),         // pokemonDataBiosGetItemDataId
            ("egg_moves", 0x7E),           // pokemonDataBiosGetKowaza
            ("base_stats", 0x8E),          // pokemonDataBiosGetBasisStatusPtr(0)
            ("ev_yields", 0x9A),           // pokemonDataBiosGetBasisStatusPtr(1)
            ("evolutions", 0xA6),          // pokemonDataBiosGetSinkaPtr
            ("level_up_moves", 0xC4),      // pokemonDataBiosGetGetWazaPtr
            ("sprites", 0x114),            // pokemonDataBiosGetCgDataPtr(0)
            ("shiny_sprites", 0x11C),      // pokemonDataBiosGetCgDataPtr(1)
        ])
    }

    // MARK: - Battles (fightEncountDataBios*)

    func testBattleStructsTileTheAccessorStrides() throws {
        XCTAssertEqual(try length("BattlePlayer"), 0x08, "fightEncountDataBiosGetFightTrainerInfoPtr stride")
        XCTAssertEqual(try length("Battle"), 0x3C, "fightEncountDataBiosGetPtr stride (US/JP)")
        XCTAssertEqual(try length("BattleEU"), 0x4C, "PAL stride: four extra intro ids")
    }

    func testBattleFieldOffsetsMatchTheAccessors() throws {
        let head: [(field: String, offset: Int)] = [
            ("battle_kind", 0x00),         // fightEncountDataBiosGetFightKind
            ("trainers_per_side", 0x01),   // fightEncountDataBiosGetTrainer
            ("battle_style", 0x02),        // fightEncountDataBiosGetFightType (fightout count)
            ("pokemon_per_trainer", 0x03), // fightEncountDataBiosGetEntry
            ("blackout_on_loss", 0x04),    // fightEncountDataBiosGetZenmetuFlag
            ("battle_field_index", 0x06),  // fightEncountDataBiosGetFightFloorDataId
            ("battle_cd_id", 0x08),        // fightEncountDataBiosGetDiskId
            ("name_id", 0x0C),             // fightEncountDataBiosGetFightName
            ("bgm_id", 0x10),              // fightEncountDataBiosGetBgmSndId
            ("wipe_id", 0x14),             // fightEncountDataBiosGetWipeId
            ("intro_wzx_id", 0x18),        // fightEncountDataBiosGetSyoukaiWzxDataId
        ]
        try assertOffsets("Battle", head + [("players", 0x1C)])
        try assertOffsets("BattleEU", head + [
            ("intro_wzx_id_german", 0x1C),
            ("intro_wzx_id_spanish", 0x28),
            ("players", 0x2C),
        ])
        try assertOffsets("BattlePlayer", [("deck", 0), ("trainer_id", 2), ("controller", 4)])
    }

    // MARK: - Pokespots (esaba*)

    func testPokespotStructsTileTheAccessorStrides() throws {
        XCTAssertEqual(try length("Pokespot"), 0x1C, "esabaGet* stride")
        XCTAssertEqual(try length("PokespotEncounter"), 0x0C, "_esabaAppearPokemonSub2 stride")
        try assertOffsets("Pokespot", [
            ("snack_count_flag_id", 0x00),     // esabaGetEsaNum
            ("spawned_species_flag_id", 0x0C), // esabaGetPokemonID
            ("spawned_pid_flag_id", 0x10),     // esabaGetPokemonRnd
            ("encounter_table_pointer", 0x18), // esabaGetPokemonMax
        ])
        try assertOffsets("PokespotEncounter", [
            ("species", 0x02),
            ("encounter_rate", 0x04),
            ("steps_per_snack", 0x08),         // esabaGetDigestRate
        ])
    }

    // MARK: - Rooms (floorDataBios*)

    func testRoomStructsTileTheAccessorStrides() throws {
        XCTAssertEqual(try length("Room"), 0x40, "floorDataBiosGetPtr stride (US/PAL)")
        XCTAssertEqual(try length("RoomJP"), 0x30, "JP stride: one fsys id")
        try assertOffsets("Room", [
            ("kind", 0x01),                    // floorDataBiosGetFloorKind
            ("room_id", 0x02),                 // floorDataBiosGetFloorID
            ("map_file_id", 0x04),             // floorDataBiosGetMapResID
            ("render_data_pointer", 0x08),     // floorDataBiosGetLensFlareResID etc.
            ("character_data_pointer", 0x0C),  // floorDataBiosGetCharInfo
            ("warp_point_data_pointer", 0x10), // floorDataBiosGetPosListPtr
            ("camera_data_pointer", 0x14),     // floorDataBiosGetFieldCameraListPtr
            ("name_id", 0x18),                 // floorDataBiosGetPlaceName
            ("preprocess_function", 0x1C),     // floorDataBiosGetPreFunc
            ("main_function", 0x20),           // floorDataBiosGetMainFunc
            ("postprocess_function", 0x24),    // floorDataBiosGetPostFunc
            ("unknown_data_pointer", 0x28),
            ("fsys_id_us_uk", 0x2C),
            ("fsys_id_spanish", 0x3C),
        ])
        try assertOffsets("RoomJP", [
            ("room_id", 0x02),
            ("fsys_id", 0x04),
            ("map_file_id", 0x08),
            ("name_id", 0x1C),
            ("postprocess_function", 0x28),
            ("unknown_data_pointer", 0x2C),
        ])
    }

    /// The typed-data path resolves a table's struct through the game engine
    /// alone, so every enum these structs name has to be one the XD engine
    /// itself carries — `getStruct` throws otherwise.
    func testEveryCommonRelStructResolvesThroughTheXDEngineAlone() throws {
        for name in [
            "PokemonBaseStats", "PokemonEvolution", "PokemonLevelUpMove", "PokemonSprite", "PokemonStat",
            "BattlePlayer", "Battle", "BattleEU",
            "Pokespot", "PokespotEncounter",
            "Room", "RoomJP",
        ] {
            XCTAssertNoThrow(try definition(name), name)
        }
    }
}
