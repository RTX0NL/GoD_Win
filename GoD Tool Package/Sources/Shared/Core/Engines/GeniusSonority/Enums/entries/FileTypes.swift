import Foundation
import Structs

extension GeniusSonorityEngine.Enums.Defaults {
    /// Raw values are even and sparse (0x02...0x34 with gaps at 0x16/0x1A),
    /// and real archives in both games carry values this list doesn't name.
    /// `allowUnknownCases` lets those round-trip as `FileTypes_<raw>` instead
    /// of resolving to nothing and being written back as type 0 — add a named
    /// case here once a value's meaning is identified.
    static let fileTypesColoXDEnum = Enum(
        name: "FileTypes",
        allowUnknownCases: true,
        values: [
            .init(name: "mdat", rawValue: 0x02),
            .init(name: "dat", rawValue: 0x04),
            .init(name: "col", rawValue: 0x06),
            .init(name: "samp", rawValue: 0x08),
            .init(name: "msg", rawValue: 0x0a),
            .init(name: "fnt", rawValue: 0x0c),
            .init(name: "scd", rawValue: 0x0e),
            .init(name: "dats", rawValue: 0x10),
            .init(name: "gtx", rawValue: 0x12),
            .init(name: "gpt1", rawValue: 0x14),
            .init(name: "cam", rawValue: 0x18),
            .init(name: "rel", rawValue: 0x1c),
            .init(name: "pkx", rawValue: 0x1e),
            .init(name: "wzx", rawValue: 0x20),
            .init(name: "gpt", rawValue: 0x22),
            .init(name: "gpd", rawValue: 0x24),
            .init(name: "drel", rawValue: 0x26),
            .init(name: "isd", rawValue: 0x28),
            .init(name: "ish", rawValue: 0x2a),
            .init(name: "thh", rawValue: 0x2c),
            .init(name: "thd", rawValue: 0x2e),
            .init(name: "gsw", rawValue: 0x30),
            .init(name: "atx", rawValue: 0x32),
            .init(name: "bin", rawValue: 0x34)
        ],
        propertyType: .uint8
    )
    
    /// `allowUnknownCases` matches the ColoXD enum: real PBR archives carry
    /// values this list doesn't name (e.g. 0x00, seen 23× in menus/mes_common),
    /// which round-trip as `FileTypes_<raw>` rather than collapsing to type 0.
    /// 0x14 = `efsq` (effect sequence) is confirmed by its `EFSQ` magic and the
    /// 39 entries across `wzx_waza`/`wzx_btlintro`.
    static let fileTypesPBREnum = Enum(
        name: "FileTypes",
        allowUnknownCases: true,
        values: [
            .init(name: "bin", rawValue: 0x02),
            .init(name: "sdr", rawValue: 0x04),
            .init(name: "odr", rawValue: 0x06),
            .init(name: "mdr", rawValue: 0x08),
            .init(name: "gpd", rawValue: 0x0a),
            .init(name: "gtx", rawValue: 0x0c),
            .init(name: "scd", rawValue: 0x12),
            .init(name: "efsq", rawValue: 0x14),
            .init(name: "fnt", rawValue: 0x16),
            .init(name: "msg", rawValue: 0x18),
            .init(name: "mnr", rawValue: 0x1a),
            .init(name: "thh", rawValue: 0x20),
            .init(name: "thd", rawValue: 0x22),
            .init(name: "gfl", rawValue: 0x24),
            .init(name: "dckp", rawValue: 0x28),
            .init(name: "dckt", rawValue: 0x2a),
            .init(name: "dcka", rawValue: 0x2e)
        ],
        propertyType: .uint8
    )
}
