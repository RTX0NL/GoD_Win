//
//  DolStruct.swift
//  
//
//  Created by Stars Momodu on 03/06/2024.
//

import Foundation
import Structs

extension DolphinEngine.Structs.Defaults {
    static let dolHeaderStruct = StructMap(
        name: "DolHeader",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .array(name: "text_sections_offsets", count: 7, of: .uint32),
            .array(name: "data_sections_offsets", count: 11, of: .uint32),
            .array(name: "text_sections_RAM_addresses", count: 7, of: .uint32),
            .array(name: "data_sections_RAM_addresses", count: 11, of: .uint32),
            .array(name: "text_sections_sizes", count: 7, of: .uint32),
            .array(name: "data_sections_sizes", count: 11, of: .uint32),
            .uint32(name: "BSS_RAM_address"),
            .uint32(name: "BSS_size"),
            .uint32(name: "entry_point"),
            .padding(length: 0x1c)
        ]
    )
}
