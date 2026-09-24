//
//  TextureOperations.swift
//  GODOps
//
//  ATX animated textures (`.atx`) <-> `<name>.atx.json` + PNG frames.
//
//  Each texture dumps into its own subfolder — the frames are numbered from
//  zero, so two textures dumped side by side would overwrite each other.
//

import Foundation
import GoDFoundation
import GeniusSonority

extension ColoXD {

    /// Suffix of the manifest a build reads back. Compound because the frames
    /// sit beside it and a bare `.json` would be ambiguous.
    private static let atxManifestSuffix = ".atx.json"

    /// An ATX's frames are numbered from zero, so two textures dumped side by
    /// side would overwrite each other. Both directions read this.
    private static let atxLayout: AssetLayout = .perAssetFolder

    static func dumpATXs(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        try dumpBatch(
            in: folder,
            matching: { $0.fileType == "atx" },
            label: "ATX texture",
            outputFolder: outputFolder,
            layout: atxLayout,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                try textureArtifacts(file: file, stem: stem, fileSystem: fileSystem)
            }
        )
    }

    static func dumpATX(
        atxFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        try dumpSingle(
            file: atxFile,
            outputFolder: outputFolder,
            layout: atxLayout,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                try textureArtifacts(file: file, stem: stem, fileSystem: fileSystem)
            }
        )
    }

    static func buildATXs(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        try buildBatch(
            in: folder,
            matching: { $0.fileName.hasSuffix(atxManifestSuffix) },
            stem: { stem(of: $0, droppingSuffix: atxManifestSuffix) },
            label: "ATX texture",
            outputFolder: outputFolder,
            layout: atxLayout,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            binaries: { manifest, stem in
                [try textureBinary(manifest: manifest, stem: stem, fileSystem: fileSystem)]
            }
        )
    }

    static func buildATX(
        metadataFile: File,
        outputFile: File,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let name = outputFile.fileName.withoutExtensions
        let binary = try textureBinary(manifest: metadataFile, stem: name, fileSystem: fileSystem)
        try fileSystem.writeFile(binary.data, at: outputFile, overwrite: overwrite)
        logger?.log(.info("  \(name) → \(outputFile.fileName)"))
    }

    // MARK: - Format work

    private static func textureArtifacts(
        file: File,
        stem: String,
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        guard let data = fileSystem.readFile(at: file)?.allData else {
            throw FSTErrors.fileNotFound(file, .init())
        }
        return try ATXFile(binary: data, name: stem).outputs
    }

    private static func textureBinary(
        manifest: File,
        stem: String,
        fileSystem: FileSystemTree
    ) throws -> FileData {
        let outputs = try artifactBundle(
            manifest: manifest,
            companions: { manifestData, baseFolder in
                declaredFramePaths(
                    in: manifestData, stem: stem, baseFolder: baseFolder, fileSystem: fileSystem
                )
            },
            fileSystem: fileSystem
        )
        return FileData(fileName: "\(stem).atx", data: try ATXFile(outputs: outputs).binaryData)
    }

    private static func declaredFramePaths(
        in manifestData: GoDData,
        stem: String,
        baseFolder: Folder,
        fileSystem: FileSystemTree
    ) -> [String] {
        struct Peek: Codable { let framePaths: [String]? }
        if let declared = (try? JSONDecoder().decode(Peek.self, from: manifestData.data))?.framePaths,
           !declared.isEmpty {
            return declared
        }
        // Manifests written before frame paths were stamped: fall back to the
        // naming convention.
        let prefix = "\(stem)_frame_"
        return (fileSystem.inspectFolder(at: baseFolder)?.files ?? [])
            .map(\.fileName)
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".png") }
            .sorted()
    }
}
