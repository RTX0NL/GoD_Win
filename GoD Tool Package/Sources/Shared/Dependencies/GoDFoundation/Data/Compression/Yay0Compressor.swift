//
//  Yay0Compressor.swift
//
//  Yaz0's predecessor, found in earlier GameCube titles. The compression is
//  identical — same 0x1000 window, same 3...0x111 lengths, same distance
//  and length encoding — but where Yaz0 interleaves everything into one
//  stream, Yay0 splits it into three tables laid end to end after the
//  header.
//
//  Layout — everything big-endian:
//
//      0x00  4  "Yay0"
//      0x04  4  uncompressed size
//      0x08  4  offset of the link table
//      0x0C  4  offset of the chunk table
//      0x10  …  mask table
//
//  The mask table is a run of 32-bit words read most significant bit first,
//  one bit per operation. A set bit takes the next byte from the chunk
//  table verbatim. A clear bit takes a two-byte link, `nnnn dddd dddd
//  dddd`: distance `d + 1` back, length `n + 2`, or — when `n` is zero — a
//  length of `0x12` plus the next byte of the chunk table. So the chunk
//  table interleaves literals and long-match counts in operation order.
//

import Foundation

public struct Yay0Compressor: MagicPrefixedCompressor {

    public static let magic: [UInt8] = Array("Yay0".utf8)
    public static let headerLength = 0x10
    public static let formatName = "Yay0"

    /// See `Yaz0Compressor.reserveCeiling` — same defence against a corrupt
    /// size field.
    private static let reserveCeiling = 1 << 24

    /// The fields ahead of the three tables.
    public struct Header: Equatable {
        public let uncompressedSize: Int
        public let linkTableOffset: Int
        public let chunkTableOffset: Int

        public init(uncompressedSize: Int, linkTableOffset: Int, chunkTableOffset: Int) {
            self.uncompressedSize = uncompressedSize
            self.linkTableOffset = linkTableOffset
            self.chunkTableOffset = chunkTableOffset
        }
    }

    public let encoder: LZ77Encoder

    public init(encoder: LZ77Encoder = LZ77Encoder()) {
        self.encoder = encoder
    }

    // MARK: - Header

    /// Reads just the header, without decompressing.
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
            linkTableOffset: Int(bigEndianUInt32(raw, at: 8)),
            chunkTableOffset: Int(bigEndianUInt32(raw, at: 12))
        )
    }

    // MARK: - Compress

    public func compress(_ data: GoDData) -> GoDData {
        let source = data.rawBytes

        var maskTable: [UInt8] = []
        var linkTable: [UInt8] = []
        var chunkTable: [UInt8] = []

        var maskByte: UInt8 = 0
        var operationsInByte = 0

        for token in encoder.tokenize(source) {
            switch token {
            case .literal(let byte):
                maskByte |= UInt8(0x80) >> operationsInByte
                chunkTable.append(byte)

            case let .match(distance, length):
                let stored = distance - 1
                let count = length >= 0x12 ? 0 : length - 2
                linkTable.append(UInt8((count << 4) | (stored >> 8)))
                linkTable.append(UInt8(stored & 0xFF))
                if count == 0 {
                    chunkTable.append(UInt8(length - 0x12))
                }
            }

            operationsInByte += 1
            if operationsInByte == 8 {
                maskTable.append(maskByte)
                maskByte = 0
                operationsInByte = 0
            }
        }

        if operationsInByte > 0 {
            maskTable.append(maskByte)
        }
        // The decoder consumes the mask table a 32-bit word at a time, so
        // the last word has to be whole. Unused bits stay clear; decoding
        // stops on the declared size before it reaches them.
        while maskTable.count % 4 != 0 {
            maskTable.append(0)
        }

        let linkTableOffset = Self.headerLength + maskTable.count
        let chunkTableOffset = linkTableOffset + linkTable.count

        var output = Self.magic
        output.reserveCapacity(chunkTableOffset + chunkTable.count)
        appendBigEndianUInt32(UInt32(truncatingIfNeeded: source.count), to: &output)
        appendBigEndianUInt32(UInt32(truncatingIfNeeded: linkTableOffset), to: &output)
        appendBigEndianUInt32(UInt32(truncatingIfNeeded: chunkTableOffset), to: &output)
        output.append(contentsOf: maskTable)
        output.append(contentsOf: linkTable)
        output.append(contentsOf: chunkTable)

        return GoDData(byteStream: output, byteOrder: data.byteOrder)
    }

    // MARK: - Decompress

    public func decompress(_ data: GoDData) throws -> GoDData {
        let header = try Self.header(of: data)
        let stream = data.rawBytes
        let expected = header.uncompressedSize

        var output = [UInt8]()
        output.reserveCapacity(min(expected, Self.reserveCeiling))

        var maskPosition = Self.headerLength
        var linkPosition = header.linkTableOffset
        var chunkPosition = header.chunkTableOffset

        var mask: UInt32 = 0
        var operationsLeftInWord = 0

        func readByte(at position: inout Int) throws -> UInt8 {
            guard position >= 0, position < stream.count else {
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

        func readMaskWord() throws -> UInt32 {
            guard maskPosition >= 0, maskPosition + 4 <= stream.count else {
                throw LZ77StreamError.unexpectedEndOfInput(
                    format: Self.formatName,
                    position: maskPosition,
                    length: stream.count
                )
            }
            let word = bigEndianUInt32(stream, at: maskPosition)
            maskPosition += 4
            return word
        }

        while output.count < expected {
            if operationsLeftInWord == 0 {
                mask = try readMaskWord()
                operationsLeftInWord = 32
            }

            if mask & 0x8000_0000 != 0 {
                output.append(try readByte(at: &chunkPosition))
            } else {
                let first = try readByte(at: &linkPosition)
                let second = try readByte(at: &linkPosition)
                let distance = Int(UInt16(first & 0x0F) << 8 | UInt16(second)) + 1
                var length = Int(first >> 4)
                if length == 0 {
                    length = Int(try readByte(at: &chunkPosition)) + 0x12
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

            mask <<= 1
            operationsLeftInWord -= 1
        }

        if output.count > expected {
            output.removeLast(output.count - expected)
        }

        return GoDData(byteStream: output, byteOrder: data.byteOrder)
    }
}
