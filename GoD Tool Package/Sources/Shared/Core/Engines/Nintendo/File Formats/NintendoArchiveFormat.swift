//
//  NintendoArchiveFormat.swift
//
//  Which container a buffer holds, and which way round its integers read.
//
//  Both answers come from the same four bytes. Nintendo's archive tooling
//  writes a format's four-character code as a machine word, so porting a
//  format to a platform of the opposite endianness reverses the spelling of
//  its own magic: a DS NARC opens with `NARC`, and the big-endian Wii port
//  of the same format opens with `CRAN`. U8 is the mirror case — native to
//  the big-endian GameCube, so `U\xAA8-` forwards means big-endian.
//
//  Reading the magic backwards is therefore not a corruption check, it is
//  the byte-order discriminator, and every scalar in the file follows it.
//

import Foundation
import GoDFoundation

public enum NintendoArchiveFormat: String, Codable, CaseIterable {

    /// The GameCube/Wii resource archive: a node tree with a string table.
    case u8

    /// The Nitro archive: a file-allocation table, a name table and a data
    /// blob. Native to the DS; Battle Revolution carries a big-endian port.
    case narc

    /// The magic as written on the platform the format is native to.
    public var nativeMagic: [UInt8] {
        switch self {
        case .u8: return [0x55, 0xAA, 0x38, 0x2D]
        case .narc: return Array("NARC".utf8)
        }
    }

    /// The byte order implied by seeing `nativeMagic` the right way round.
    public var nativeByteOrder: ByteOrder {
        switch self {
        case .u8: return .big
        case .narc: return .little
        }
    }

    /// The magic as it appears when the format has been ported to a machine
    /// of the opposite endianness.
    public var reversedMagic: [UInt8] {
        nativeMagic.reversed()
    }

    /// Conventional file extension, used to name a rebuilt archive when the
    /// manifest doesn't carry one.
    public var fileExtension: String {
        rawValue == "u8" ? "arc" : rawValue
    }

    /// Human-readable name for logs and errors.
    public var displayName: String {
        switch self {
        case .u8: return "U8"
        case .narc: return "NARC"
        }
    }
}

/// A format together with the byte order its magic announced.
public struct NintendoArchiveSignature: Equatable, Codable {
    public let format: NintendoArchiveFormat
    public let byteOrder: ByteOrder

    public init(format: NintendoArchiveFormat, byteOrder: ByteOrder) {
        self.format = format
        self.byteOrder = byteOrder
    }

    /// The magic to write for this combination — reversed exactly when the
    /// byte order isn't the format's native one.
    public var magic: [UInt8] {
        byteOrder == format.nativeByteOrder ? format.nativeMagic : format.reversedMagic
    }

    public var description: String {
        "\(format.displayName) (\(byteOrder == .big ? "big" : "little")-endian)"
    }

    /// Identifies `data` from its first four bytes, or nil if they spell no
    /// known magic in either direction.
    ///
    /// Takes a `GoDReadable` because this only reads the first four bytes —
    /// sniffing a file shouldn't pull it into memory.
    public static func detect(_ data: GoDReadable) -> NintendoArchiveSignature? {
        guard data.length >= 4,
              let magic = data.read(atAddress: 0, length: 4)?.rawBytes else {
            return nil
        }
        return detect(magic: magic)
    }

    public static func detect(magic: [UInt8]) -> NintendoArchiveSignature? {
        for format in NintendoArchiveFormat.allCases {
            if magic == format.nativeMagic {
                return .init(format: format, byteOrder: format.nativeByteOrder)
            }
            if magic == format.reversedMagic {
                return .init(format: format, byteOrder: format.nativeByteOrder.swapped)
            }
        }
        return nil
    }
}

// MARK: - Errors

public enum NintendoArchiveError: Error, CustomStringConvertible {
    case unrecognizedMagic(found: [UInt8])
    case wrongFormat(expected: NintendoArchiveFormat, found: NintendoArchiveFormat)
    case truncated(format: String, needed: Int, available: Int)
    case malformed(format: String, reason: String)

    public var description: String {
        switch self {
        case let .unrecognizedMagic(found):
            let hex = found.map { String(format: "%02X", $0) }.joined(separator: " ")
            let text = String(decoding: found, as: UTF8.self)
            return "Nintendo archive: bytes \(hex) (\"\(text)\") spell no known magic in either direction"
        case let .wrongFormat(expected, found):
            return "Nintendo archive: expected a \(expected.displayName), found a \(found.displayName)"
        case let .truncated(format, needed, available):
            return "\(format): needs to read \(needed) bytes of a \(available)-byte buffer"
        case let .malformed(format, reason):
            return "\(format): \(reason)"
        }
    }
}

