//
//  PBRStringsConfig.swift
//  GODOps
//
//  Config surface for Battle Revolution's string operations.
//
//  Nothing here is shared with the Colosseum/XD message operations, because
//  nothing about the two formats is shared beyond the extension — see
//  `PBRStringTable`. A config naming a PBR operation is the statement that
//  these are PBR strings; no byte sniffing decides it.
//
//  Both operations take the unpack root as well as the folders they read,
//  because the catalogue stores its file references relative to that root.
//  Keeping the root explicit means the document survives the project being
//  moved or renamed, and means a build knows where to put things back
//  without re-deriving the disc's layout.
//

import GoDFoundation

enum PBRStringsDump {

    /// Every string on the disc into one editable document.
    struct Config: Codable {
        /// Root the unpack wrote to; file references in the document are
        /// relative to it.
        let unpackedFolder: Folder
        /// Folder of `.msg` binaries, language subfolders included.
        let messagesFolder: Folder
        /// The `common.fsys` member holding the string directory.
        let directoryFile: File
        /// The document to write.
        let outputFile: File
        let overwrite: Bool

        init(
            unpackedFolder: Folder,
            messagesFolder: Folder,
            directoryFile: File,
            outputFile: File,
            overwrite: Bool = false
        ) {
            self.unpackedFolder = unpackedFolder
            self.messagesFolder = messagesFolder
            self.directoryFile = directoryFile
            self.outputFile = outputFile
            self.overwrite = overwrite
        }
    }
}

enum PBRStringsBuild {

    /// The document back to the binaries it names.
    struct Config: Codable {
        let stringsFile: File
        /// Root the document's file references resolve against.
        let unpackedFolder: Folder
        let overwrite: Bool

        init(stringsFile: File, unpackedFolder: Folder, overwrite: Bool = true) {
            self.stringsFile = stringsFile
            self.unpackedFolder = unpackedFolder
            self.overwrite = overwrite
        }
    }
}
