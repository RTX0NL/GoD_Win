//
//  PBRFont3D+FileFormat.swift
//  PBR
//
//  Registry conformance, so a `.f3d` routes through the same dump/build
//  machinery as every other format: `<name>.f3d.json` + `<name>.f3d.svg`,
//  matching what `PBRFont` does with its manifest-plus-atlas pair.
//
//  `.f3d` is unambiguous — no other engine claims the extension — so unlike
//  `.fnt` this binding exists only because PBR is the engine that has the
//  format, not to resolve a clash.
//

import Foundation
import GoDFoundation

extension PBRFont3D: FileFormat {

    public init(binaries: [FileData]) throws {
        guard let first = binaries.first else {
            throw PBRFont3D.Error.notA3DFontContainer()
        }
        let stem = first.file.fileName.withoutExtensions
        try self.init(data: first.data, name: stem.isEmpty ? Self.formatName : stem)
    }

    public var binaries: [FileData] {
        get throws {
            [FileData(file: File("\(name).\(Self.formatName)"), data: try data)]
        }
    }

    public init(outputs: [FileData]) throws {
        guard let manifestFile = outputs.first(where: { $0.file.path.hasSuffix(".json") }) else {
            throw PBRFont3D.Error.notA3DFontContainer()
        }
        let manifest = try JSONDecoder().decode(
            PBRFont3DSVG.Manifest.self, from: Data(manifestFile.data.rawBytes)
        )
        // The manifest names its sheet, so a build only has to be handed the
        // bundle. The extension check is the fallback for a bundle whose files
        // were renamed after the dump.
        guard let sheet = outputs.first(where: { $0.file.fileName == manifest.svgPath })
                ?? outputs.first(where: { $0.file.path.hasSuffix(".svg") }) else {
            throw PBRFont3DSVG.Error.malformedSVG(reason: "the bundle has no \(manifest.svgPath)")
        }
        // `<name>.f3d.json` — two extensions to strip to recover the stem.
        let stem = manifestFile.file.fileName.withoutExtensions.withoutExtensions
        self = try PBRFont3DSVG.importFont(
            svg: sheet.data,
            manifest: manifest,
            name: stem.isEmpty ? manifest.name : stem
        )
    }

    public var outputs: [FileData] {
        get throws {
            let svgName = "\(name).\(Self.formatName).svg"
            let (svg, manifest) = PBRFont3DSVG.export(font: self, svgPath: svgName)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = GoDData(data: try encoder.encode(manifest), byteOrder: .big)
            return [
                FileData(file: jsonFilename, data: json),
                FileData(file: File(svgName), data: svg),
            ]
        }
    }
}
