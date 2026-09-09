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
            /// `structName` across `engines`) and write it as a JSON object.
            /// Fails unless the binary is exactly the struct's size.
            ///
            /// `engines` lists engine folders in priority order, exactly as the
            /// DOL/REL type maps do: they are combined into one engine, so a
            /// struct in one folder can name an enum or sub-struct from another,
            /// and where two folders declare the same name the earliest listed
            /// wins (logged as a warning). Pass the game engine first.
            case decodeStruct(
                inputFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                structName: String,
                engines: [Folder]
            )

            /// Encode a struct JSON object (produced by `decodeStruct`) back
            /// into its binary using `structName` from `engines`.
            case encodeStruct(
                inputFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                structName: String,
                engines: [Folder]
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
                engines: [Folder]
            )

            /// Encode a struct-table JSON array (produced by
            /// `decodeStructTable`) back into its binary using `structName`
            /// from `engines`.
            case encodeStructTable(
                inputFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                structName: String,
                engines: [Folder]
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
