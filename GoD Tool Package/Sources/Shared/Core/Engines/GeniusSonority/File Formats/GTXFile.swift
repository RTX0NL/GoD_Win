//
//  GTXFile.swift
//
//  FileFormat wrapper over GXTextureDecoder. The decoder itself is
//  stateless; this wrapper owns the decoded image plus the format flags
//  needed to re-encode. Width and height come from `image` rather than
//  being stored separately so there's no chance of them drifting.
//
//  Artifacts (using project-wide naming pattern):
//    <name>.gtx.json  — metadata (format flags + `pngPath` reference)
//    <name>.gtx.png   — RGBA8888 decoded pixels
//

import Foundation
import GoDFoundation
import GTX

public struct GTXFile: FileFormat {
    public static let formatName = "gtx"

    /// Base name (no extension) used for output filenames.
    public var name: String = "gtx"

    public var image: GoDImage
    public var format: GXTextureFormat
    public var paletteFormat: GXPaletteFormat?

    /// Computed wrapper matching the shape GXTextureDecoder expects. Width
    /// and height are taken from `image` so they can't disagree.
    public var metadata: GXTextureMetadata {
        GXTextureMetadata(
            width: image.width,
            height: image.height,
            format: format,
            paletteFormat: paletteFormat
        )
    }

    public init(
        image: GoDImage,
        format: GXTextureFormat,
        paletteFormat: GXPaletteFormat? = nil,
        name: String = "gtx"
    ) {
        self.image = image
        self.format = format
        self.paletteFormat = paletteFormat
        self.name = name
    }

    public func texturePNGFilename() -> File { File("\(name).\(GTXFile.formatName).png") }

    public init(binaries: [FileData]) throws {
        guard let first = binaries.first else {
            throw GTXFile.invalidFileError
        }
        try self.init(binary: first.data)
        let stem = first.file.fileName.withoutExtensions
        if !stem.isEmpty { self.name = stem }
    }

    public init(binary: GoDData) throws {
        let decoder = GXTextureDecoder()
        guard let meta = decoder.parseHeader(data: binary) else {
            throw GTXFile.invalidFileError
        }
        guard let image = decoder.decode(data: binary) else {
            throw GTXFile.invalidFileError
        }
        self.image = image
        self.format = meta.format
        self.paletteFormat = meta.paletteFormat
    }

    public init(binary: GoDData, name: String) throws {
        try self.init(binary: binary)
        self.name = name
    }

    public static func measuredLength(of data: GoDData) -> Int? {
        GXTextureDecoder().measuredLength(data: data)
    }

    public var binaries: [FileData] {
        get throws {
            let decoder = GXTextureDecoder()
            guard let data = decoder.encode(image: image, metadata: metadata) else {
                throw GTXFile.failedToEncodeError(target: "gtx")
            }
            return [FileData(file: File("\(name).\(GTXFile.formatName)"), data: data)]
        }
    }

    /// JSON DTO. `pngPath` is the on-disc filename for the PNG sidecar;
    /// `format` and `paletteFormat` are the only fundamental fields
    /// (width/height come from the PNG itself).
    public struct DTO: Codable, Equatable {
        public let format: GXTextureFormat
        public let paletteFormat: GXPaletteFormat?
        /// Path of the PNG sidecar, relative to this JSON's parent folder.
        public let pngPath: String

        public init(format: GXTextureFormat, paletteFormat: GXPaletteFormat?, pngPath: String) {
            self.format = format
            self.paletteFormat = paletteFormat
            self.pngPath = pngPath
        }
    }

    public init(outputs: [FileData]) throws {
        let dict = outputs.byFile
        let suffix = ".\(GTXFile.formatName).json"
        guard let jsonKey = dict.keys.first(where: { $0.path.hasSuffix(suffix) }) else {
            throw GTXFile.missingOutputError(key: "*\(suffix)")
        }
        let stem = String(jsonKey.path.dropLast(suffix.count))
        guard let jsonData = dict[jsonKey] else {
            throw GTXFile.missingOutputError(key: jsonKey.path)
        }
        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: jsonData.data)
        } catch {
            throw GTXFile.invalidFileError
        }
        let pngKey = File(dto.pngPath)
        guard let pngData = dict[pngKey] else {
            throw GTXFile.missingOutputError(key: dto.pngPath)
        }
        guard let image = GoDImage.fromPNG(pngData) else {
            throw GTXFile.invalidFileError
        }
        self.image = image
        self.format = dto.format
        self.paletteFormat = dto.paletteFormat
        self.name = stem.isEmpty ? "gtx" : stem
    }

    public var outputs: [FileData] {
        get throws {
            guard let png = image.pngData() else {
                throw GTXFile.failedToEncodeError(target: "png")
            }
            let pngFile = texturePNGFilename()
            let dto = DTO(format: format, paletteFormat: paletteFormat, pngPath: pngFile.path)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(dto)
            return [
                FileData(file: jsonFilename, data: GoDData(data: jsonData, byteOrder: .big)),
                FileData(file: pngFile, data: png)
            ]
        }
    }
}
