//
//  NintendoArchiveRegistry.swift
//
//  The manifest an unpacked archive leaves behind, and the only thing a
//  repack reads besides the extracted files themselves.
//
//  Same role as `FSYSRegistry`: the project filesystem holds the editable
//  contents, and this holds everything about the container that the
//  contents don't imply — which format and byte order it was, what order
//  its entries went in, and the handful of bytes that aren't derivable.
//  Entry order is load-bearing for both formats: a U8's node table is a
//  preorder walk, and a nameless NARC addresses its files purely by index
//  (in PBR's `waza_seq_rev.narc` that index is the move ID).
//

import Foundation
import GoDFoundation

public struct NintendoArchiveRegistry: Codable {

    public struct Entry: Codable {
        /// Path inside the archive. For a U8 this is the node's full path,
        /// which is what reconstructs the directory tree. For a NARC with a
        /// name table it is the file's name; for a nameless one it is nil
        /// and the entry is identified by its position in `entries`.
        public let archivePath: String?
        /// Where the extracted bytes live, relative to the folder holding
        /// this manifest. Nil for a directory, which has no payload.
        public let file: File?
        /// A U8 directory node. Carried explicitly because an empty one
        /// leaves no other trace.
        public let isDirectory: Bool

        public init(archivePath: String?, file: File?, isDirectory: Bool = false) {
            self.archivePath = archivePath
            self.file = file
            self.isDirectory = isDirectory
        }
    }

    public let format: NintendoArchiveFormat
    /// Which way round the archive's scalars read. Recorded rather than
    /// re-detected: the rebuilt archive has to be written the way the game
    /// expects to read it, and by then the original magic is gone.
    public let byteOrder: ByteOrder
    /// The archive's own filename, e.g. `homeBtn.arc`. Used to name the
    /// rebuilt file when the caller doesn't supply a path.
    public let archiveName: String
    public let entries: [Entry]
    /// A nameless NARC's name-table body, kept verbatim. Two bytes of it
    /// are ordered differently on the DS and in the big-endian port, and
    /// replaying them is how a repack avoids having to pick a side. Nil for
    /// U8 and for a NARC that carries real names.
    public let rawNameTable: [UInt8]?

    public init(
        format: NintendoArchiveFormat,
        byteOrder: ByteOrder,
        archiveName: String,
        entries: [Entry],
        rawNameTable: [UInt8]? = nil
    ) {
        self.format = format
        self.byteOrder = byteOrder
        self.archiveName = archiveName
        self.entries = entries
        self.rawNameTable = rawNameTable
    }

    /// The manifest's filename for an archive called `archiveName`, e.g.
    /// `homeBtn.arc` → `homeBtn.arc.json`.
    public static func manifestName(forArchive archiveName: String) -> String {
        archiveName + ".json"
    }

    /// The folder the extracted contents go in, alongside the manifest.
    public static func contentsFolderName(forArchive archiveName: String) -> String {
        archiveName.withoutExtension
    }
}
