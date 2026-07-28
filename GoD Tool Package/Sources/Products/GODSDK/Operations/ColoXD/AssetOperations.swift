//
//  AssetOperations.swift
//  GODOps
//
//  `dumpAssets` and `buildAssets` — one pair of operations covering every
//  self-contained asset format, replacing the four-cases-per-format explosion
//  described in `AssetFormat`.
//
//  The shape both share: resolve the inputs (a file, or a folder walked for
//  the format's extension), run each through the format, and write what comes
//  back. Only the middle step varies, and it varies by a switch on the format.
//

import Foundation
import GoDFoundation
import GeniusSonority
import Colosseum
import ScriptDecompiler

extension ColoXD {

    // MARK: - Dump

    static func dumpAssets(
        format: AssetFormat,
        input: AssetPath,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let inputs = resolve(input, extension: format.binaryExtension, in: fileSystem)
        logger?.log(.info("Found \(inputs.count) \(format.displayName) file(s)"))

        var skipped = 0
        for scanned in inputs {
            // Mirror the input's directory layout into the output, so language
            // subfolders (French/, German/, …) survive the trip.
            var destination = outputFolder.folder(scanned.relativeFolder.path)
            let stem = scanned.file.fileName.withoutExtensions
            if format.dumpsIntoPerFileFolder {
                destination = destination.folder(stem)
            }

            do {
                let artifacts = try dumpArtifacts(
                    format: format,
                    file: scanned.file,
                    stem: stem,
                    fileSystem: fileSystem
                )
                try createFolder(destination, in: fileSystem, overwrite: overwrite)
                for artifact in artifacts {
                    try fileSystem.writeFile(
                        artifact.data,
                        at: resolveArtifact(artifact.file, in: destination),
                        overwrite: overwrite
                    )
                }
                logger?.log(.info("  \(stem): \(artifacts.count) artifact(s) → \(destination.path)"))
            } catch {
                // One unparseable asset shouldn't abandon the batch, but the
                // run has to say how many it gave up on — a silent skip used
                // to look identical to a clean pass.
                skipped += 1
                logger?.log(.warning("Failed to dump \(format.displayName) \(scanned.file.fileName): \(error)"))
            }
        }

        if skipped > 0 {
            logger?.log(.warning("Skipped \(skipped) of \(inputs.count) \(format.displayName) file(s)"))
        }
    }

    /// Produces the editable artifacts for one input file.
    private static func dumpArtifacts(
        format: AssetFormat,
        file: File,
        stem: String,
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        guard let data = fileSystem.readFile(at: file) else {
            throw FSTErrors.fileNotFound(file, .init())
        }

        switch format {
        case .font:
            let font = try GSFont(data: data)
            let atlasName = "\(stem)_atlas.pgm"
            let (imageData, metadata) = GSFontAtlas.exportAtlas(font: font, atlasPath: atlasName)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return [
                FileData(fileName: atlasName, data: imageData),
                FileData(fileName: "\(stem).json", data: try encoder.encode(metadata)),
            ]

        case .flashMenu:
            let parsed = try GSWParser.parse(data: data, name: stem)
            var gsw = parsed.file
            gsw.name = stem
            gsw.images = parsed.images
            return try gsw.outputs

        case let .message(variant):
            var parsed = try MSGFile(binary: data, variant: MSGFile.Variant(configValue: variant))
            parsed.name = stem
            return try parsed.outputs

        case .texture:
            return try ATXFile(binary: data, name: stem).outputs

        case .audio:
            // Paired format: the data half sits beside the header input.
            guard let parent = file.parentFolder else {
                throw FSTErrors.invalidPath(file.path, .init())
            }
            let isdFile = parent.file("\(stem).isd")
            guard let isdData = fileSystem.readFile(at: isdFile) else {
                throw FSTErrors.fileNotFound(isdFile, .init())
            }
            return try ISFFile(ish: data, isd: isdData, name: stem).outputs

        case let .coloScript(language, enginePath):
            let engine = try ColosseumEngine(from: enginePath, in: fileSystem)
            let script = try ColoScript(data: data)
            let source = ColoScriptSourceEmitter(
                builtInFunctions: engine.scriptBuiltInFunctionsByID,
                enums: engine.enumsByName
            ).decompileToText(script: script, fileName: file.fileName, syntax: language)
            return [FileData(
                fileName: "\(stem).\(language.fileExtension)",
                data: GoDData(byteStream: Array(source.utf8), byteOrder: .big)
            )]
        }
    }

