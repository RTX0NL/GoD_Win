import Foundation
import Structs

extension GeniusSonorityEngine.Structs.Defaults {
    static let fsysFileMetadataStruct = StructMap(
        name: "FSYSFileMetaData",
        wordSize: 4,
        alignmentStyle: .cStyle,
        properties: [
            .uint16(name: "identifier"),
            .abstraction(name: "file_type", typeName: "FileTypes"),
            .uint32(name: "data_address"),
            .uint32(name: "uncompressed_size"),
            .uint32(name: "flags"),
            .padding(length: 4),
            .uint32(name: "file_size"),
            .padding(length: 4),
            .uint32(name: "full_filename_pointer"),
            .uint32(name: "file_type_index"), // file type / 2
            .uint32(name: "filename_pointer"),
            .padding(length: 8)
        ]
    )
}
