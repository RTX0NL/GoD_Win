//
//  LZSSHeaderedCompressor.swift
//
//  Genius Sonority's LZSS behind the 16-byte header an FSYS entry carries.
//  `LZSSCompressor` speaks the bare stream, which has no magic and no sizes;
//  this is the self-describing form of it — what sits at the start of every
//  compressed FSYS entry, and what a standalone `.lzss` file holds.
//
//  Layout — everything big-endian:
//
//      0x00  4  "LZSS"
//      0x04  4  uncompressed size
//      0x08  4  compressed size, counting this header
//      0x0C  4  reserved (zero)
//      0x10  …  stream
//
//  The compressed size includes the header, so the stream is
//  `compressedSize - 0x10` bytes long. That is what `FSYSArchive` writes and
//  reads back. The archive keeps its own header code rather than routing
//  through this type — FSYS is a verified 1:1 target and its writer stays as
//  it is — and a cross-check test pins the two to the same bytes.
//

import Foundation

public struct LZSSHeaderedCompressor: MagicPrefixedCompressor {

    public static let magic: [UInt8] = Array("LZSS".utf8)
    public static let headerLength = 0x10
    public static let formatName = "LZSS"

    /// The fields ahead of the stream.
    public struct Header: Equatable {
        public let uncompressedSize: Int
        /// Counts the 16-byte header as well as the stream.
        public let compressedSize: Int
        public let reserved: UInt32

        public init(uncompressedSize: Int, compressedSize: Int, reserved: UInt32) {
            self.uncompressedSize = uncompressedSize
            self.compressedSize = compressedSize
            self.reserved = reserved
        }
    }

    /// The stream codec. Defaults to the Genius Sonority geometry (12-bit
    /// window, 4-bit length, threshold 2); a caller handling a stream cut
    /// with different parameters passes its own.
    public let codec: LZSSCompressor

    public init(codec: LZSSCompressor = LZSSCompressor()) {
        self.codec = codec
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
            compressedSize: Int(bigEndianUInt32(raw, at: 8)),
            reserved: bigEndianUInt32(raw, at: 12)
        )
    }

    // MARK: - Compress

    public func compress(_ data: GoDData) -> GoDData {
        let stream = codec.compress(data).rawBytes

        var output = Self.magic
        output.reserveCapacity(Self.headerLength + stream.count)
        appendBigEndianUInt32(UInt32(truncatingIfNeeded: data.length), to: &output)
        appendBigEndianUInt32(UInt32(truncatingIfNeeded: stream.count + Self.headerLength), to: &output)
        appendBigEndianUInt32(0, to: &output)
        output.append(contentsOf: stream)

        return GoDData(byteStream: output, byteOrder: data.byteOrder)
    }

    // MARK: - Decompress

    /// Bytes past the declared compressed size are ignored, so a stream can
    /// be handed over with whatever follows it in its container.
    public func decompress(_ data: GoDData) throws -> GoDData {
        let header = try Self.header(of: data)
        guard header.compressedSize >= Self.headerLength,
              header.compressedSize <= data.length else {
            throw LZ77StreamError.unexpectedEndOfInput(
                format: Self.formatName,
                position: header.compressedSize,
                length: data.length
            )
        }
        let body = Array(data.rawBytes[Self.headerLength ..< header.compressedSize])
        return try codec.decompress(
            GoDData(byteStream: body, byteOrder: data.byteOrder),
            expectedSize: header.uncompressedSize
        )
    }
}