    // MARK: - Build

    static func buildAssets(
        format: AssetFormat,
        input: AssetPath,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let inputs = resolveBuildInputs(input, format: format, in: fileSystem)
        logger?.log(.info("Building \(inputs.count) \(format.displayName) file(s)"))

        for scanned in inputs {
            let stem = buildStem(of: scanned.file, format: format)
            let binaries = try buildBinaries(
                format: format,
                manifest: scanned.file,
                stem: stem,
                fileSystem: fileSystem
            )
            let destination = outputFolder.folder(scanned.relativeFolder.path)
            for binary in binaries {
                let outFile = destination.file(binary.file.fileName)
                if overwrite || fileSystem.inspectFile(at: outFile) == nil {
                    try fileSystem.writeFile(binary.data, at: outFile, overwrite: overwrite)
                }
            }
            logger?.log(.info("  \(stem) → \(binaries.map(\.file.fileName).joined(separator: ", "))"))
        }
    }

    /// Rebuilds one asset's game-side binaries from its artifacts.
    private static func buildBinaries(
        format: AssetFormat,
        manifest: File,
        stem: String,
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        guard let manifestData = fileSystem.readFile(at: manifest),
              let baseFolder = manifest.parentFolder else {
            throw FSTErrors.fileNotFound(manifest, .init())
        }

        switch format {
        case .font:
            let metadata: GSFontAtlas.Metadata = try fileSystem.decodeJSON(from: manifest)
            let atlas = baseFolder.file(metadata.atlasPath)
            guard let imageData = fileSystem.readFile(at: atlas) else {
                throw FSTErrors.fileNotFound(atlas, .init())
            }
            let font = try GSFontAtlas.importAtlas(imageData: imageData, metadata: metadata)
            return [FileData(fileName: "\(stem).fnt", data: try font.data)]

        case .flashMenu:
            let outputs = try artifactBundle(
                manifest: manifest, manifestData: manifestData, baseFolder: baseFolder,
                companions: declaredPaths(inGSW: manifestData), fileSystem: fileSystem
            )
            return [FileData(fileName: "\(stem).gsw", data: try GSWFile(outputs: outputs).binaryData)]

        case .message:
            let file = try MSGFile(outputs: [
                FileData(file: File("\(stem).msg.json"), data: manifestData)
            ])
            return [FileData(fileName: "\(stem).msg", data: try file.binaryData)]

        case .texture:
            let outputs = try artifactBundle(
                manifest: manifest, manifestData: manifestData, baseFolder: baseFolder,
                companions: declaredPaths(inATX: manifestData, stem: stem, baseFolder: baseFolder, fileSystem: fileSystem),
                fileSystem: fileSystem
            )
            return [FileData(fileName: "\(stem).atx", data: try ATXFile(outputs: outputs).binaryData)]

        case .audio:
            struct WavPathOnly: Codable { let wavPath: String }
            let peek = try JSONDecoder().decode(WavPathOnly.self, from: manifestData.data)
            let outputs = try artifactBundle(
                manifest: manifest, manifestData: manifestData, baseFolder: baseFolder,
                companions: [peek.wavPath], fileSystem: fileSystem
            )
            let (ish, isd) = try ISFFile(outputs: outputs).ishISDBytes()
            return [
                FileData(fileName: "\(stem).ish", data: ish),
                FileData(fileName: "\(stem).isd", data: isd),
            ]

        case .coloScript(_, let enginePath):
            let engine = try ColosseumEngine(from: enginePath, in: fileSystem)
            var parser = ColoScriptTextParser(builtInFunctions: engine.scriptBuiltInFunctionsByID)
            let parsed = try parser.parse(manifestData.string(format: .utf8))
            return [FileData(fileName: "\(stem).scd", data: try ColoScriptCompiler().compile(parsed))]
        }
    }

