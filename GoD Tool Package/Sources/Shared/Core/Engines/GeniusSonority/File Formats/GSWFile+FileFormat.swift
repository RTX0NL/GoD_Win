//
//  GSWFile+FileFormat.swift
//
//  Bridges GSWParser.parse / GSWParser.serialize onto the FileFormat
//  contract. Artifacts (using project-wide naming):
//    <name>.gsw.json — includes a `texturePaths` list keyed by ref id
//    <name>_texture_001.png, <name>_texture_002.png, ...
//
//  Texture PNG filenames are derived from the parent GSWFile's `name` and
//  the ref's id at serialize time, and echoed into the JSON so the build
//  op only needs the JSON path to resolve siblings.
//

import Foundation
import GoDFoundation
import GTX

extension GSWFile {
    /// Filename for the PNG that backs a given texture ref.
    public func pngFilename(for ref: GSWTextureRef) -> File {
        File("\(name)_texture_\(String(format: "%03d", ref.id)).png")
    }

    public init(binaries: [FileData]) throws {
        guard let first = binaries.first else {
            throw GSWFile.invalidFileError
        }
        let stem = first.file.fileName.withoutExtensions
        try self.init(binary: first.data, name: stem.isEmpty ? "gsw" : stem)
    }

    public init(binary: GoDData) throws {
        try self.init(binary: binary, name: "gsw")
    }

    public init(binary: GoDData, name: String) throws {
        let parsed = try GSWParser.parse(data: binary, name: name)
        self.init(header: parsed.file.header, tags: parsed.file.tags, images: parsed.images)
        self.name = name
    }

    public var binaries: [FileData] {
        get throws {
            [FileData(
                file: File("\(name).\(GSWFile.formatName)"),
                data: try GSWParser.serialize(file: self, images: images)
            )]
        }
    }

    public init(outputs: [FileData]) throws {
        let dict = outputs.byFile
        let suffix = ".\(GSWFile.formatName).json"
        guard let jsonKey = dict.keys.first(where: { $0.path.hasSuffix(suffix) }) else {
            throw GSWFile.missingOutputError(key: "*\(suffix)")
        }
        let stem = String(jsonKey.path.dropLast(suffix.count))
        guard let jsonData = dict[jsonKey] else {
            throw GSWFile.missingOutputError(key: jsonKey.path)
        }
        let metadata: GSWFile
        do {
            metadata = try JSONDecoder().decode(GSWFile.self, from: jsonData.data)
        } catch {
            throw GSWFile.invalidFileError
        }
        var rebuilt = metadata
        rebuilt.name = stem.isEmpty ? "gsw" : stem

        // Texture paths are declared inside the JSON (via each ref's
        // `pngPath`); fall back to the naming convention for older dumps.
        var images = [GoDImage]()
        for ref in rebuilt.allTextureRefs {
            let key: File
            if let storedPath = ref.pngPath, !storedPath.isEmpty {
                key = File(storedPath)
            } else {
                key = rebuilt.pngFilename(for: ref)
            }
            guard let pngData = dict[key] else {
                throw GSWFile.missingOutputError(key: key.path)
            }
            guard let image = GoDImage.fromPNG(pngData) else {
                throw GSWFile.invalidFileError
            }
            images.append(image)
        }

        rebuilt.images = images
        self = rebuilt
    }

    public var outputs: [FileData] {
        get throws {
            // Stamp each ref with its canonical PNG path so the JSON is a
            // self-describing manifest.
            var stamped = self
            stamped.stampTexturePaths()

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(stamped)

            var artifacts: [FileData] = [
                FileData(file: jsonFilename, data: GoDData(data: jsonData, byteOrder: .big))
            ]

            let refs = stamped.allTextureRefs
            guard refs.count == stamped.images.count else {
                throw FileFormatErrors.failedToEncode(
                    format: GSWFile.formatName,
                    target: "image count mismatch (got \(stamped.images.count), expected \(refs.count))"
                )
            }
            for (ref, image) in zip(refs, stamped.images) {
                guard let png = image.pngData() else {
                    throw GSWFile.failedToEncodeError(target: "PNG for texture \(ref.id)")
                }
                artifacts.append(FileData(file: pngFilename(for: ref), data: png))
            }
            return artifacts
        }
    }
}
