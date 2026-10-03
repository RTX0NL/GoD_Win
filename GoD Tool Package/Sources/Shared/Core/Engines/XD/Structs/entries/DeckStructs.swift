import Structs
import GoDFoundation

/// Struct definitions for the per-deck section rows: DTNR (trainer),
/// DPKM (deck pokemon), DTAI (trainer AI), DDPK (shadow pokemon).
///
/// These are byte-faithful mirrors of the in-game records, with property
/// names chosen so the combined `Trainer` struct in the Pokemon engine
/// can absorb fields by direct name + type match. The stat-stage ranges
/// are split into their two nibbles; the AI flag bytes stay raw, because
/// the bit positions in `DeckTrainer.md` are inferred rather than read
/// off an accessor.
public extension XDStructDefaults {

    /// One stat's AI range. Both nibbles are a stage count biased by 6, so
    /// 6 means "no change" and the pair spans -6…+9.
    static func statStageRange(name: String, description: String? = nil) -> StructMap.Property {
        .bits(name: name, description: description, fields: [
            .number(name: "maxStages", bits: 0...3, description: "Highest stage the AI will drive the stat to; midpoint 6"),
            .number(name: "minStages", bits: 4...7, description: "Lowest stage it will accept; midpoint 6"),
        ])
    }

    /// DTNR — single trainer entry. 0x38 bytes.
    static let deckTrainerStruct = StructMap(
        name: "DeckTrainer",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint16(name: "stringID",
                    description: "Pointer into the deck's DSTR table — the trainer's identity tag (e.g. 'D1_p_01')."),
            .padding(length: 2),
            .uint8(name: "shadowMask",
                   description: "Bit i set ⇒ slot i holds a DDPK index (shadow), else a DPKM index. LSB = slot 0."),
            .uint8(name: "trainerClass"),
            .uint16(name: "nameID",
                    description: "MSG id in common_rel.msg for the trainer's display name."),
            .padding(length: 4),
            .padding(length: 4),
            .uint16(name: "trainerModel"),
            .uint16(name: "cameraEffect",
                    description: "Selects a special camera animation for trainers with bespoke intros."),
            .uint16(name: "preBattleTextID",
                    description: "MSG id in fight_common.msg."),
            .uint16(name: "victoryTextID"),
            .uint16(name: "defeatTextID"),
            .padding(length: 2),
            .array(name: "pokemonIndexes", count: 6, of: .uint16,
                   description: "Per-slot index — DPKM if shadowMask bit cleared, else DDPK."),
            .uint16(name: "aiIndex"),
            .uint16(name: "fixedActionID",
                    description: "DeckTrainer::getFixedActionID; non-zero on 32 trainers"),
            .array(name: "comboIDs", count: 4, of: .uint16),
            .array(name: "activeCombos", count: 4, of: .uint8),
        ],
        description: "DTNR row — single trainer entry (0x38 bytes per row)."
    )

    /// DPKM — single deck pokemon. 0x20 bytes.
    static let deckTrainerPokemonStruct = StructMap(
        name: "DeckTrainerPokemon",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .abstraction(name: "species", typeName: "PokemonSpecies"),
            .uint8(name: "level"),
            .uint8(name: "happiness"),
            .abstraction(name: "item", typeName: "Items"),
            .uint8(name: "aiRole",
                   description: "Index into common.rel AIPokemonRoles."),
            .abstraction(name: "keyPlayer", typeName: "DeckPokemonKeyPlayer"),
            .array(name: "ivs", count: 6, of: .uint8,
                   description: "HP/Atk/Def/SpA/SpD/Spe."),
            .array(name: "evs", count: 6, of: .uint8),
            .array(name: "moves", count: 4, of: .enumeration(name: "Moves")),
            .uint8(name: "unusedByte",
                   description: "0x1C — repurposed by XG mods for shininess (low byte)."),
            .uint8(name: "comboPartnerFlags",
                   description: "0x1D — 4 bits naming which combo roles this pokemon can fill."),
            .uint8(name: "pidByte",
                   description: "0x1E — packed: bit 0 = useSecondAbility, bits 1-2 = gender, bits 3-7 = nature."),
            .uint8(name: "settingsByte",
                   description: "0x1F — bit 7 = use random nature/gender; XG mods reuse this for priority."),
        ],
        description: "DPKM row — single deck pokemon (0x20 bytes per row)."
    )

    /// DTAI — single trainer AI block. 0x20 bytes.
    static let deckTrainerAIStruct = StructMap(
        name: "DeckTrainerAI",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // One bit per decision knob, with a dedicated accessor each.
            // `Documentation/Assembly Analysis/Data Structures/
            // DeckTrainer.md` lists the accessors but marks the positions
            // "(inferred)", so the bytes stay whole until one is read off
            // an `rlwinm`.
            .uint8(name: "pokemonSelectionFlags",
                   description: "Bitfield for pokemon-send-out behavior; see DeckTrainer.md for the accessors."),
            .uint8(name: "moveSelectionFlags",
                   description: "Bitfield for move-pick behavior."),
            .padding(length: 2),
            XDStructDefaults.statStageRange(name: "atkStatStages", description: "0x04"),
            XDStructDefaults.statStageRange(name: "defStatStages"),
            XDStructDefaults.statStageRange(name: "spAtkStatStages"),
            XDStructDefaults.statStageRange(name: "spDefStatStages"),
            XDStructDefaults.statStageRange(name: "speedStatStages"),
            XDStructDefaults.statStageRange(name: "accuracyStatStages", description: "Unused at runtime per legacy notes."),
            XDStructDefaults.statStageRange(name: "evasionStatStages"),
            .padding(length: 1),
            .uint8(name: "maxTotalStatStages",
                   description: "Shifted-int with midpoint 42; range −42..+42."),
            .uint8(name: "minTotalStatStages"),
            .uint8(name: "switchRate",
                   description: "Percent. AI switch chance per turn."),
            .uint8(name: "itemUseRate"),
            .uint8(name: "attackingMoveRate"),
            .uint8(name: "koRate"),
            .uint8(name: "lowHPRate"),
            .uint8(name: "lastPPRate"),
            .abstraction(name: "specialityPokemonType1", typeName: "Type", description: "A move type the AI favors; None (9) for no preference"),
            .abstraction(name: "specialityPokemonType2", typeName: "Type"),
            .uint8(name: "specialityPokemonType1Rate"),
            .uint8(name: "specialityPokemonType2Rate"),
            .uint16(name: "specialityMoveType1"),
            .uint16(name: "specialityMoveType2"),
            .uint8(name: "specialityMoveType1Rate"),
            .uint8(name: "specialityMoveType2Rate"),
            .uint8(name: "correctionValue",
                   description: "Trailing scalar; purpose still undocumented."),
            .padding(length: 1),
        ],
        description: "DTAI row — single trainer AI entry (0x20 bytes per row)."
    )

    /// DDPK — single shadow pokemon. 0x18 bytes. Lives in DeckData_DarkPokemon.
    static let deckShadowPokemonStruct = StructMap(
        name: "DeckShadowPokemon",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint8(name: "mirorBWeighting",
                   description: "0 = never appears with Miror B. Higher = more common encounter."),
            .uint8(name: "catchRate",
                   description: "Overrides the species' base catch rate."),
            .uint8(name: "caughtLevel",
                   description: "Level the pokemon settles at after being snagged."),
            .uint8(name: "statusFlags",
                   description: "Bit 7 (0x80) = 'this DDPK slot is in use'."),
            .uint32(name: "storyDeckSpeciesIndex",
                    description: "DPKM index in DeckData_Story for the underlying pokemon data."),
            .uint16(name: "heartGauge",
                    description: "Initial dark-point counter; counts down toward 0 on purification."),
            .uint16(name: "bonusExp",
                    description: "Pooled experience to award on purification — usually 0 at dump time."),
            .array(name: "shadowMoves", count: 4, of: .enumeration(name: "Moves"),
                   description: "Sealed move ids the pokemon retains in shadow form."),
            .abstraction(name: "aggression", typeName: "ReverseModeRate",
                   description: "Lower value ⇒ enters Reverse Mode more often."),
            .boolean(name: "alwaysFleeToMirorB",
                     description: "When true the shadow pokemon flees to Miror B even if the player wins the snag battle."),
            .padding(length: 2),
        ],
        description: "DDPK row — single shadow pokemon entry (0x18 bytes per row)."
    )
}
