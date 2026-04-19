//
//  GTXFile.swift
//
//  FileFormat wrapper over GXTextureDecoder. The decoder itself is
//  stateless; this wrapper owns the decoded image + header metadata so the
//  registry can move GTX chunks uniformly.
//
//  Artifacts:
//    texture.json  — GTX metadata (dimensions, formats, `pngPath` reference)
//    texture.png   — RGBA8888 decoded pixels
//
//  The JSON's `pngPath` field points at the PNG by name so a single folder
//  can hold multiple textures with distinct JSON references without any
//  implicit naming convention.
//

import Foundation
import GoDFoundation
import GTX

public struct GTXFile: FileFormat {
    public static let formatName = "gtx"

    /// Default filenames. `init(outputs:)` follows the JSON's `pngPath` so
    /// callers are free to emit arbitrary names, but `outputs` always uses
    /// these defaults.
    public static let textureJSON = File("texture.json")
    public static let texturePNG = File("texture.png")

    public var image: GoDImage
    public var metadata: GXTextureMetadata

    public init(image: GoDImage, metadata: GXTextureMetadata) {
        self.image = image
        self.metadata = metadata
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
        self.metadata = meta
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
        guard let jsonData = outputs[GTXFile.textureJSON] else {
            throw GTXFile.missingOutputError(key: GTXFile.textureJSON.path)
        }
        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: jsonData.data)
        } catch {
            throw GTXFile.invalidFileError
        }
        // The JSON's pngPath points at the PNG relative to the JSON's folder.
        // Registry helpers place artifacts at `<folder>/<key.path>`, so the
        // same relative path shows up as a key in `outputs`.
        let pngKey = File(dto.pngPath)
        guard let pngData = outputs[pngKey] else {
            throw GTXFile.missingOutputError(key: dto.pngPath)
        }
        guard let image = GoDImage.fromPNG(pngData) else {
            throw GTXFile.invalidFileError
        }
        self.image = image
        self.metadata = dto.metadata
    }

    public var outputs: [File: GoDData] {
        get throws {
            guard let png = image.pngData() else {
                throw GTXFile.failedToEncodeError(target: "png")
            }
            let dto = DTO(metadata: metadata, pngPath: GTXFile.texturePNG.path)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(dto)
            return [
                GTXFile.texturePNG: png,
                GTXFile.textureJSON: GoDData(data: jsonData, byteOrder: .big)
            ]
        }
    }
}
