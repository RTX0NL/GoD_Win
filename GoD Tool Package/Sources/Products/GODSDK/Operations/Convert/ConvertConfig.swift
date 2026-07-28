//
//  ConvertConfig.swift
//  GODOps
//

import GoDFoundation

extension Convert {
    struct Config: Codable {
        enum Operations: Codable {
            /// Decode a single binary file into a file format's editable
            /// artifacts (e.g. `.msg` -> JSON, `.gtx` -> JSON + PNG) written
            /// into `outputFolder`. The artifact filenames are derived from
            /// the input file's stem.
            case decodeFile(
                inputFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                format: FileFormatSelection
            )

            /// Rebuild a file format's binary from the artifact bundle under
            /// `inputFolder` (the folder a previous `decodeFile` produced),
            /// writing the reconstructed binary into `outputFolder`.
            case encodeFile(
                inputFolder: Folder,
                outputFolder: Folder,
                overwrite: Bool,
                format: FileFormatSelection
            )

            /// Map a binary file onto a single struct definition (resolved by
            /// `structName` from `engine`) and write it as a JSON object.
            /// Fails unless the binary is exactly the struct's size.
            case decodeStruct(
                inputFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                structName: String,
                engine: Folder
            )

            /// Encode a struct JSON object (produced by `decodeStruct`) back
            /// into its binary using `structName` from `engine`.
            case encodeStruct(
                inputFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                structName: String,
                engine: Folder
            )

            /// Map a binary file onto a table of `structName` structs. The
            /// entry count is the input size divided by the struct size;
            /// fails unless the struct tiles the input exactly. Written as a
            /// JSON array of struct objects.
            case decodeStructTable(
                inputFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                structName: String,
                engine: Folder
            )

            /// Encode a struct-table JSON array (produced by
            /// `decodeStructTable`) back into its binary using `structName`
            /// from `engine`.
            case encodeStructTable(
                inputFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                structName: String,
                engine: Folder
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
