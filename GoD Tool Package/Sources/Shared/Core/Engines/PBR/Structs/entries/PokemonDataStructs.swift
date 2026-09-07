import Foundation
import Structs

/// Per-species tables in `common.fsys`: stats, evolutions, level-up moves,
/// and the menu icon/face/body index tables.
///
/// Field layouts are ported from the legacy tool's
/// `Revolution Tool CL/structs/*.swift`. The legacy definitions relied on
/// C-style auto-alignment; here every implicit pad is written out so the
/// offsets are readable, and each struct's total length is pinned against
/// the real PAL stride by `PBRCommonTableStructTests`.
public extension PBRStructDefaults {

    /// Base stats and species metadata (0x34 / 52 bytes). US/PAL layout —
    /// the JP disc drops `japanese_name_message_id` and splits the two
    /// trailing bytes differently, so a JP build needs its own struct.
    static let pokemonStatsStruct = StructMap(
        name: "PBRPokemonStats",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: TM/HM compatibility, 128 bits. Bit order within the
            // four words is unconfirmed (the legacy tool flagged the same).
            .array(name: "tm_hm_flags", count: 16, of: .uint8),

            // 0x10: Items the species may hold when caught in the wild.
            .abstraction(name: "wild_item_1", typeName: "Items"),
            .abstraction(name: "wild_item_2", typeName: "Items"),

            // 0x14: Height in decimetres, weight in hectograms — both the
            // real value × 10.
            .uint16(name: "height"),
            .uint16(name: "weight"),

            // 0x18: Message-table ids for the species name.
            .uint16(name: "name_message_id"),
            .uint16(name: "japanese_name_message_id"),

            // 0x1C: Row of the model table (`PBRPokemonModel`) holding this
            // species' first model.
            .uint16(name: "model_index"),

            // 0x1E: Base stats.
            .uint8(name: "base_hp"),
            .uint8(name: "base_attack"),
            .uint8(name: "base_defense"),
            .uint8(name: "base_speed"),
            .uint8(name: "base_special_attack"),
            .uint8(name: "base_special_defense"),

            // 0x24: Typing. Both bytes hold the same value for a
            // single-typed species.
            .abstraction(name: "type_1", typeName: "Type"),
            .abstraction(name: "type_2", typeName: "Type"),

            // 0x26
            .uint8(name: "catch_rate"),
            .uint8(name: "base_experience"),

            // 0x28: EV yield, 2 bits per stat, packed HP → Sp.Def from the
            // high bits down.
            .uint16(name: "ev_yields"),

            // 0x2A
            .uint8(name: "gender_ratio"),
            .uint8(name: "egg_cycles"),
            .uint8(name: "base_happiness"),
            .uint8(name: "level_up_rate"),

            // 0x2E: Breeding compatibility groups.
            .uint8(name: "egg_group_1"),
            .uint8(name: "egg_group_2"),

            // 0x30
            .abstraction(name: "ability_1", typeName: "Abilities"),
            .abstraction(name: "ability_2", typeName: "Abilities"),
            .uint8(name: "safari_zone_flee_rate"),

            // 0x33: Pokédex color category. The lowest bit is used for
            // something else, per the legacy tool.
            .uint8(name: "color_data"),
        ],
        description: "Base stats, typing, breeding and Pokédex metadata for one species. US/PAL layout."
    )

    /// One evolution branch (6 bytes).
    static let evolutionStruct = StructMap(
        name: "PBREvolution",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            // 0x00: How the evolution triggers.
            .uint16(name: "method"),
            // 0x02: Meaning depends on the method — the level for level-up,
            // the item id for evolution stones, and so on.
            .uint16(name: "condition"),
            // 0x04: Species evolved into.
            .abstraction(name: "evolved_species", typeName: "PokemonSpecies"),
        ],
        description: "One evolution branch: trigger, its parameter, and the resulting species."
    )

    /// A species' evolution branches (0x2A / 42 bytes) — 7 fixed slots.
    static let pokemonEvolutionsStruct = StructMap(
        name: "PBRPokemonEvolutions",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            .array(name: "evolutions", count: 7, of: .subStruct(name: "PBREvolution")),
        ],
        description: "Seven evolution slots for one species; unused slots are zeroed."
    )

    /// One level-up learnset entry (4 bytes).
    static let levelUpMoveStruct = StructMap(
        name: "PBRLevelUpMove",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "move", typeName: "Moves"),
            .uint8(name: "level"),
            // 0x03: Alignment filler (0xD0 on every slot of every row), not
            // the unknown field the legacy tool declared here.
            .padding(length: 1),
        ],
        description: "One move learned by level-up."
    )

    /// A species' level-up learnset (0x50 / 80 bytes) — 20 fixed slots.
    static let levelUpMovesStruct = StructMap(
        name: "PBRLevelUpMoves",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            .array(name: "level_up_moves", count: 20, of: .subStruct(name: "PBRLevelUpMove")),
        ],
        description: "Twenty level-up learnset slots for one species; unused slots are zeroed."
    )

    /// Menu icon file ids for one species (0x10 / 16 bytes). Faces come
    /// from `menu_face.fsys`, bodies from `menu_pokemon.fsys`.
    static let pokemonIconStruct = StructMap(
        name: "PBRPokemonIcon",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "male_face_file_id"),
            .uint32(name: "male_body_file_id"),
            .uint32(name: "female_face_file_id"),
            .uint32(name: "female_body_file_id"),
        ],
        description: "Menu face and body sprite file ids for a species, male and female."
    )

    /// Face-sprite index entry (0x08 / 8 bytes).
    static let pokemonFaceStruct = StructMap(
        name: "PBRPokemonFace",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "species"),
            // 0x04: Row of the icon table this species' sprites start at.
            .uint16(name: "icons_index"),
            // 0x06: Packed. Bits 15:1 are the form count, bit 0 appears to
            // mark a species that still has an evolution — flagged as
            // unconfirmed by the legacy tool.
            .uint16(name: "forms"),
        ],
        description: "Maps a species to its run of face sprites in the icon table."
    )

    /// Body-sprite index entry (0x0C / 12 bytes).
    static let pokemonBodyStruct = StructMap(
        name: "PBRPokemonBody",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "species"),
            .uint16(name: "icons_index"),
            .uint16(name: "form_count"),
            .array(name: "unknown_values", count: 2, of: .uint8),
            // 0x0A: Alignment filler (0xD0 on every row).
            .padding(length: 2),
        ],
        description: "Maps a species to its run of body sprites in the icon table."
    )

    /// One entry of the ability table's entry array (0x04 / 4 bytes).
    ///
    /// The abilities table is the one common table whose real records live
    /// outside the entry array: each ability's `TOKUSEI_<nnn>` name and its
    /// index sit in the shared name table (`PBRCommonTableNameRecord`),
    /// while the entry array — indexed by ability id — holds only the pair
    /// of message ids below.
    static let abilityMessageIDsStruct = StructMap(
        name: "PBRAbilityMessageIDs",
        wordSize: 2,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "name_message_id"),
            .uint16(name: "description_message_id"),
        ],
        description: "Name and description message ids for one ability, indexed by ability id."
    )
}
