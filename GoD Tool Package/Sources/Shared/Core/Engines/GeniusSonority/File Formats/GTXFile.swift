//
//  GTXFile.swift
//
//  FileFormat wrapper over GXTextureDecoder. The decoder itself is
//  stateless; this wrapper owns the decoded image + header metadata so the
//  registry can move GTX chunks uniformly.
//
//  Artifacts (using project-wide naming pattern):
//    <name>.gtx.json  — metadata (dimensions, formats, `pngPath` reference)
//    <name>.gtx.png   — RGBA8888 decoded pixels
//

import Foundation
import GoDFoundation
import GTX

public struct GTXFile: FileFormat {
    public static let formatName = "gtx"

    /// Base name (no extension) used for output filenames. Defaults to
    /// `gtx`; set explicitly when dumping a known source file so the
    /// artifacts are named after it.
    public var name: String = "gtx"

    public var image: GoDImage
    public var metadata: GXTextureMetadata

    public init(image: GoDImage, metadata: GXTextureMetadata, name: String = "gtx") {
        self.image = image
        self.metadata = metadata
        self.name = name
    }

    public func texturePNGFilename() -> File { File("\(name).\(GTXFile.formatName).png") }

    public init(binary: GoDData) throws {
        let decoder = GXTextureDecoder()
        guard let meta = decoder.parseHeader(data: binary) else {
            throw GTXFile.invalidFileError
        }
        guard let image = decoder.decode(data: binary) else {
            throw GTXFile.invalidFileError
        }
        self.image = image
        self.metadata = meta
    }

    public init(binary: GoDData, name: String) throws {
        try self.init(binary: binary)
        self.name = name
    }

    public var binaryData: GoDData {
        get throws {
            let decoder = GXTextureDecoder()
            guard let data = decoder.encode(image: image, metadata: metadata) else {
                throw GTXFile.failedToEncodeError(target: "gtx")
            }
            return data
        }
    }

    /// Metadata DTO — wraps GXTextureMetadata with a `pngPath` reference so
    /// the JSON is self-describing about where to find its PNG sidecar.
    public struct DTO: Codable, Equatable {
        public let width: Int
        public let height: Int
        public let format: GXTextureFormat
        public let paletteFormat: GXPaletteFormat?
        /// Path of the PNG sidecar, relative to this JSON's parent folder.
        public let pngPath: String

        public init(metadata: GXTextureMetadata, pngPath: String) {
            self.width = metadata.width
            self.height = metadata.height
            self.format = metadata.format
            self.paletteFormat = metadata.paletteFormat
            self.pngPath = pngPath
        }

        public var metadata: GXTextureMetadata {
            GXTextureMetadata(width: width, height: height, format: format, paletteFormat: paletteFormat)
        }
    }

    public init(outputs: [File: GoDData]) throws {
        let suffix = ".\(GTXFile.formatName).json"
        guard let jsonKey = outputs.keys.first(where: { $0.path.hasSuffix(suffix) }) else {
            throw GTXFile.missingOutputError(key: "*\(suffix)")
        }
        let stem = String(jsonKey.path.dropLast(suffix.count))
        guard let jsonData = outputs[jsonKey] else {
            throw GTXFile.missingOutputError(key: jsonKey.path)
        }
        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: jsonData.data)
        } catch {
            throw GTXFile.invalidFileError
        }
        let pngKey = File(dto.pngPath)
        guard let pngData = outputs[pngKey] else {
            throw GTXFile.missingOutputError(key: dto.pngPath)
        }
        guard let image = GoDImage.fromPNG(pngData) else {
            throw GTXFile.invalidFileError
        }
        self.image = image
        self.metadata = dto.metadata
        self.name = stem.isEmpty ? "gtx" : stem
    }

    public var outputs: [File: GoDData] {
        get throws {
            guard let png = image.pngData() else {
                throw GTXFile.failedToEncodeError(target: "png")
            }
            let pngFile = texturePNGFilename()
            let dto = DTO(metadata: metadata, pngPath: pngFile.path)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(dto)
            return [
                pngFile: png,
                jsonFilename: GoDData(data: jsonData, byteOrder: .big)
            ]
        }
    }
}
