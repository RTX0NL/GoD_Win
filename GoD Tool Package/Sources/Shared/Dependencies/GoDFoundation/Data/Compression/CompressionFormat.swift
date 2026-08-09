//
//  CompressionFormat.swift
//
//  Identifies which compressed-stream format a buffer holds, and hands back
//  the codec for it.
//
//  Deliberately a closed enum rather than a registry: unlike file formats,
//  which engines extend with game-specific handlers, the set of compressed
//  stream formats is fixed knowledge about Nintendo's tooling. There is no
//  mutable state to inject, so callers just ask.
//
//  Only self-describing formats belong here — ones whose own first bytes
//  say what they are. The LZSS inside FSYS entries does not qualify: its
//  magic lives in the archive's entry header, so `FSYSArchive` knows the
//  payload is compressed before it ever reaches `LZSSCompressor`.
//

import Foundation

public enum CompressionFormat: String, CaseIterable, Codable {

    /// Nintendo's LZ77 stream. GameCube onwards; the usual contents of a
    /// `.szs` and the usual wrapper around RARC and U8 archives.
    case yaz0

    /// Yaz0's predecessor, in earlier GameCube titles. Same compression,
    /// split across three tables.
    case yay0

    /// The bytes at offset 0 that identify this format.
    public var magic: [UInt8] {
        switch self {
        case .yaz0: return Yaz0Compressor.magic
        case .yay0: return Yay0Compressor.magic
        }
    }

    /// The format's conventional spelling, for logs and errors.
    public var name: String {
        switch self {
        case .yaz0: return Yaz0Compressor.formatName
        case .yay0: return Yay0Compressor.formatName
        }
    }

    /// The number of bytes of a stream `detect` needs to see.
    public static var magicLength: Int {
        allCases.map(\.magic.count).max() ?? 0
    }

    /// A codec for this format, configured with its defaults.
    public func makeCompressor() -> Compressor {
        switch self {
        case .yaz0: return Yaz0Compressor()
        case .yay0: return Yay0Compressor()
        }
    }

    /// The declared size of the data inside a stream of this format, read
    /// from its header without decompressing.
    public func uncompressedSize(of data: GoDReadable) throws -> Int {
        switch self {
        case .yaz0: return try Yaz0Compressor.header(of: data).uncompressedSize
        case .yay0: return try Yay0Compressor.header(of: data).uncompressedSize
        }
    }

    // MARK: - Detection

    /// The format `data` begins with, or nil if none of them.
    ///
    /// Takes a `GoDReadable` because this only ever looks at the first few
    /// bytes — sniffing a file shouldn't pull it into memory.
    public static func detect(_ data: GoDReadable) -> CompressionFormat? {
        guard data.length >= magicLength,
              let prefix = data.read(atAddress: 0, length: magicLength)?.rawBytes else {
            return nil
        }
        return allCases.first { format in
            prefix.count >= format.magic.count
                && Array(prefix[0 ..< format.magic.count]) == format.magic
        }
    }

    /// True if `data` starts with a recognized compressed stream.
    public static func isCompressed(_ data: GoDReadable) -> Bool {
        detect(data) != nil
    }

    /// Unwraps `data` if it is a recognized compressed stream, and returns
    /// it untouched if it isn't.
    ///
    /// This is the shape most callers want: archive payloads are compressed
    /// or not depending on the title, and either way the caller wants the
    /// contents.
    public static func decompressIfRecognized(_ data: GoDData) throws -> GoDData {
        guard let format = detect(data) else { return data }
        return try format.makeCompressor().decompress(data)
    }
}
