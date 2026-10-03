import Structs
import GoDFoundation

/// Combined Trainer schema, plus the substructs it nests. Properties are
/// chosen by name + type to overlap the underlying deck section structs
/// (DTNR, DPKM, DTAI, DDPK in the XD engine) so the trainer dump op can
/// fold individual rows into a single Trainer JSON via name/type match.
///
/// Anything that can be derived from another field (shadowMask is per-
/// slot `isShadow`, pokemon indexes are positional, AI index is
/// per-trainer, storyDeckSpeciesIndex equals `species`) is omitted.
public extension PokemonStructDefaults {

    /// One stat's AI range. Both nibbles are a stage count biased by 6, so
    /// 6 means "no change" and the pair spans -6…+9.
    static func statStageRange(name: String, description: String? = nil) -> StructMap.Property {
        .bits(name: name, description: description, fields: [
            .number(name: "maxStages", bits: 0...3, description: "Highest stage the AI will drive the stat to; midpoint 6"),
            .number(name: "minStages", bits: 4...7, description: "Lowest stage it will accept; midpoint 6"),
        ])
    }

    /// Top-level combined Trainer record. One JSON file per row in the
    /// deck's DTNR section.
    static let trainerStruct = StructMap(
        name: "Trainer",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // From DTNR (less stringID, padding, shadowMask, pokemonIndexes, aiIndex)
            .uint8(name: "trainerClass"),
            .uint16(name: "nameID"),
            .uint16(name: "trainerModel"),
            .uint16(name: "cameraEffect"),
            .uint16(name: "preBattleTextID"),
            .uint16(name: "victoryTextID"),
            .uint16(name: "defeatTextID"),
            .array(name: "comboIDs", count: 4, of: .uint16),
            .array(name: "activeCombos", count: 4, of: .uint8),

            // Inlined team and AI
            .array(name: "team", count: 6,
                   of: .subStruct(name: "TrainerTeamSlot")),
            .subStruct(name: "ai", typeName: "TrainerAI"),
        ],
        description: "Combined trainer record — DTNR fields + inlined per-slot team (DPKM + optional DDPK) + inlined DTAI."
    )

    /// One slot of the team — the union of DPKM fields and (when shadow)
    /// DDPK fields. `isShadow` discriminates which subset is meaningful;
    /// non-shadow slots leave the DDPK fields zero.
    static let trainerTeamSlotStruct = StructMap(
        name: "TrainerTeamSlot",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // From DPKM
            .uint16(name: "species"),
            .uint8(name: "level"),
            .uint8(name: "happiness"),
            .uint16(name: "item"),
            .uint8(name: "aiRole"),
            .abstraction(name: "keyPlayer", typeName: "DeckPokemonKeyPlayer"),
            .array(name: "ivs", count: 6, of: .uint8),
            .array(name: "evs", count: 6, of: .uint8),
            // Plain integers here: `Moves` is per game, and this cross-game
            // engine has no game to resolve it against.
            .array(name: "moves", count: 4, of: .uint16),
            .uint8(name: "unusedByte"),
            .uint8(name: "comboPartnerFlags"),
            .uint8(name: "pidByte"),
            .uint8(name: "settingsByte"),

            // Discriminator. Set when the trainer's `shadowMask` bit
            // for this slot is true — the disassembly confirms the
            // shadow-slot mechanism is universal across decks (every
            // `_fightTrainerCreateDeck*` variant routes through
            // `DeckTrainer::getDarkPokemonDataID`), so any deck's
            // trainer can carry shadow slots, not just DeckStory.
            .boolean(name: "isShadow"),
            // Stable DDPK index for shadow slots. Save files reference
            // shadow pokémon by this id, and the runtime DDPK lookup
            // (`deckGetDeckDarkPokemon`) hardcodes a 128-slot cap —
            // both reasons the rebuild must put the slot back at the
            // recorded position rather than re-allocating sequentially.
            // Zero when `isShadow == false`.
            .uint16(name: "darkPokemonID"),

            // From DDPK (zero unless isShadow == true)
            .uint8(name: "mirorBWeighting"),
            .uint8(name: "catchRate"),
            .uint8(name: "caughtLevel"),
            .uint8(name: "statusFlags"),
            .uint16(name: "heartGauge"),
            .uint16(name: "bonusExp"),
            .array(name: "shadowMoves", count: 4, of: .uint16),
            .abstraction(name: "aggression", typeName: "ReverseModeRate"),
            .boolean(name: "alwaysFleeToMirorB"),
        ],
        description: "Single trainer team slot — DPKM fields plus optional DDPK extension when isShadow is true. `darkPokemonID` carries the shadow's DDPK row index for stable round-trip."
    )

    /// Trainer AI block — semantic copy of DTAI without the binary
    /// padding so the JSON layout is editor-friendly.
    static let trainerAIStruct = StructMap(
        name: "TrainerAI",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "pokemonSelectionFlags"),
            .uint8(name: "moveSelectionFlags"),
            PokemonStructDefaults.statStageRange(name: "atkStatStages"),
            PokemonStructDefaults.statStageRange(name: "defStatStages"),
            PokemonStructDefaults.statStageRange(name: "spAtkStatStages"),
            PokemonStructDefaults.statStageRange(name: "spDefStatStages"),
            PokemonStructDefaults.statStageRange(name: "speedStatStages"),
            PokemonStructDefaults.statStageRange(name: "accuracyStatStages"),
            PokemonStructDefaults.statStageRange(name: "evasionStatStages"),
            .uint8(name: "maxTotalStatStages"),
            .uint8(name: "minTotalStatStages"),
            .uint8(name: "switchRate"),
            .uint8(name: "itemUseRate"),
            .uint8(name: "attackingMoveRate"),
            .uint8(name: "koRate"),
            .uint8(name: "lowHPRate"),
            .uint8(name: "lastPPRate"),
            .abstraction(name: "specialityPokemonType1", typeName: "Type"),
            .abstraction(name: "specialityPokemonType2", typeName: "Type"),
            .uint8(name: "specialityPokemonType1Rate"),
            .uint8(name: "specialityPokemonType2Rate"),
            .uint16(name: "specialityMoveType1"),
            .uint16(name: "specialityMoveType2"),
            .uint8(name: "specialityMoveType1Rate"),
            .uint8(name: "specialityMoveType2Rate"),
            .uint8(name: "correctionValue"),
        ],
        description: "Trainer AI block — DTAI fields with padding stripped."
    )
}
