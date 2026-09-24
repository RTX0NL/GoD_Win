//
//  CardSaveLayout.swift
//
//  How a GameCube save's body divides into named regions.
//
//  Exactly one region holds what the console defines — the banner, the
//  animated icon and the two comment strings — and can be opened by the
//  generic decoder. Every other region is the game's own and is carried
//  verbatim.
//
//  The list comes from one of two places. A game engine that knows the
//  save's shape declares it, which is the only way to find boundaries
//  nothing in the file describes: Pokémon XD's two save slots start at
//  0x6000 and 0x2E000, and no generic rule could say so. Absent a
//  declaration the list is derived, giving a metadata region that covers
//  the images and comments and one data region for the rest.
//
//  See `Documentation/File Formats/Shared/GCI - GameCube Memory Card Save.md`.
//

import Foundation
import GoDFoundation

public struct CardSaveLayout: Equatable {

    public struct Region: Codable, Equatable {
        public enum Kind: String, Codable, CaseIterable {
            /// Banner, icon frames and comments — the console's own.
            case cardMetadata
            /// The game's data, opaque here.
            case gameData
        }

        public let name: String
        public let offset: Int
        public let length: Int
        public let kind: Kind
        /// Byte the region is padded with where no artifact describes it.
        ///
        /// A metadata region is rebuilt from scratch: filled with this,
        /// then written over with the images, the comments and any
        /// checksum. Nothing of it is carried across from the original
        /// save, so this is what the untouched remainder has to be. Every
        /// real save measured has zero here, which is the default; a game
        /// that pads with something else declares it.
        public let fill: UInt8

        public init(name: String, offset: Int, length: Int, kind: Kind, fill: UInt8 = 0) {
            self.name = name
            self.offset = offset
            self.length = length
            self.kind = kind
            self.fill = fill
        }

        private enum CodingKeys: String, CodingKey {
            case name, offset, length, kind, fill
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            offset = try container.decode(Int.self, forKey: .offset)
            length = try container.decode(Int.self, forKey: .length)
            kind = try container.decode(Kind.self, forKey: .kind)
            fill = try container.decodeIfPresent(UInt8.self, forKey: .fill) ?? 0
        }

        public var end: Int { offset + length }

        /// The file a dump writes this region to when it isn't opened.
        public var binaryFilename: String { "\(name).bin" }
    }

    /// Name the derived layout gives its two regions.
    public static let derivedMetadataName = "metadata"
    public static let derivedDataName = "data"

    public let regions: [Region]
    public let bodyLength: Int

    /// Regions must tile the body exactly, in order, with at most one
    /// metadata region. A list that doesn't is a declaration error: a gap
    /// would drop bytes on rebuild and an overlap would write them twice.
    public init(regions: [Region], bodyLength: Int) throws {
        guard bodyLength >= 0 else {
            throw CardSaveLayoutError.negativeBodyLength(bodyLength, .init())
        }
        let sorted = regions.sorted { $0.offset < $1.offset }

        var names = Set<String>()
        for region in sorted {
            guard region.length > 0 else {
                throw CardSaveLayoutError.emptyRegion(name: region.name, .init())
            }
            guard names.insert(region.name).inserted else {
                throw CardSaveLayoutError.duplicateRegionName(region.name, .init())
            }
        }

        let metadataRegions = sorted.filter { $0.kind == .cardMetadata }
        guard metadataRegions.count <= 1 else {
            throw CardSaveLayoutError.multipleMetadataRegions(
                names: metadataRegions.map(\.name), .init()
            )
        }

        var cursor = 0
        for region in sorted {
            guard region.offset == cursor else {
                throw CardSaveLayoutError.regionsDoNotTile(
                    name: region.name, expectedOffset: cursor, actualOffset: region.offset, .init()
                )
            }
            cursor = region.end
        }
        guard cursor == bodyLength else {
            throw CardSaveLayoutError.regionsDoNotCoverBody(
                covered: cursor, bodyLength: bodyLength, .init()
            )
        }

        self.regions = sorted
        self.bodyLength = bodyLength
    }

