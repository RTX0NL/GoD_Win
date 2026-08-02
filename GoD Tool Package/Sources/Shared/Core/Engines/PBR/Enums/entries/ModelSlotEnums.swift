import Foundation
import Structs

/// Slot roles for the Pokémon model body map (`PBRPokemonModel`).
///
/// Battle code never names a bone or an animation — it asks for "bone slot
/// N" or "animation slot N" and the model table converts that fixed role
/// into an index into *this* model's skeleton or action list. These enums
/// name the roles, so a tool can address a slot by meaning rather than by
/// magic number; `PBRModelBoneMap` / `PBRModelAnimationMap` expose the same
/// roles as struct fields.
///
/// Roles were derived by resolving every slot of 321 real PAL model-table
/// rows against the bone and action names inside the `.sdr` each row points
/// at. Retail models name their bones and actions in romaji (`atama` head,
/// `mune` chest, `ef_tsuno` horn, `kime` finishing pose, `kuchu` midair,
/// `kyukoka` rapid descent), and the `ef_` / `ct_` prefixes mark effect
/// attachment points and camera targets respectively.
public extension PBREnumDefaults {

    /// Bone-map slot index → role. 25 slots, at `PBRPokemonModel` +0x19.
    ///
    /// The `CameraTarget*` slots are what let the camera frame an arbitrary
    /// model: `Bust` is the close-up framing target, `All` the full-body
    /// one, and the `Move` variants the targets used while an attack plays.
    /// Point them at the wrong bone and a replacement model is framed at
    /// its feet or off-screen.
    static let modelBoneSlot = Enum(
        name: "PBRModelBoneSlot",
        allowUnknownCases: true,
        values: [
            .init(name: "DamageEffect",          rawValue: 0x00), // ef_damage      312/321
            .init(name: "Mouth",                 rawValue: 0x01), // ef_mouth       313/321
            .init(name: "LeftEye",               rawValue: 0x02), // ef_leye        296/321
            .init(name: "RightEye",              rawValue: 0x03), // ef_reye        296/321
            .init(name: "Root",                  rawValue: 0x04), // world / model root bone
            .init(name: "LeftHand",              rawValue: 0x05), // ef_lhand / ef_lfhand / ef_lwing
            .init(name: "RightHand",             rawValue: 0x06), // ef_rhand / ef_rfhand / ef_rwing
            .init(name: "LeftFoot",              rawValue: 0x07), // ef_lffoot / ef_foot
            .init(name: "RightFoot",             rawValue: 0x08), // ef_rffoot / ef_foot
            .init(name: "BodyCentre",            rawValue: 0x09), // ef_o / ef_hip
            .init(name: "CameraTargetAllMove",   rawValue: 0x0A), // ct_all_move    321/321
            .init(name: "Head",                  rawValue: 0x0B), // ef_head / ef_tsuno / ef_top
            .init(name: "RightHandAlt",          rawValue: 0x0C), // ef_rhand / ef_rfhand
            .init(name: "RightFootAlt",          rawValue: 0x0D), // ef_rffoot
            .init(name: "TopAlt",                rawValue: 0x0E), // ef_top / ef_tsuno, else root
            .init(name: "LeftAlt",               rawValue: 0x0F), // ef_lwing / ef_lo, else root
            .init(name: "RightAlt",              rawValue: 0x10), // ef_rwing / ef_ro, else root
            .init(name: "LeftMiddleFoot",        rawValue: 0x11), // ef_lmfoot, else root
            .init(name: "RightMiddleFoot",       rawValue: 0x12), // ef_rmfoot, else root
            .init(name: "DamageEffectAlt",       rawValue: 0x13), // ef_damage, same value as slot 0
            .init(name: "DirectSet",             rawValue: 0x14), // direct_set     321/321
            .init(name: "CameraTargetBust",      rawValue: 0x15), // ct_bust        319/321
            .init(name: "CameraTargetBustMove",  rawValue: 0x16), // ct_bust_move   319/321
            .init(name: "CameraTargetAll",       rawValue: 0x17), // ct_all         321/321
            .init(name: "CameraTargetAllMoveAlt", rawValue: 0x18), // ct_all_move   321/321
        ],
        propertyType: .uint8
    )

    /// Animation-map slot index → role. 22 slots, at `PBRPokemonModel`
    /// +0x32. A slot holding 0xFF means "no animation" — retail uses that
    /// only for the three `tx_` face animations (slots 0x13–0x15), which
    /// are the ones a model may legitimately lack.
    static let modelAnimationSlot = Enum(
        name: "PBRModelAnimationSlot",
        allowUnknownCases: true,
        values: [
            .init(name: "BattleIdle",         rawValue: 0x00), // wait       317/321
            .init(name: "SpecialMove",        rawValue: 0x01), // kime / kime_a
            .init(name: "PhysicalMove",       rawValue: 0x02), // tackle / kime_phy
            .init(name: "Punch",              rawValue: 0x03), // tackle / punch / kime_phy
            .init(name: "Kick",               rawValue: 0x04), // tackle / kick / kime_phy
            .init(name: "FlyIntoAir",         rawValue: 0x05), // takeoff, else falls back to wait
            .init(name: "DiveFromAir",        rawValue: 0x06), // kyukoka, else falls back to wait
            .init(name: "PunchAlt",           rawValue: 0x07), // tackle / punch / kime_phy
            .init(name: "TakeDamage",         rawValue: 0x08), // damage     315/321
            .init(name: "Faint",              rawValue: 0x09), // down       321/321
            .init(name: "HoverInAir",         rawValue: 0x0A), // kuchu_wait, else wait
            .init(name: "SpecialMoveAlt",     rawValue: 0x0B), // kime / kime_a, else wait
            .init(name: "UnknownIdle1",       rawValue: 0x0C), // mostly wait / wait_a
            .init(name: "UnknownIdle2",       rawValue: 0x0D), // mostly wait
            .init(name: "UnknownIdle3",       rawValue: 0x0E), // mostly wait
            .init(name: "UnknownIdle4",       rawValue: 0x0F), // mostly wait
            .init(name: "StatusMove",         rawValue: 0x10), // wait on nearly every model
            .init(name: "Running",            rawValue: 0x11), // run        315/321
            .init(name: "SummaryScreenIdle",  rawValue: 0x12), // wait       317/321
            .init(name: "Blink",              rawValue: 0x13), // tx_wink    297/321, 21× none
            .init(name: "Sleeping",           rawValue: 0x14), // tx_sleep   302/321, 18× none
            .init(name: "WakeUp",             rawValue: 0x15), // tx_wakeup  301/321, 18× none
        ],
        propertyType: .uint8
    )
}
