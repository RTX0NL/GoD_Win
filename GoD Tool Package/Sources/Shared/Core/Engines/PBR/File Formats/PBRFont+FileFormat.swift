//
//  PBRFont+FileFormat.swift
//  PBR
//
//  Registry conformance, so a PBR font routes through the same dump/build
//  machinery as every other format: `<name>.fnt.json` + `<name>.fnt.pgm`,
//  matching the pattern `GSFont` uses for Colosseum/XD.
//
//  The two formats share the `.fnt` extension and nothing else, so which one
//  a registry binds is decided by the engine that hands the registry out —
//  see `PBREngine.fileFormats()`. Neither ever guesses from bytes.
//

import Foundation
import GoDFoundation

extension PBRFont: FileFormat {

    public init(binaries: [FileData]) throws {
        guard let first = binaries.first else {
            throw PBRFont.Error.notAFontContainer()
        }
        let stem = first.file.fileName.withoutExtensions
        try self.init(data: first.data, name: stem.isEmpty ? Self.formatName : stem)
    }

    public var binaries: [FileData] {
        [FileData(file: File("\(name).\(Self.formatName)"), data: data)]
    }

    public init(outputs: [FileData]) throws {
        guard let manifest = outputs.first(where: { $0.file.path.hasSuffix(".json") }) else {
            throw PBRFont.Error.notAFontContainer()
        }
        let metadata = try JSONDecoder().decode(
            PBRFontAtlas.Metadata.self, from: Data(manifest.data.rawBytes)
        )
        // The manifest names its atlas, so a build only has to be handed the
        // bundle — it doesn't need the image identified separately.
        // The extension fallback accepts either spelling, which is what makes
        // projects dumped before the switch to PNG keep working.
        guard let atlas = outputs.first(where: {
            $0.file.fileName == metadata.atlasPath
        }) ?? outputs.first(where: {
            $0.file.path.hasSuffix(".png") || $0.file.path.hasSuffix(".pgm")
        }) else {
            throw PBRFontAtlas.Error.invalidAtlas()
        }
        let stem = manifest.file.fileName.withoutExtensions.withoutExtensions
        // `FileFormat` has nowhere to surface warnings, so the atlas checks
        // are dropped here and reported by the operation layer, which does
        // hold a logger. The font itself loads either way.
        self = try PBRFontAtlas.importAtlas(
            imageData: atlas.data,
            metadata: metadata,
            name: stem.isEmpty ? Self.formatName : stem
        ).font
    }

    public var outputs: [FileData] {
        get throws {
            let atlasName = "\(name).\(Self.formatName).png"
            let (image, metadata) = PBRFontAtlas.exportAtlas(font: self, atlasPath: atlasName)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = GoDData(data: try encoder.encode(metadata), byteOrder: .big)
            return [
                FileData(file: jsonFilename, data: json),
                FileData(file: File(atlasName), data: image),
            ]
        }
    }
}
