import Structs
import GoDFoundation

/// Struct definitions for the per-deck section rows: DTNR (trainer),
/// DPKM (deck pokemon), DTAI (trainer AI), DDPK (shadow pokemon).
///
/// These are byte-faithful mirrors of the in-game records, with property
/// names chosen so the combined `Trainer` struct in the Pokemon engine
/// can absorb fields by direct name + type match. Bit-packed bytes
/// (PID, combo flags, AI flag bytes, stat-stage ranges) stay as raw
/// integers here — semantic breakouts live in the editor layer.
public extension XDStructDefaults {

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
            .padding(length: 2),
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
            .uint16(name: "species"),
            .uint8(name: "level"),
            .uint8(name: "happiness"),
            .uint16(name: "item"),
            .uint8(name: "aiRole",
                   description: "Index into common.rel AIPokemonRoles."),
            .uint8(name: "isKeyStrategicPokemon"),
            .array(name: "ivs", count: 6, of: .uint8,
                   description: "HP/Atk/Def/SpA/SpD/Spe."),
            .array(name: "evs", count: 6, of: .uint8),
            .array(name: "moves", count: 4, of: .uint16),
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
            .uint8(name: "pokemonSelectionFlags",
                   description: "Bitfield for pokemon-send-out behavior. See DeckTables.swift for the bit meanings."),
            .uint8(name: "moveSelectionFlags",
                   description: "Bitfield for move-pick behavior."),
            .padding(length: 2),
            .uint8(name: "atkStatStages",
                   description: "0x04 — high nibble = max stages (midpoint 6), low nibble = min stages."),
            .uint8(name: "defStatStages"),
            .uint8(name: "spAtkStatStages"),
            .uint8(name: "spDefStatStages"),
            .uint8(name: "speedStatStages"),
            .uint8(name: "accuracyStatStages",
                   description: "Unused at runtime per legacy notes."),
            .uint8(name: "evasionStatStages"),
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
            .uint8(name: "specialityPokemonType1"),
            .uint8(name: "specialityPokemonType2"),
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
            .array(name: "shadowMoves", count: 4, of: .uint16,
                   description: "Sealed move ids the pokemon retains in shadow form."),
            .uint8(name: "aggression",
                   description: "Lower value ⇒ enters Reverse Mode more often."),
            .boolean(name: "alwaysFleeToMirorB",
                     description: "When true the shadow pokemon flees to Miror B even if the player wins the snag battle."),
            .padding(length: 2),
        ],
        description: "DDPK row — single shadow pokemon entry (0x18 bytes per row)."
    )
}
