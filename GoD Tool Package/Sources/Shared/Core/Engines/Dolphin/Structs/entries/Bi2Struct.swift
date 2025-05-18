//
//  Bi2Struct.swift
//  
//
//  Created by Stars Momodu on 03/06/2024.
//

import Foundation
import Structs

extension DolphinEngine.Structs.Defaults {
    static let bi2Struct = StructMap(
        name: "Bi2Data",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .uint32(name: "debug_monitor_size"),
            .uint32(name: "simulated_memory_size"),
            .uint32(name: "argument_offset"),
            .uint32(name: "debug_flag"),
            .uint32(name: "track_location"),
            .uint32(name: "track_size"),
            .uint32(name: "country_code"),
            .uint32(name: "unknown"),
            .padding(length: 0x1FE0)
        ],
        description: "this is loaded to the Address in 0x800000f4 when a disc is initialized by the IPL. https://hitmen.c02.at/files/yagcd/yagcd/chap13.html"
    )
}
