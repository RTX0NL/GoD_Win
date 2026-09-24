//
//  CardIntegrityRule.swift
//
//  A checksum a game keeps over part of its own save body.
//
//  Editing a banner or a comment changes bytes some games verify. The
//  generic rebuild has no way to know that and must not: which bytes are
//  covered, how they are summed and where the result is stored are facts
//  about one game's save format. So a game engine declares the rule and
//  the generic assembler applies whatever it is handed.
//
//  Pokémon XD and Colosseum are the case this exists for. Both store a
//  32-bit big-endian word sum of the first 0x3A40 bytes — the comments
//  and the whole image block — at 0x3A40, and the game checks it on
//  load. See `Documentation/File Formats/Shared/GCI - GameCube Memory Card Save.md`.
//

import Foundation
import GoDFoundation

public struct CardIntegrityRule: Codable, Equatable {

    /// How the covered range is reduced to a stored value.
    ///
    /// A closed set rather than a registry: these are facts about
    /// specific games' save formats, so a new one is a new case with a
    /// name, not an injectable strategy. One entry today.
    public enum Algorithm: String, Codable, CaseIterable {
        /// Sum of the range read as big-endian 32-bit words, truncated to
        /// 32 bits, stored big-endian.
        case sumUInt32BigEndian
    }

    public let algorithm: Algorithm
    /// Start of the covered range, relative to the save body.
    public let offset: Int
    public let length: Int
    /// Where the result is written, relative to the save body.
    public let storeAt: Int

    public init(algorithm: Algorithm, offset: Int, length: Int, storeAt: Int) {
        self.algorithm = algorithm
        self.offset = offset
        self.length = length
        self.storeAt = storeAt
    }

    /// Compute the value this rule would store for a body.
    public func value(in body: GoDData) throws -> UInt32 {
        guard offset >= 0, length > 0, offset + length <= body.length else {
            throw CardIntegrityRuleError.rangeOutOfBounds(
                offset: offset, length: length, bodyLength: body.length, .init()
            )
        }
        switch algorithm {
        case .sumUInt32BigEndian:
            guard length % 4 == 0 else {
                throw CardIntegrityRuleError.rangeNotWordAligned(length: length, .init())
            }
            body.setByteOrder(.big)
            var total: UInt32 = 0
            for address in stride(from: offset, to: offset + length, by: 4) {
                let word: UInt32 = body.readSafely(atAddress: address)
                total = total &+ word
            }
            return total
        }
    }

    /// Write the computed value into the body, in place.
    public func apply(to body: GoDData) throws {
        guard storeAt >= 0, storeAt + 4 <= body.length else {
            throw CardIntegrityRuleError.storeOutOfBounds(
                storeAt: storeAt, bodyLength: body.length, .init()
            )
        }
        let value = try self.value(in: body)
        body.setByteOrder(.big)
        let encoded = GoDData(byteStream: [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
        ], byteOrder: .big)
        body.write(encoded, atAddress: UInt(storeAt))
    }

    /// True when the body already holds the value this rule computes.
    public func holds(in body: GoDData) -> Bool {
        guard storeAt >= 0, storeAt + 4 <= body.length else { return false }
        guard let expected = try? value(in: body) else { return false }
        body.setByteOrder(.big)
        let stored: UInt32 = body.readSafely(atAddress: storeAt)
        return stored == expected
    }
}

public enum CardIntegrityRuleError: Error, CustomStringConvertible {
    case rangeOutOfBounds(offset: Int, length: Int, bodyLength: Int, ErrorTrace)
    case rangeNotWordAligned(length: Int, ErrorTrace)
    case storeOutOfBounds(storeAt: Int, bodyLength: Int, ErrorTrace)

    public var description: String {
        switch self {
        case let .rangeOutOfBounds(offset, length, bodyLength, trace):
            return """
                Save integrity rule covers \(offset)..<\(offset + length), \
                past the \(bodyLength)-byte body
                \(trace)
                """
        case let .rangeNotWordAligned(length, trace):
            return "Save integrity rule covers \(length) bytes, not a whole number of words\n\(trace)"
        case let .storeOutOfBounds(storeAt, bodyLength, trace):
            return "Save integrity rule stores at \(storeAt), past the \(bodyLength)-byte body\n\(trace)"
        }
    }
}
