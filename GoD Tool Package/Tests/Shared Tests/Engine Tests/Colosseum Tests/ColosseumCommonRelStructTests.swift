//
//  ColosseumCommonRelStructTests.swift
//  ColosseumTests
//
//  Pins Colosseum's common.rel table structs to the strides the REL's own
//  count words give them (chunk length ÷ count, identical on the US, PAL and
//  JP discs) and to the field offsets the byte scans and the identifiable
//  accessors established. A drift here means a definition no longer tiles
//  its table.
//

import XCTest
import Structs
import GoDEngine
@testable import Colosseum

final class ColosseumCommonRelStructTests: XCTestCase {

    private func definition(_ name: String) throws -> StructDefinition {
        try ColosseumEngine.defaults().getStruct(name)
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

    /// Every table's stride, as measured on all three discs.
    func testEveryTableStructTilesItsMeasuredStride() throws {
        let strides: [(name: String, length: Int)] = [
            ("LegendaryPokemon", 2), ("Pokeface", 8), ("PeopleID", 8), ("TrainerClass", 12),
            ("KeyboardCharacter", 2), ("BattleStyle", 8), ("Multiplier", 2), ("MetLocation", 8),
            ("SoundFile", 8), ("AIWeightEffect", 0x14), ("PokemonAIRole", 0x14), ("Treasure", 0x1C),
            ("Door", 0x18), ("InteractionPoint", 0x1C), ("BattleType", 0x20),
            ("BattleField", 0x18), ("BattleFieldEU", 0x28),
            ("BattlePlayer", 8), ("Battle", 0x38), ("BattleEU", 0x48),
            ("Trainer", 0x34), ("PokemonIVs", 6), ("TrainerPokemonMove", 8), ("TrainerPokemonData", 0x50),
            ("TrainerAIData", 0x28), ("ShadowPokemonFlags", 8), ("ShadowData", 0x38),
            ("RoomScriptFunction", 4), ("Room", 0x4C), ("RoomEU", 0x5C),
            ("Move", 0x38), ("Nature", 0x28),
            ("PokemonBaseStats", 0x0C), ("PokemonEvolution", 6), ("PokemonLevelUpMove", 4),
            ("PokemonSprite", 8), ("PokemonStat", 0x11C),
            ("CharacterModel", 0x2C),
        ]
        for (name, expected) in strides {
            XCTAssertEqual(try length(name), expected, name)
        }
    }

    func testSpeciesFieldOffsets() throws {
        try assertOffsets("PokemonStat", [
            ("base_exp_yield", 0x06), ("height", 0x0A), ("weight", 0x0C), ("cry_id", 0x0E),
            ("national_dex_index", 0x10), ("pokedex_number", 0x14), ("name_id", 0x18),
            ("caught_flag_id", 0x28), ("model_index", 0x2C), ("type_1", 0x30), ("ability_1", 0x32),
            ("learnable_tms", 0x34), ("egg_group_1", 0x6E), ("wild_item_1", 0x70), ("egg_moves", 0x74),
            ("base_stats", 0x84), ("ev_yields", 0x90), ("evolutions", 0x9C),
            ("level_up_moves", 0xBA), ("sprites", 0x10C), ("shiny_sprites", 0x114),
        ])
    }

    func testRoomFieldOffsets() throws {
        try assertOffsets("Room", [
            ("kind", 0x00), ("area", 0x01), ("fsys_id", 0x06), ("room_id", 0x0C),
            ("render_data_pointer", 0x10), ("camera_data_pointer", 0x1C), ("name_id", 0x24),
            ("script_functions", 0x28), ("preprocess_function", 0x3C), ("unknown_data_pointer", 0x48),
        ])
        try assertOffsets("RoomEU", [
            ("room_id", 0x08), ("render_data_pointer", 0x0C), ("name_id", 0x20),
            ("script_functions", 0x24), ("preprocess_function", 0x38), ("unknown_data_pointer", 0x44),
            ("fsys_id_us_uk", 0x48), ("fsys_id_spanish", 0x58),
        ])
    }

    func testBattleFieldOffsets() throws {
        let head: [(field: String, offset: Int)] = [
            ("battle_kind", 0x00), ("battle_style", 0x01), ("battle_field_index", 0x04),
            ("name_id", 0x08), ("bgm_id", 0x0C), ("colosseum_round_id", 0x14),
        ]
        try assertOffsets("Battle", head + [("players", 0x18)])
        try assertOffsets("BattleEU", head + [("colosseum_round_id_german", 0x18), ("players", 0x28)])
        try assertOffsets("BattleField", [("terrain", 0x00), ("room_id", 0x02), ("name_id", 0x04), ("intro_wzx_id", 0x08), ("bgm_id", 0x0C), ("side_ids", 0x14)])
        try assertOffsets("BattleFieldEU", [("name_id", 0x04), ("side_ids", 0x10), ("intro_wzx_id_english", 0x14), ("intro_wzx_id_spanish", 0x24)])
    }

    func testTrainerFieldOffsets() throws {
        try assertOffsets("Trainer", [
            ("trainer_class", 0x02), ("first_pokemon_index", 0x04), ("ai_index", 0x06),
            ("name_id", 0x08), ("model_id", 0x10), ("items", 0x14), ("pre_battle_text_id", 0x24),
        ])
        try assertOffsets("TrainerPokemonData", [
            ("happiness", 0x08), ("species", 0x0A), ("pokeball", 0x0C), ("held_item", 0x10),
            ("name_id", 0x14), ("ivs", 0x1C), ("evs", 0x22), ("moves", 0x30),
        ])
        try assertOffsets("ShadowData", [
            ("species", 0x02), ("heart_gauge", 0x08), ("flag_ids", 0x10), ("debug_name_id", 0x20),
        ])
    }

    /// The typed-data path resolves a table's struct through the game engine
    /// alone, so every enum these structs name has to be one the Colosseum
    /// engine itself carries — `getStruct` throws otherwise.
    func testEveryCommonRelStructResolvesThroughTheColosseumEngineAlone() throws {
        for name in [
            "LegendaryPokemon", "Pokeface", "PeopleID", "TrainerClass", "KeyboardCharacter", "BattleStyle",
            "Multiplier", "MetLocation", "SoundFile", "AIWeightEffect", "PokemonAIRole", "Treasure", "Door",
            "InteractionPoint", "BattleType", "BattleField", "BattleFieldEU", "BattlePlayer", "Battle", "BattleEU",
            "Trainer", "PokemonIVs", "TrainerPokemonMove", "TrainerPokemonData", "TrainerAIData",
            "ShadowPokemonFlags", "ShadowData", "RoomScriptFunction", "Room", "RoomEU", "Move", "Nature",
            "PokemonBaseStats", "PokemonEvolution", "PokemonLevelUpMove", "PokemonSprite", "PokemonStat",
            "CharacterModel",
        ] {
            XCTAssertNoThrow(try definition(name), name)
        }
    }
}
