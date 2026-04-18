//
//  GSFont+DumpableFileFormat.swift
//
//  Bridges GSFont's existing binary init / atlas export+import onto the
//  DumpableFileFormat contract so the registry can route `.fnt` chunks
//  automatically.
//

import Foundation
import GoDFoundation

extension GSFont: DumpableFileFormat {
    public init(binary: GoDData) throws {
        try self.init(data: binary)
    }

    public var binaryData: GoDData {
        get throws { try data }
    }

    public init(outputs: [String: GoDData]) throws {
        guard let pgm = outputs["pgm"] else {
            throw GSFont.missingOutputError(key: "pgm")
        }
        guard let metaData = outputs["json"] else {
            throw GSFont.missingOutputError(key: "json")
        }
        let metadata: GSFontAtlas.Metadata
        do {
            metadata = try JSONDecoder().decode(GSFontAtlas.Metadata.self, from: metaData.data)
        } catch {
            throw GSFont.invalidFileError
        }
        self = try GSFontAtlas.importAtlas(imageData: pgm, metadata: metadata)
    }

    public var outputs: [String: GoDData] {
        get throws {
            // The `atlasPath` metadata field is used by the ColoXD file-based
            // build op to locate the PGM on disc. When routing via the
            // registry, artifacts travel in-memory keyed by "pgm" and "json"
            // — the stored path is informational.
            let result = GSFontAtlas.exportAtlas(font: self, atlasPath: "atlas.pgm")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(result.metadata)
            return [
                "pgm": result.imageData,
                "json": GoDData(data: jsonData, byteOrder: .big)
            ]
        }
    }
}
