//
//  GSWFile+FileFormat.swift
//
//  Bridges GSWParser.parse / GSWParser.serialize onto the FileFormat
//  contract so the registry can route `.gsw` chunks. Outputs are a JSON
//  metadata file plus per-texture PNGs nested under `textures/`.
//

import Foundation
import GoDFoundation
import GTX

extension GSWFile {
    public init(binary: GoDData) throws {
        let parsed = try GSWParser.parse(data: binary)
        self.init(header: parsed.file.header, tags: parsed.file.tags, images: parsed.images)
    }

    public var binaryData: GoDData {
        get throws {
            try GSWParser.serialize(file: self, images: images)
        }
    }

    public init(outputs: [String: GoDData]) throws {
        guard let jsonData = outputs["json"] else {
            throw GSWFile.missingOutputError(key: "json")
        }
        let metadata: GSWFile
        do {
            metadata = try JSONDecoder().decode(GSWFile.self, from: jsonData.data)
        } catch {
            throw GSWFile.invalidFileError
        }

        // Match each texture ref to its PNG artifact. Refs store an absolute-
        // looking pngPath like "./textures/<name>_texture_001.png"; the
        // registry-style outputs map keys those by their relative-to-base
        // path, so we look for a key ending with the basename of the path.
        var images = [GoDImage]()
        for ref in metadata.allTextureRefs {
            let needle = (ref.pngPath as NSString).lastPathComponent
            let candidates = outputs.keys.filter { $0.hasSuffix(needle) }
            guard let key = candidates.first, let pngData = outputs[key] else {
                throw GSWFile.missingOutputError(key: needle)
            }
            guard let image = GoDImage.fromPNG(pngData) else {
                throw GSWFile.invalidFileError
            }
            images.append(image)
        }

        self.init(header: metadata.header, tags: metadata.tags, images: images)
    }

    public var outputs: [String: GoDData] {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(self)

            var artifacts: [String: GoDData] = [
                "json": GoDData(data: jsonData, byteOrder: .big)
            ]

            // Pair each ref with its image (parallel arrays). Emit keys
            // mirroring `pngPath` so the same layout that ColoXD already
            // writes round-trips through the registry. Keys drop any
            // leading "./" so they're cleanly relative.
            let refs = allTextureRefs
            guard refs.count == images.count else {
                throw FileFormatErrors.failedToEncode(
                    format: GSWFile.formatName,
                    target: "image count mismatch (got \(images.count), expected \(refs.count))"
                )
            }
            for (ref, image) in zip(refs, images) {
                guard let png = image.pngData() else {
                    throw GSWFile.failedToEncodeError(target: "PNG for texture \(ref.id)")
                }
                var key = ref.pngPath
                if key.hasPrefix("./") { key.removeFirst(2) }
                artifacts[key] = png
            }
            return artifacts
        }
    }
}
