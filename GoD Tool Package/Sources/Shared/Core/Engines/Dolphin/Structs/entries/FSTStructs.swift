//
//  FSTStructs.swift
//  
//
//  Created by Stars Momodu on 04/06/2024.
//

import Foundation
import Structs

extension DolphinEngine.Structs.Defaults {
    static let fstRootEntryStruct = StructMap(
        name: "FSTRootEntry",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .boolean(name: "is_directory"),
            .padding(length: 7),
            .uint32(name: "entry_count")
        ]
    )
    
    static let fstDirectoryEntryStruct = StructMap(
        name: "FSTDirectoryEntry",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .boolean(name: "is_directory"),
            .uint24(name: "name_offset"),
            .uint32(name: "parent_entry", description: "The index of the entry of the parent directory of this directory"),
            .uint32(name: "next_entry", description: "The index of the next entry that isn't under this directory")
        ]
    )
    
    static let fstFileEntryStruct = StructMap(
        name: "FSTFileEntry",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .boolean(name: "is_directory"),
            .uint24(name: "name_offset"),
            .uint32(name: "file_offset"),
            .uint32(name: "file_size")
        ]
    )
}
