//
//  GSFont+FileFormat.swift
//
//  Bridges GSFont's existing binary init / atlas export+import onto the
//  FileFormat contract. Artifact filenames follow the project-wide
//  pattern: `<name>.fnt.json` + `<name>.fnt.png` (default `name = "fnt"`).
//

import Foundation
import GoDFoundation

extension GSFont: FileFormat {
    public func atlasImageFilename() -> File { File("\(name).\(GSFont.formatName).png") }

    public init(binaries: [FileData]) throws {
        guard let first = binaries.first else {
            throw GSFont.invalidFileError
        }
        try self.init(data: first.data)
        let stem = first.file.fileName.withoutExtensions
        if !stem.isEmpty { self.name = stem }
    }

    /// Thin bridge for call sites that have only the raw bytes. Equivalent
    /// to `init(data:)` — present so `GSFont(binary:)` reads idiomatically
    /// alongside other `FileFormat` conformers in tests and ops.
    public init(binary: GoDData) throws {
        try self.init(data: binary)
    }

    public var binaries: [FileData] {
        get throws {
            [FileData(file: File("\(name).\(GSFont.formatName)"), data: try data)]
        }
    }

    public init(outputs: [FileData]) throws {
        let dict = outputs.byFile
        let jsonSuffix = ".\(GSFont.formatName).json"
        let pngSuffix = ".\(GSFont.formatName).png"
        guard let jsonKey = dict.keys.first(where: { $0.path.hasSuffix(jsonSuffix) }) else {
            throw GSFont.missingOutputError(key: "*\(jsonSuffix)")
        }
        let stem = String(jsonKey.path.dropLast(jsonSuffix.count))
        let pngKey = File("\(stem)\(pngSuffix)")
        guard let metaData = dict[jsonKey] else {
            throw GSFont.missingOutputError(key: jsonKey.path)
        }
        guard let atlas = dict[pngKey] else {
            throw GSFont.missingOutputError(key: pngKey.path)
        }
        let metadata: GSFontAtlas.Metadata
        do {
            metadata = try JSONDecoder().decode(GSFontAtlas.Metadata.self, from: metaData.data)
        } catch {
            throw GSFont.invalidFileError
        }
        // `FileFormat` has nowhere to surface warnings, so the atlas checks
        // are dropped here and reported by the operation layer, which holds a
        // logger. The font loads either way.
        self = try GSFontAtlas.importAtlas(imageData: atlas, metadata: metadata).font
        self.name = stem.isEmpty ? "fnt" : stem
    }

    public var outputs: [FileData] {
        get throws {
            let atlas = atlasImageFilename()
            let result = try GSFontAtlas.exportAtlas(font: self, atlasPath: atlas.path)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(result.metadata)
            return [
                FileData(file: jsonFilename, data: GoDData(data: jsonData, byteOrder: .big)),
                FileData(file: atlas, data: result.imageData)
            ]
        }
    }
}