// MARK: - Byte-order-aware primitives

/// Bounds-checked, byte-order-aware reads over a raw buffer.
///
/// The archive parsers work in `[UInt8]` and assemble scalars by hand:
/// which end a word reads from is decided per archive by its magic, not by
/// the byte order the surrounding `GoDData` happens to be tagged with.
struct ArchiveReader {
    let bytes: [UInt8]
    let byteOrder: ByteOrder
    let format: String

    func u8(_ offset: Int) throws -> UInt8 {
        try checkBounds(offset, 1)
        return bytes[offset]
    }

    func u16(_ offset: Int) throws -> UInt16 {
        try checkBounds(offset, 2)
        let a = UInt16(bytes[offset]), b = UInt16(bytes[offset + 1])
        return byteOrder == .big ? (a << 8 | b) : (b << 8 | a)
    }

    func u32(_ offset: Int) throws -> UInt32 {
        try checkBounds(offset, 4)
        let b = (0 ..< 4).map { UInt32(bytes[offset + $0]) }
        return byteOrder == .big
            ? (b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3])
            : (b[3] << 24 | b[2] << 16 | b[1] << 8 | b[0])
    }

    /// A four-character code, always read in stored order — the whole point
    /// of a section magic here is the direction it is written in.
    func magic(_ offset: Int) throws -> [UInt8] {
        try checkBounds(offset, 4)
        return Array(bytes[offset ..< offset + 4])
    }

    func slice(_ offset: Int, _ length: Int) throws -> [UInt8] {
        try checkBounds(offset, length)
        return Array(bytes[offset ..< offset + length])
    }

    /// A NUL-terminated name. Shift-JIS is the encoding these tools wrote;
    /// it agrees with ASCII for the plain names that dominate real archives.
    func cString(_ offset: Int) throws -> String {
        try checkBounds(offset, 1)
        var end = offset
        while end < bytes.count, bytes[end] != 0 { end += 1 }
        guard end < bytes.count else {
            throw NintendoArchiveError.malformed(
                format: format, reason: "a name starting at \(offset) has no terminator"
            )
        }
        return decodeName(Array(bytes[offset ..< end]))
    }

    private func checkBounds(_ offset: Int, _ length: Int) throws {
        guard offset >= 0, length >= 0, offset + length <= bytes.count else {
            throw NintendoArchiveError.truncated(
                format: format, needed: offset + length, available: bytes.count
            )
        }
    }
}

/// Byte-order-aware appends.
struct ArchiveWriter {
    let byteOrder: ByteOrder
    private(set) var bytes: [UInt8] = []

    init(byteOrder: ByteOrder, reserving capacity: Int = 0) {
        self.byteOrder = byteOrder
        bytes.reserveCapacity(capacity)
    }

    mutating func append(u8 value: UInt8) {
        bytes.append(value)
    }

    mutating func append(u16 value: UInt16) {
        let pair: [UInt8] = [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
        bytes += byteOrder == .big ? pair : pair.reversed()
    }

    mutating func append(u32 value: UInt32) {
        let quad = (0 ..< 4).map { UInt8(truncatingIfNeeded: value >> (24 - 8 * $0)) }
        bytes += byteOrder == .big ? quad : quad.reversed()
    }

    /// Raw bytes, written in the order given — for magics, names and file
    /// payloads, none of which are scalars.
    mutating func append(raw value: [UInt8]) {
        bytes += value
    }

    mutating func pad(to boundary: Int, with byte: UInt8) {
        guard boundary > 1 else { return }
        while bytes.count % boundary != 0 { bytes.append(byte) }
    }

    mutating func pad(count: Int, with byte: UInt8) {
        guard count > 0 else { return }
        bytes += [UInt8](repeating: byte, count: count)
    }

    /// Overwrites a word already written — for sizes only known once the
    /// rest of a section exists.
    mutating func patch(u32 value: UInt32, at offset: Int) {
        let quad = (0 ..< 4).map { UInt8(truncatingIfNeeded: value >> (24 - 8 * $0)) }
        let ordered = byteOrder == .big ? quad : quad.reversed()
        for (index, byte) in ordered.enumerated() { bytes[offset + index] = byte }
    }
}

/// Names round-trip through Shift-JIS: it is what these tools wrote, and it
/// agrees with ASCII over the plain names that dominate real archives.
func decodeName(_ bytes: [UInt8]) -> String {
    let data = Foundation.Data(bytes)
    if let text = String(data: data, encoding: .shiftJIS) { return text }
    return String(decoding: bytes, as: UTF8.self)
}

func encodeName(_ name: String) -> [UInt8] {
    if let data = name.data(using: .shiftJIS) { return [UInt8](data) }
    return Array(name.utf8)
}
