//
//  ChunkTypeMaps.swift
//  GeniusSonority
//
//  Which unpacked files carry typed data sections, and where the type map
//  that describes each one lives.
//

import Foundation
import GoDFoundation

public extension GeniusSonorityEngine.Data {

    /// One unpacked file whose data sections a type map describes.
    ///
    /// The FSYS unpack drops several RELs into a project that carry typed
    /// data — `tableres2.rel` alone holds an embedded font (the only 13×13
    /// glyph block in either game) and seven language message tables. Before
    /// this existed each such file meant another branch in project setup, so
    /// files that *were* known to hold typed chunks simply went untyped.
    ///
    /// The type map itself lives with the **game** engine, not here: a map
    /// names that game's structs and, for REL chunks, its pointer-index
    /// symbols, and both differ per game and per region. This route says
    /// *which file* and *which map*; the game engine says what's in it.
    struct ChunkTypeMapRoute: Codable, Equatable {
        /// Path of the file within the unpacked project.
        public var file: File

        /// Path of the type map within the game engine's folder.
        public var typeMap: File

        /// Folder under `/Source/Code` the disassembly output lands in.
        public var sourceFolderName: String

        /// Whether project setup enables the generated step.
        ///
        /// A file that only some regions ship has to default to disabled:
        /// the disassembly throws when the REL isn't there, which would
        /// abandon every operation chained behind it on that region.
        public var enabledByDefault: Bool

        public init(
            file: File,
            typeMap: File,
            sourceFolderName: String,
            enabledByDefault: Bool
        ) {
            self.file = file
            self.typeMap = typeMap
            self.sourceFolderName = sourceFolderName
            self.enabledByDefault = enabledByDefault
        }
    }

    /// Files beyond `common.rel` and the DOL whose chunks should be typed.
    ///
    /// Those two have dedicated operations because they need more than a type
    /// map (a symbol index, a symbol map, cross-module resolution). Everything
    /// else is a plain REL plus a map, which is what this list covers — adding
    /// another is a line of data rather than a new branch.
    ///
    /// Optional so engines serialized before this existed still decode.
    var chunkTypeMapRoutes: [ChunkTypeMapRoute] {
        get { storedChunkTypeMapRoutes ?? [] }
        set { storedChunkTypeMapRoutes = newValue }
    }
}

public extension GeniusSonorityEngine.Data {

    /// `tableres2.rel` comes out of `common_dvdeth.fsys`, which only the US
    /// and PAL discs ship — hence disabled by default, so a JP project's
    /// operation chain isn't broken by a file that isn't there.
    static let defaultXDChunkTypeMapRoutes: [ChunkTypeMapRoute] = [
        .init(
            file: "/Data/Relocatable Modules/tableres2.rel",
            typeMap: "Resources/tableres2_typemap.json",
            sourceFolderName: "tableres2",
            enabledByDefault: false
        )
    ]
}