    /// Derive a layout from the directory entry alone: a metadata region
    /// reaching to the end of the images or the comments, whichever is
    /// further, then one data region for everything after it.
    ///
    /// Both halves may be absent. A save with no images and no comments
    /// is all data; one that is nothing but metadata has no data region.
    public static func derived(header: GCIFile.Header, bodyLength: Int) throws -> CardSaveLayout {
        var metadataEnd = 0
        if let layout = CardImageBlock.layout(header: header) {
            metadataEnd = max(metadataEnd, layout.end)
        }
        if header.commentsAddr != CardComments.noCommentsAddress {
            metadataEnd = max(metadataEnd, Int(header.commentsAddr) + CardComments.byteCount)
        }
        metadataEnd = min(metadataEnd, bodyLength)

        var regions: [Region] = []
        if metadataEnd > 0 {
            regions.append(.init(
                name: derivedMetadataName, offset: 0, length: metadataEnd, kind: .cardMetadata
            ))
        }
        if metadataEnd < bodyLength {
            regions.append(.init(
                name: derivedDataName,
                offset: metadataEnd,
                length: bodyLength - metadataEnd,
                kind: .gameData
            ))
        }
        return try CardSaveLayout(regions: regions, bodyLength: bodyLength)
    }

    public var metadataRegion: Region? {
        regions.first { $0.kind == .cardMetadata }
    }

    public var gameDataRegions: [Region] {
        regions.filter { $0.kind == .gameData }
    }

    /// The bytes of one region.
    public func slice(_ region: Region, from body: GoDData) throws -> GoDData {
        guard region.end <= body.length else {
            throw CardSaveLayoutError.regionOutOfBounds(
                name: region.name, end: region.end, bodyLength: body.length, .init()
            )
        }
        guard let data = body.read(
            atAddress: UInt(region.offset), length: UInt(region.length)
        ) else {
            throw CardSaveLayoutError.regionReadFailed(name: region.name, .init())
        }
        return data
    }

    /// Concatenate region bytes back into a body, in offset order.
    public func assembled(regionBytes: [String: GoDData]) throws -> GoDData {
        let combined = GoDData(byteStream: [UInt8](), byteOrder: .big)
        for region in regions {
            guard let bytes = regionBytes[region.name] else {
                throw CardSaveLayoutError.missingRegionBytes(name: region.name, .init())
            }
            guard bytes.length == region.length else {
                throw CardSaveLayoutError.regionLengthMismatch(
                    name: region.name, expected: region.length, actual: bytes.length, .init()
                )
            }
            combined.append(bytes)
        }
        guard combined.length == bodyLength else {
            throw CardSaveLayoutError.regionsDoNotCoverBody(
                covered: combined.length, bodyLength: bodyLength, .init()
            )
        }
        return combined
    }
}

public enum CardSaveLayoutError: Error, CustomStringConvertible {
    case negativeBodyLength(Int, ErrorTrace)
    case emptyRegion(name: String, ErrorTrace)
    case duplicateRegionName(String, ErrorTrace)
    case multipleMetadataRegions(names: [String], ErrorTrace)
    case regionsDoNotTile(name: String, expectedOffset: Int, actualOffset: Int, ErrorTrace)
    case regionsDoNotCoverBody(covered: Int, bodyLength: Int, ErrorTrace)
    case regionOutOfBounds(name: String, end: Int, bodyLength: Int, ErrorTrace)
    case regionReadFailed(name: String, ErrorTrace)
    case missingRegionBytes(name: String, ErrorTrace)
    case regionLengthMismatch(name: String, expected: Int, actual: Int, ErrorTrace)

    public var description: String {
        switch self {
        case let .negativeBodyLength(length, trace):
            return "Save body length \(length) is negative\n\(trace)"
        case let .emptyRegion(name, trace):
            return "Save region '\(name)' has no length\n\(trace)"
        case let .duplicateRegionName(name, trace):
            return "Two save regions are both named '\(name)'\n\(trace)"
        case let .multipleMetadataRegions(names, trace):
            return """
                Save layout declares more than one card-metadata region \
                (\(names.joined(separator: ", "))); only one can hold the \
                banner, icon and comments.
                \(trace)
                """
        case let .regionsDoNotTile(name, expected, actual, trace):
            return """
                Save region '\(name)' starts at \(actual) but the previous \
                region ends at \(expected). Regions must tile the body with \
                no gaps or overlaps.
                \(trace)
                """
        case let .regionsDoNotCoverBody(covered, bodyLength, trace):
            return "Save regions cover \(covered) bytes of a \(bodyLength)-byte body\n\(trace)"
        case let .regionOutOfBounds(name, end, bodyLength, trace):
            return "Save region '\(name)' ends at \(end), past the \(bodyLength)-byte body\n\(trace)"
        case let .regionReadFailed(name, trace):
            return "Failed to read save region '\(name)'\n\(trace)"
        case let .missingRegionBytes(name, trace):
            return "No bytes supplied for save region '\(name)'\n\(trace)"
        case let .regionLengthMismatch(name, expected, actual, trace):
            return "Save region '\(name)' is \(actual) bytes, expected \(expected)\n\(trace)"
        }
    }
}
