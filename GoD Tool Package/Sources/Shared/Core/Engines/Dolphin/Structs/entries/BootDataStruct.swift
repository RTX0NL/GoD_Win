//
//  BootDataStruct.swift
//  
//
//  Created by Stars Momodu on 03/06/2024.
//

import Foundation
import Structs

extension DolphinEngine.Structs.Defaults {
    static let bootDataStruct = StructMap(
        name: "ISOBootData",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .string(name: "game_id", format: .utf8, length: 4),
            .string(name: "maker_code", format: .utf8, length: 2),
            .uint8(name: "disc_number"),
            .uint8(name: "disc_version"),
            .uint8(name: "audio_streaming"),
            .uint8(name: "stream_buffer_size"),
            .padding(length: 0x12),
            .uint32(name: "dvd_magic_word"),
            .string(name: "game_title", format: .utf8, length: 0x3e0),
            .uint32(name: "debug_monitor_offset"),
            .uint32(name: "debug_monitor_ram_address"),
            .padding(length: 0x18),
            .uint32(name: "main_executable_offset"),
            .uint32(name: "fst_offset"),
            .uint32(name: "fst_size"),
            .uint32(name: "max_fst_size", description: "the Max Fst.bin size is the same as the Fst.bin size in most cases. It can be different for 2 disc games though where the other disc has a larger fst.bin. Fst.bin size is always the size of the fst.bin on the same disc."),
            .uint32(name: "user_data_ram_address"),
            .uint32(name: "user_data_offset"),
            .uint32(name: "user_data_length"),
            .padding(length: 4)
        ]
    )
}
