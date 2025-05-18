//
//  ApploaderStruct.swift
//  
//
//  Created by Stars Momodu on 03/06/2024.
//

import Foundation
import Structs

extension DolphinEngine.Structs.Defaults {
    static let apploaderHeaderStruct = StructMap(
        name: "ApploaderHeader",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .string(name: "date", format: .utf8, length: 10),
            .padding(length: 6),
            .uint32(name: "entry_point"),
            .uint32(name: "size"),
            .uint32(name: "trailer_size"),
            .padding(length: 4)
        ]
    )
}
