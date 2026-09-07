import Foundation
import Structs

/// The Pokémon model table — `common.fsys` member 6 on US/PAL discs, 12 on
/// JP — and its two body-map sub-structs.
///
/// This is the indirection that lets PBR drive an arbitrary skeleton with
/// shared battle code. Nothing at runtime refers to a bone or an action by
/// name: battle code asks for "bone slot N" or "animation slot N", and the
/// row for the Pokémon being rendered converts that fixed role into an index
/// into *that model's* own skeleton and action list. Replace a model without
/// re-pointing the slots and the effects attach to whatever bone happens to
/// sit at the old index — and, because four of the bone slots are the
/// camera's framing targets, the camera aims at the wrong place too.
///
/// Layout verified against all 670 rows of the PAL disc (RPBP01).
public extension PBRStructDefaults {

    /// One row of the Pokémon model table (0x48 / 72 bytes).
    static let pokemonModelStruct = StructMap(
        name: "PBRPokemonModel",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            // 0x00: Packed parameters.
            //   bits 7:4 — size / scale class. Values 0 and 2…12 occur on
            //              the PAL disc; 1 does not, and bits 3, 1 and 0 are
            //              never set. PBRHex writes 0x60 for a new row.
            //   bit  2   — this row is the female-specific model (93 of 670
            //              rows). Row lookup matches species + form and then
            //              this bit, so a species with a female variant has
            //              two rows.
            .uint8(name: "parameters"),

            // 0x01: Alignment filler. The packer fills intra-entry gaps with
            // 0xD0 rather than zero — 14 of the 33 tables contain such runs —
            // so these three bytes are 0xD0 in every row, not a field.
            .padding(length: 3),

            // 0x04: Registry id of the FSYS archive holding the model, or 0
            // on the 25 placeholder rows. The PAL disc ships 495 model
            // archives: `pkx_001`…`pkx_493` take ids 5001…5493, so for a
            // real species the id is 5000 + its dex number, and the two
            // extra archives (`pkx_600`, `pkx_601`) continue the sequence
            // at 5494 and 5495 rather than following their filenames.
            .uint32(name: "fsys_id"),

            // 0x08: File within that archive: the entry's 16-bit identifier
            // in the high halfword and its FSYS file type (0x0400, the
            // `.sdr` model type) in the low halfword.
            .uint32(name: "model_file_id"),

            // 0x0C: Same encoding, for the shiny coloring of the model.
            // Both models share this row, so they share its bone and
            // animation maps.
            .uint32(name: "shiny_model_file_id"),

            // 0x10: Movement speed used by the run animation. 53 distinct
            // values on the PAL disc, from 0 up.
            .float(name: "run_speed"),

            // 0x14: Species this row renders. Mostly the national dex
            // number, but the 26 rows at the end of the table use ids above
            // 493 (494, 601, 1000…1011) for non-species models, so it is a
            // model id rather than strictly a dex number.
            .abstraction(name: "species", typeName: "PokemonSpecies"),

            // 0x16: Zero in all 670 rows.
            .padding(length: 2),

            // 0x18: Form index within the species. 0…27 on the PAL disc.
            .uint8(name: "form_index"),

            // 0x19: Bone slots — role → index into this model's skeleton.
            .subStruct(name: "bones", typeName: "PBRModelBoneMap"),

            // 0x32: Animation slots — role → index into this model's
            // action list.
            .subStruct(name: "animations", typeName: "PBRModelAnimationMap"),
        ],
        description: "One Pokémon model: which archive and file hold the model, how it moves, and the bone/animation maps that bind engine roles to this skeleton's own indexes."
    )

    /// Bone slots (0x19 / 25 bytes) — each byte is an index into the
    /// model's skeleton, addressed by role.
    ///
    /// Names were derived by resolving every slot of 321 PAL rows against
    /// the bone names inside the `.sdr` each row points at; the comment on
    /// each field gives the bone names actually seen there, most common
    /// first. Retail models prefix effect attachment points with `ef_` and
    /// camera targets with `ct_`, and name anatomy in romaji (`ef_tsuno`
    /// horn, `ef_o` tail/origin).
    ///
    /// A model that lacks a given part points the slot at a stand-in — a
    /// wingless Pokémon's `left_hand` may be its mouth bone, a legless one's
    /// feet may be its body center. Unused slots point at the root.
    static let modelBoneMapStruct = StructMap(
        name: "PBRModelBoneMap",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            // 0x00: ef_damage — where hit effects spawn.
            .uint8(name: "damage_effect"),
            // 0x01: ef_mouth — beams, breath, ingestion effects.
            .uint8(name: "mouth"),
            // 0x02: ef_leye, else ef_eye on single-eye rigs.
            .uint8(name: "left_eye"),
            // 0x03: ef_reye, else ef_eye.
            .uint8(name: "right_eye"),
            // 0x04: the model's root — `world` on most rigs, otherwise the
            // top bone, which retail names after the species.
            .uint8(name: "root"),
            // 0x05: ef_lhand, else ef_lfhand (fore-paw) or ef_lwing.
            .uint8(name: "left_hand"),
            // 0x06: ef_rhand, else ef_rfhand or ef_rwing.
            .uint8(name: "right_hand"),
            // 0x07: ef_lffoot, else ef_foot, else ef_o on legless rigs.
            .uint8(name: "left_foot"),
            // 0x08: ef_rffoot, else ef_foot, else ef_o.
            .uint8(name: "right_foot"),
            // 0x09: ef_o or ef_hip — the body's center of mass.
            .uint8(name: "body_center"),
            // 0x0A: ct_all_move — camera target for full-body framing
            // during a move. ct_all_move on all 321 models checked.
            .uint8(name: "camera_target_all_move"),
            // 0x0B: ef_head, else ef_tsuno (horn) or ef_top.
            .uint8(name: "head"),
            // 0x0C: second right-hand slot; ef_rhand / ef_rfhand.
            .uint8(name: "right_hand_alt"),
            // 0x0D: second right-foot slot; ef_rffoot.
            .uint8(name: "right_foot_alt"),
            // 0x0E: ef_top / ef_tsuno where present, else the root.
            .uint8(name: "top_alt"),
            // 0x0F: secondary left attachment — ef_lwing, ef_lo — else root.
            .uint8(name: "left_alt"),
            // 0x10: secondary right attachment — ef_rwing, ef_ro — else root.
            .uint8(name: "right_alt"),
            // 0x11: ef_lmfoot on many-legged rigs, else the root.
            .uint8(name: "left_middle_foot"),
            // 0x12: ef_rmfoot on many-legged rigs, else the root.
            .uint8(name: "right_middle_foot"),
            // 0x13: ef_damage again — holds the same index as slot 0x00 on
            // every model checked.
            .uint8(name: "damage_effect_alt"),
            // 0x14: direct_set — direct_set on all 321 models checked.
            .uint8(name: "direct_set"),
            // 0x15: ct_bust — camera target for close-up / portrait framing.
            .uint8(name: "camera_target_bust"),
            // 0x16: ct_bust_move — close-up framing during a move.
            .uint8(name: "camera_target_bust_move"),
            // 0x17: ct_all — camera target for full-body framing.
            // ct_all on all 321 models checked.
            .uint8(name: "camera_target_all"),
            // 0x18: ct_all_move again — same bone as slot 0x0A.
            .uint8(name: "camera_target_all_move_alt"),
        ],
        description: "Bone slots: engine role → index into this model's skeleton. The camera_target_* slots are what let the camera frame an arbitrary model."
    )

    /// Animation slots (0x16 / 22 bytes) — each byte is an index into the
    /// model's action list, addressed by role. 0xFF means "no animation";
    /// retail uses it only for the three `tx_` face animations, which a
    /// model may legitimately lack.
    ///
    /// Names below give the action names actually found in the 321 PAL
    /// models checked, most common first. Retail action names are romaji:
    /// `wait` idle, `kime` a finishing pose (special move), `tackle` the
    /// generic physical attack, `down` fainting, `kuchu_wait` midair idle,
    /// `kyukoka` rapid descent.
    static let modelAnimationMapStruct = StructMap(
        name: "PBRModelAnimationMap",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            // 0x00: wait — the battle idle every other slot falls back to.
            .uint8(name: "battle_idle"),
            // 0x01: kime / kime_a — special (non-contact) move.
            .uint8(name: "special_move"),
            // 0x02: tackle / kime_phy — generic physical move.
            .uint8(name: "physical_move"),
            // 0x03: punch where the rig has one, else tackle / kime_phy.
            .uint8(name: "punch"),
            // 0x04: kick where the rig has one, else tackle / kime_phy.
            .uint8(name: "kick"),
            // 0x05: takeoff on models that fly, else the idle.
            .uint8(name: "fly_into_air"),
            // 0x06: kyukoka (dive) on models that fly, else the idle.
            .uint8(name: "dive_from_air"),
            // 0x07: second punch slot; punch / tackle / kime_phy.
            .uint8(name: "punch_alt"),
            // 0x08: damage — flinch on taking a hit.
            .uint8(name: "take_damage"),
            // 0x09: down — fainting. `down` on all 321 models checked.
            .uint8(name: "faint"),
            // 0x0A: kuchu_wait — midair idle for levitating models, else
            // the ground idle.
            .uint8(name: "hover_in_air"),
            // 0x0B: second special-move slot; kime / kime_a, else the idle.
            .uint8(name: "special_move_alt"),
            // 0x0C: purpose unidentified — the idle on most models.
            .uint8(name: "unknown_idle_1"),
            // 0x0D: purpose unidentified — the idle on most models.
            .uint8(name: "unknown_idle_2"),
            // 0x0E: purpose unidentified — the idle on most models.
            .uint8(name: "unknown_idle_3"),
            // 0x0F: purpose unidentified — the idle on most models.
            .uint8(name: "unknown_idle_4"),
            // 0x10: status move. Retail points it at the idle on nearly
            // every model, so the naming comes from the legacy tool rather
            // than from the data.
            .uint8(name: "status_move"),
            // 0x11: run — used when entering the field.
            .uint8(name: "running"),
            // 0x12: summary-screen idle. The battle idle on nearly every
            // model; naming again from the legacy tool.
            .uint8(name: "summary_screen_idle"),
            // 0x13: tx_wink — blink. 0xFF on models with no face rig.
            .uint8(name: "blink"),
            // 0x14: tx_sleep. 0xFF where absent.
            .uint8(name: "sleeping"),
            // 0x15: tx_wakeup. 0xFF where absent.
            .uint8(name: "wake_up"),
        ],
        description: "Animation slots: engine role → index into this model's action list. 0xFF means the model has no animation for that role."
    )
}
