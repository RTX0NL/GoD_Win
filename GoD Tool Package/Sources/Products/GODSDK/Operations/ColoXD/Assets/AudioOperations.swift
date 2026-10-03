//
//  AudioOperations.swift
//  GODOps
//
//  ISF audio (`.ish` header + `.isd` data) <-> `<name>.isf.json` + WAV.
//
//  A paired format: both halves are one logical file, so a dump reads the
//  `.isd` sitting beside the `.ish` it was pointed at, and a build emits both.
//

import Foundation
import GoDFoundation
import GeniusSonority

extension ColoXD {

    private static let isfManifestSuffix = ".isf.json"

    static func dumpAudios(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        try dumpBatch(
            in: folder,
            matching: { $0.fileType == "ish" },
            label: "ISF audio",
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                guard let parent = file.parentFolder else {
                    throw FSTErrors.invalidPath(file.path, .init())
                }
                return try audioArtifacts(
                    ishFile: file,
                    isdFile: parent.file("\(stem).isd"),
                    stem: stem,
                    fileSystem: fileSystem
                )
            }
        )
    }

    /// The single-file form takes both halves explicitly rather than inferring
    /// the `.isd` — a caller pointing at one specific file may well have them
    /// in different folders.
    static func dumpAudio(
        ishFile: File,
        isdFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        try dumpSingle(
            file: ishFile,
            label: "ISF audio",
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                try audioArtifacts(ishFile: file, isdFile: isdFile, stem: stem, fileSystem: fileSystem)
            }
        )
    }

    static func buildAudios(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        try buildBatch(
            in: folder,
            matching: { $0.fileName.hasSuffix(isfManifestSuffix) },
            stem: { stem(of: $0, droppingSuffix: isfManifestSuffix) },
            label: "ISF audio",
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            binaries: { manifest, stem in
                let (ish, isd) = try audioBinaries(manifest: manifest, fileSystem: fileSystem)
                return [
                    FileData(fileName: "\(stem).ish", data: ish),
                    FileData(fileName: "\(stem).isd", data: isd),
                ]
            }
        )
    }

    static func buildAudio(
        metadataFile: File,
        ishOutputFile: File,
        isdOutputFile: File,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let (ish, isd) = try audioBinaries(manifest: metadataFile, fileSystem: fileSystem)
        try fileSystem.writeFile(ish, at: ishOutputFile, overwrite: overwrite)
        try fileSystem.writeFile(isd, at: isdOutputFile, overwrite: overwrite)
        logger?.log(.info("  \(metadataFile.fileName) → \(ishOutputFile.fileName), \(isdOutputFile.fileName)"))
    }

    // MARK: - Format work

    private static func audioArtifacts(
        ishFile: File,
        isdFile: File,
        stem: String,
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        guard let ishData = fileSystem.readFile(at: ishFile)?.allData else {
            throw FSTErrors.fileNotFound(ishFile, .init())
        }
        guard let isdData = fileSystem.readFile(at: isdFile)?.allData else {
            throw FSTErrors.fileNotFound(isdFile, .init())
        }
        return try ISFFile(ish: ishData, isd: isdData, name: stem).outputs
    }

    private static func audioBinaries(
        manifest: File,
        fileSystem: FileSystemTree
    ) throws -> (GoDData, GoDData) {
        let outputs = try artifactBundle(
            manifest: manifest,
            companions: { manifestData, _ in
                struct WavPathOnly: Codable { let wavPath: String }
                guard let peek = try? JSONDecoder().decode(WavPathOnly.self, from: manifestData.data) else {
                    return []
                }
                return [peek.wavPath]
            },
            fileSystem: fileSystem
        )
        return try ISFFile(outputs: outputs).ishISDBytes()
    }
}