    // MARK: - Input resolution

    private static func resolve(
        _ input: AssetPath,
        extension ext: String,
        in fileSystem: FileSystemTree
    ) -> [ScannedFile] {
        switch input {
        case let .file(file):
            return [ScannedFile(file: file, relativeFolder: Folder("."))]
        case let .folder(folder):
            return fileSystem.scan(folder, withExtension: ext)
        }
    }

    private static func resolveBuildInputs(
        _ input: AssetPath,
        format: AssetFormat,
        in fileSystem: FileSystemTree
    ) -> [ScannedFile] {
        switch input {
        case let .file(file):
            return [ScannedFile(file: file, relativeFolder: Folder("."))]
        case let .folder(folder):
            switch format {
            case .coloScript:
                // Scripts rebuild from source text in either dialect.
                return fileSystem.scan(folder) { $0.fileType == "swift" || $0.fileType == "py" }
            default:
                return fileSystem.scan(folder, withSuffix: format.manifestSuffix)
            }
        }
    }

    /// Stem of the asset a manifest belongs to, with the manifest's compound
    /// suffix removed (`absol.atx.json` -> `absol`).
    private static func buildStem(of manifest: File, format: AssetFormat) -> String {
        let name = manifest.fileName
        let suffix = format.manifestSuffix
        if !suffix.isEmpty, name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name.withoutExtensions
    }

    // MARK: - Artifact helpers

    /// The manifest plus the companion files it names, in the shape the
    /// `FileFormat.init(outputs:)` initialisers expect.
    private static func artifactBundle(
        manifest: File,
        manifestData: GoDData,
        baseFolder: Folder,
        companions: [String],
        fileSystem: FileSystemTree
    ) throws -> [FileData] {
        var outputs = [FileData(file: File(manifest.fileName), data: manifestData)]
        for relative in companions {
            let file = resolveRelativeFile(relative, in: baseFolder)
            guard let data = fileSystem.readFile(at: file) else {
                throw FSTErrors.fileNotFound(file, .init())
            }
            outputs.append(FileData(file: File(relative), data: data))
        }
        return outputs
    }

    private static func declaredPaths(inGSW manifestData: GoDData) -> [String] {
        struct TextureRefPath: Codable { let pngPath: String? }
        struct TagTextures: Codable { let textures: [TextureRefPath] }
        struct Peek: Codable { let tags: [TagTextures] }
        let peek = try? JSONDecoder().decode(Peek.self, from: manifestData.data)
        return (peek?.tags ?? []).flatMap(\.textures).compactMap(\.pngPath)
    }

    private static func declaredPaths(
        inATX manifestData: GoDData,
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

    private static func createFolder(
        _ folder: Folder,
        in fileSystem: FileSystemTree,
        overwrite: Bool
    ) throws {
        try fileSystem.createFolder(at: folder, overwrite: overwrite)
    }

    /// Places an artifact's (possibly nested) relative path under `folder`.
    private static func resolveArtifact(_ relative: File, in folder: Folder) -> File {
        var path = relative.path
        if path.hasPrefix("/") { path.removeFirst() }
        let parts = path.split(separator: "/").map(String.init)
        guard let last = parts.last else { return folder.file(path) }
        var current = folder
        for part in parts.dropLast() { current = current.folder(part) }
        return current.file(last)
    }
}
