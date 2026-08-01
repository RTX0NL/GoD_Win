//
//  FontOperations.swift
//  GODOps
//
//  GSFont (`.fnt`) <-> PGM atlas + JSON metadata.
//

import Foundation
import GoDFoundation
import GeniusSonority

extension ColoXD {

    static func dumpFonts(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        try dumpBatch(
            in: folder,
            matching: { $0.fileType == "fnt" },
            label: "font",
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                try fontArtifacts(file: file, stem: stem, fileSystem: fileSystem)
            }
        )
    }

    static func buildFonts(
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
            label: "font",
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            binaries: { manifest, stem in
                try fontBinary(manifest: manifest, stem: stem, fileSystem: fileSystem)
            }
        )
    }

    // MARK: - Format work

    private static func fontArtifacts(
        file: File,
        stem: String,
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        guard let data = fileSystem.readFile(at: file) else {
            throw FSTErrors.fileNotFound(file, .init())
        }
        let font = try GSFont(data: data)
        let atlasName = "\(stem)_atlas.pgm"
        let (imageData, metadata) = GSFontAtlas.exportAtlas(font: font, atlasPath: atlasName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return [
            FileData(fileName: atlasName, data: imageData),
            FileData(fileName: "\(stem).json", data: try encoder.encode(metadata)),
        ]
    }

    private static func fontBinary(
        manifest: File,
        stem: String,
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        guard let baseFolder = manifest.parentFolder else {
            throw FSTErrors.fileNotFound(manifest, .init())
        }
        let metadata: GSFontAtlas.Metadata = try fileSystem.decodeJSON(from: manifest)
        let atlas = baseFolder.file(metadata.atlasPath)
        guard let imageData = fileSystem.readFile(at: atlas) else {
            throw FSTErrors.fileNotFound(atlas, .init())
        }
        let font = try GSFontAtlas.importAtlas(imageData: imageData, metadata: metadata)
        return [FileData(fileName: "\(stem).fnt", data: try font.data)]
    }
}
