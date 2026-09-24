//
//  FlashMenuOperations.swift
//  GODOps
//
//  GSW flash menus (`.gsw`) <-> JSON metadata + PNG textures.
//
//  Each menu dumps into its own subfolder: the textures are named after the
//  tags inside the menu, so two menus dumped side by side would collide.
//

import Foundation
import GoDFoundation
import GeniusSonority

extension ColoXD {

    /// A menu's textures are named after the tags inside it, so two menus
    /// dumped side by side would collide. Both directions read this.
    private static let flashMenuLayout: AssetLayout = .perAssetFolder

    static func dumpFlashMenus(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        try dumpBatch(
            in: folder,
            matching: { $0.fileType == "gsw" },
            label: "flash menu",
            outputFolder: outputFolder,
            layout: flashMenuLayout,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                try flashMenuArtifacts(file: file, stem: stem, fileSystem: fileSystem)
            }
        )
    }

    static func dumpFlashMenu(
        gswFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        try dumpSingle(
            file: gswFile,
            outputFolder: outputFolder,
            layout: flashMenuLayout,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                try flashMenuArtifacts(file: file, stem: stem, fileSystem: fileSystem)
            }
        )
    }

    static func buildFlashMenus(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        try buildBatch(
            in: folder,
            matching: { $0.fileType == "json" },
            stem: { $0.fileName.withoutExtensions },
            label: "flash menu",
            outputFolder: outputFolder,
            layout: flashMenuLayout,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            binaries: { manifest, stem in
                [try flashMenuBinary(manifest: manifest, stem: stem, fileSystem: fileSystem)]
            }
        )
    }

    static func buildFlashMenu(
        metadataFile: File,
        outputFile: File,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let stem = outputFile.fileName.withoutExtensions
        let binary = try flashMenuBinary(manifest: metadataFile, stem: stem, fileSystem: fileSystem)
        try fileSystem.writeFile(binary.data, at: outputFile, overwrite: overwrite)
        logger?.log(.info("  \(stem) → \(outputFile.fileName)"))
    }

    // MARK: - Format work

    private static func flashMenuArtifacts(
        file: File,
        stem: String,
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        guard let data = fileSystem.readFile(at: file)?.allData else {
            throw FSTErrors.fileNotFound(file, .init())
        }
        let parsed = try GSWParser.parse(data: data, name: stem)
        var gsw = parsed.file
        gsw.name = stem
        gsw.images = parsed.images
        return try gsw.outputs
    }

    private static func flashMenuBinary(
        manifest: File,
        stem: String,
        fileSystem: FileSystemTree
    ) throws -> FileData {
        let outputs = try artifactBundle(
            manifest: manifest,
            companions: { manifestData, _ in declaredPNGPaths(in: manifestData) },
            fileSystem: fileSystem
        )
        return FileData(fileName: "\(stem).gsw", data: try GSWFile(outputs: outputs).binaryData)
    }

    /// The PNGs a menu's metadata names, read without decoding the whole
    /// manifest — the format's own decoder does that once the files are in
    /// hand, and this only needs to know which to fetch.
    private static func declaredPNGPaths(in manifestData: GoDData) -> [String] {
        struct TextureRefPath: Codable { let pngPath: String? }
        struct TagTextures: Codable { let textures: [TextureRefPath] }
        struct Peek: Codable { let tags: [TagTextures] }
        let peek = try? JSONDecoder().decode(Peek.self, from: manifestData.data)
        return (peek?.tags ?? []).flatMap(\.textures).compactMap(\.pngPath)
    }
}
