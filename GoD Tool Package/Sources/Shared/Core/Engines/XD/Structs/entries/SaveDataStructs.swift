import Structs
import GoDFoundation

/// Struct definitions for XD save-slot sections. Field offsets cross-
/// referenced against PKHeX's `SAV3XD.cs` and the legacy GoD tool's
/// `XGSaveManager.swift` constants. XD's section sizes are read from
/// the slot's own size table at runtime, so these structs only need
/// to cover the *known* prefix of each section — trailing bytes are
/// preserved through the build path's pad-from-raw-slot logic.
public extension XDStructDefaults {

    // MARK: - Pokemon

    /// XD Pokemon record (XK3 in PKHeX). 196 bytes per
    /// `PokeCrypto.SIZE_3XSTORED`. Internal field layout (species,
    /// stats, moves, IVs, EVs, shadow data, etc.) is a separate
    /// reverse-engineering effort — for now expose the raw bytes
    /// so party/box arrays at least have the correct length.
    static let savePokemonStruct = StructMap(
        name: "XDPokemon",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [.padding(length: 0xC4)]
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
            .padding(length: 0x1C),                      // +0x04..0x20
            .losslessFloat(name: "playTimeJP"),          // +0x20  (f32 BE, JP saves)
            .padding(length: 0x0C),                      // +0x24..0x30
            .losslessDouble(name: "playTimeIntl"),       // +0x30  (f64 BE, US/PAL)
            .padding(length: 0x50),                      // +0x38..0x88
        ]
    )

    // MARK: - Section 1: Trainer1

    /// XD save section 1 — Trainer1 / player profile. Per PKHeX:
    ///   - OT name           @ +0x000  (20 bytes / 10 chars `gsXD`)
    ///   - SID16             @ +0x02C
    ///   - TID16             @ +0x02E
    ///   - Party (6 × XK3)   @ +0x030  (6 × 0xC4 = 0x498)
    ///   - Gender            @ +0x8E0
    ///   - Money             @ +0x8E4
    ///   - Coupons           @ +0x8E8
    /// Section size is variable; this struct covers 0x8EC, leaving
    /// the rest to the build-path's pad-with-raw-slot fallback.
    static let saveTrainer1Struct = StructMap(
        name: "XDSaveTrainer1",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            // OT name — 10 chars × 2 bytes (UTF-16 BE), zero-padded
            // to fill the 20-byte field.
            .string(name: "OT", format: .gsXD, length: 10),          // +0x000..0x014
            .padding(length: 0x18),                                  // +0x014..0x02C
            .uint16(name: "SID16"),                                  // +0x02C
            .uint16(name: "TID16"),                                  // +0x02E
            .array(name: "party", count: 6, of: .subStruct(name: "XDPokemon")),  // +0x030..0x4C8
            .padding(length: 0x418),                                 // +0x4C8..0x8E0
            .uint8(name: "gender"),                                  // +0x8E0
            .padding(length: 3),                                     // +0x8E1..0x8E4 (alignment)
            .uint32(name: "money"),                                  // +0x8E4
            .uint32(name: "coupons"),                                // +0x8E8
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
            .padding(length: 4),                                      // +0x10..0x14
            .array(name: "pokemon", count: 30, of: .subStruct(name: "XDPokemon")),
        ]
    )

    /// XD save section 2 — PCBox. Eight `XDBox` entries packed
    /// back-to-back. Total 8 × 0x170C = 0xB860; section is typically
    /// 0xBC50 in the wild, with the 0x3F0 trailing region preserved
    /// from raw-slot.bin.
    static let savePCBoxStruct = StructMap(
        name: "XDPCBox",
        wordSize: 1,
        alignmentStyle: .none,
        properties: [
            .array(name: "boxes", count: 8, of: .subStruct(name: "XDBox")),
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
            .padding(length: 2),
            .uint32(name: "depositedEXP"),
            .subStruct(name: "pokemon", typeName: "XDPokemon"),
        ]
    )
}
