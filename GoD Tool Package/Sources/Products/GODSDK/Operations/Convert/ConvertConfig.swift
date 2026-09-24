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
            ///
            /// The struct is read from `fileOffset` (default 0) and occupies
            /// exactly its own size from there; bytes outside that window
            /// are ignored. The window has to sit wholly inside the input.
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
                engines: [Folder],
                fileOffset: Int? = nil
            )

            /// Encode a struct JSON object (produced by `decodeStruct`) back
            /// into its binary using `structName` from `engines`.
            ///
            /// With `insertOffset`, and an output file that already exists,
            /// the bytes are patched into that file at the offset instead of
            /// replacing it — the patch has to fit inside the file, and
            /// `overwrite` is ignored because patching is the point. Without
            /// an offset, or when the file doesn't exist yet, the file is
            /// written whole.
            case encodeStruct(
                inputFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                structName: String,
                engines: [Folder],
                insertOffset: Int? = nil
            )

            /// Map a binary file onto a table of `structName` structs, written
            /// as a JSON array of struct objects.
            ///
            /// Entries tile from `fileOffset` (default 0). With `count`, that
            /// many are read and anything after them is ignored; without it,
            /// tiling runs to the end of the file and a partial trailing
            /// entry is an error.
            case decodeStructTable(
                inputFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                structName: String,
                engines: [Folder],
                fileOffset: Int? = nil,
                count: Int? = nil
            )

            /// Encode a struct-table JSON array (produced by
            /// `decodeStructTable`) back into its binary using `structName`
            /// from `engines`. `insertOffset` behaves as for `encodeStruct`.
            case encodeStructTable(
                inputFile: File,
                outputFolder: Folder,
                overwrite: Bool,
                structName: String,
                engines: [Folder],
                insertOffset: Int? = nil
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
