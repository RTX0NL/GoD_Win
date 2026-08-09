//
//  Yaz0Compressor.swift
//
//  Nintendo's Yaz0: an LZ77 stream behind a 16-byte header, used from the
//  GameCube era onwards. It is what a `.szs` file usually holds, and what
//  RARC and U8 archives are most often wrapped in.
//
//  Layout — everything big-endian:
//
//      0x00  4  "Yaz0"
//      0x04  4  uncompressed size
//      0x08  4  alignment hint (0 on GameCube/Wii; used from Wii U on)
//      0x0C  4  reserved
//      0x10  …  groups
//
//  A group is a flag byte followed by the eight operations it describes,
//  most significant bit first. A set bit is a literal byte. A clear bit is
//  a back-reference: two bytes `nnnn dddd dddd dddd`, where the distance
//  is `d + 1` bytes back and the length is `n + 2` — unless `n` is zero, in
//  which case a third byte carries `length - 0x12`. So lengths run 3...0x11
//  in two bytes and 0x12...0x111 in three.
//

import Foundation

public struct Yaz0Compressor: MagicPrefixedCompressor {

    public static let magic: [UInt8] = Array("Yaz0".utf8)
    public static let headerLength = 0x10
    public static let formatName = "Yaz0"

    /// Cap on how much output space a header is trusted to reserve up
    /// front. A corrupt or hostile size field shouldn't turn into a
    /// gigabyte allocation before the first byte is even read.
    private static let reserveCeiling = 1 << 24

    /// The fields ahead of the compressed data.
    public struct Header: Equatable {
        public let uncompressedSize: Int
        public let alignment: UInt32
        public let reserved: UInt32

        public init(uncompressedSize: Int, alignment: UInt32, reserved: UInt32) {
            self.uncompressedSize = uncompressedSize
            self.alignment = alignment
            self.reserved = reserved
        }
    }

    /// Written to the header's alignment field. Zero for GameCube and Wii
    /// content; a caller re-packing a Wii U or Switch archive that declared
    /// one passes it back through.
    public let alignment: UInt32
    public let encoder: LZ77Encoder

    public init(alignment: UInt32 = 0, encoder: LZ77Encoder = LZ77Encoder()) {
        self.alignment = alignment
        self.encoder = encoder
    }

    // MARK: - Header

    /// Reads just the header, without decompressing. Takes a `GoDReadable`
    /// so a streamed source stays streamed — this only needs 16 bytes.
    public static func header(of data: GoDReadable) throws -> Header {
        guard data.length >= headerLength,
              let raw = data.read(atAddress: 0, length: headerLength)?.rawBytes,
              raw.count == headerLength else {
            throw LZ77StreamError.headerTruncated(format: formatName, length: data.length)
        }
        let found = Array(raw[0 ..< 4])
        guard found == magic else {
            throw LZ77StreamError.wrongMagic(format: formatName, found: found)
        }
        return Header(
            uncompressedSize: Int(bigEndianUInt32(raw, at: 4)),
            alignment: bigEndianUInt32(raw, at: 8),
            reserved: bigEndianUInt32(raw, at: 12)
        )
    }

    // MARK: - Compress

    public func compress(_ data: GoDData) -> GoDData {
        let source = data.rawBytes

        var output = Self.magic
        output.reserveCapacity(Self.headerLength + source.count / 2 + 0x10)
        appendBigEndianUInt32(UInt32(truncatingIfNeeded: source.count), to: &output)
        appendBigEndianUInt32(alignment, to: &output)
        appendBigEndianUInt32(0, to: &output)

        var groupFlags: UInt8 = 0
        var groupBody: [UInt8] = []
        var operationsInGroup = 0

        for token in encoder.tokenize(source) {
            switch token {
            case .literal(let byte):
                groupFlags |= UInt8(0x80) >> operationsInGroup
                groupBody.append(byte)

            case let .match(distance, length):
                // Stored one less than it is: distance 1 is encoded as 0,
                // which frees the whole 12-bit field for the 0x1000 window.
                let stored = distance - 1
                if length >= 0x12 {
                    groupBody.append(UInt8(stored >> 8))
                    groupBody.append(UInt8(stored & 0xFF))
                    groupBody.append(UInt8(length - 0x12))
                } else {
                    groupBody.append(UInt8(((length - 2) << 4) | (stored >> 8)))
                    groupBody.append(UInt8(stored & 0xFF))
                }
            }

            operationsInGroup += 1
            if operationsInGroup == 8 {
                output.append(groupFlags)
                output.append(contentsOf: groupBody)
                groupFlags = 0
                groupBody.removeAll(keepingCapacity: true)
                operationsInGroup = 0
            }
        }

        // A final short group keeps its unused flag bits clear; the decoder
        // stops on the declared size, not on the group boundary.
        if operationsInGroup > 0 {
            output.append(groupFlags)
            output.append(contentsOf: groupBody)
        }

        return GoDData(byteStream: output, byteOrder: data.byteOrder)
    }

    // MARK: - Decompress

    public func decompress(_ data: GoDData) throws -> GoDData {
        let header = try Self.header(of: data)
        let stream = data.rawBytes
        let expected = header.uncompressedSize

        var output = [UInt8]()
        output.reserveCapacity(min(expected, Self.reserveCeiling))

        var position = Self.headerLength
        var flags: UInt8 = 0
        var operationsLeftInGroup = 0

        func readByte() throws -> UInt8 {
            guard position < stream.count else {
                throw LZ77StreamError.unexpectedEndOfInput(
                    format: Self.formatName,
                    position: position,
                    length: stream.count
                )
            }
            let byte = stream[position]
            position += 1
            return byte
        }

        while output.count < expected {
            if operationsLeftInGroup == 0 {
                flags = try readByte()
                operationsLeftInGroup = 8
            }

            if flags & 0x80 != 0 {
                output.append(try readByte())
            } else {
                let first = try readByte()
                let second = try readByte()
                let distance = Int(UInt16(first & 0x0F) << 8 | UInt16(second)) + 1
                var length = Int(first >> 4)
                if length == 0 {
                    length = Int(try readByte()) + 0x12
                } else {
                    length += 2
                }
                try LZ77Decoder.appendBackReference(
                    distance: distance,
                    length: length,
                    to: &output,
                    format: Self.formatName
                )
            }

            flags <<= 1
            operationsLeftInGroup -= 1
        }

        // The last back-reference can run past the declared size; the size
        // is what's authoritative.
        if output.count > expected {
            output.removeLast(output.count - expected)
        }

        return GoDData(byteStream: output, byteOrder: data.byteOrder)
    }
}
