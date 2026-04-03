import Foundation
import Structs

extension GeniusSonorityEngine.Enums.Defaults {
    static let fileTypesColoXDEnum = Enum(
        name: "FileTypes",
        allowUnknownCases: false,
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
    
    static let fileTypesPBREnum = Enum(
        name: "FileTypes",
        allowUnknownCases: false,
        values: [
            .init(name: "bin", rawValue: 0x02),
            .init(name: "sdr", rawValue: 0x04),
            .init(name: "odr", rawValue: 0x06),
            .init(name: "mdr", rawValue: 0x08),
            .init(name: "gpd", rawValue: 0x0a),
            .init(name: "gtx", rawValue: 0x0c),
            .init(name: "scd", rawValue: 0x12),
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
