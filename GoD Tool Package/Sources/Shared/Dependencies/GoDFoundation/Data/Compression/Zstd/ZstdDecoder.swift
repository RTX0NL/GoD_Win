//
//  ZstdDecoder.swift
//
//  A Zstandard decompressor, written from the format specification.
//
//  It lives here beside LZSS and the Nintendo LZ77 codecs for the same
//  reason those do: a codec is a pure byte-level algorithm with no game
//  knowledge. It is pure Swift rather than a binding to libzstd because the
//  package's other algorithms — AES, SHA-1, the LZ77 family — are, and a C
//  dependency would be the first thing in the tree that doesn't build
//  wherever Swift does.
//
//  Decode only. Nothing in GoD-Tool writes Zstandard: RVZ is read to restore
//  an ISO and never produced. That asymmetry is why Zstd is absent from
//  `CompressionFormat`, whose cases promise a codec that runs both ways.
//
//  Reference: RFC 8878 (Zstandard Compression), facebook/zstd
//  `doc/zstd_compression_format.md`
//

import Foundation

public enum ZstdError: Error, CustomStringConvertible {
    case corrupted(String)
    case unsupported(String)
    case checksumMismatch(expected: UInt32, found: UInt32)

    public var description: String {
        switch self {
        case let .corrupted(detail):
            return "Malformed Zstandard stream: \(detail)"
        case let .unsupported(detail):
            return "Unsupported Zstandard stream: \(detail)"
        case let .checksumMismatch(expected, found):
            return String(
                format: "Zstandard frame checksum mismatch: the frame declares %08X, its content hashes to %08X",
                expected, found
            )
        }
    }
}

public enum Zstd {

    public static let magic: [UInt8] = [0x28, 0xB5, 0x2F, 0xFD]
    static let frameMagic: UInt32 = 0xFD2F_B528
    static let skippableMagicMask: UInt32 = 0xFFFF_FFF0
    static let skippableMagic: UInt32 = 0x184D_2A50

    /// Whether a buffer starts with a Zstandard frame magic.
    public static func isZstdFrame(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 4 && Array(bytes[0..<4]) == magic
    }

    /// Decompress every frame in `bytes`, concatenated.
    ///
    /// - Parameter expectedSize: reserves output capacity when the caller
    ///   already knows how big the result is, as an RVZ group always does.
    public static func decompress(_ bytes: [UInt8], expectedSize: Int? = nil) throws -> [UInt8] {
        var decoder = ZstdFrameDecoder()
        if let expectedSize { decoder.reserve(expectedSize) }
        var cursor = 0
        while cursor < bytes.count {
            cursor = try decoder.decodeFrame(bytes: bytes, at: cursor)
        }
        return decoder.output
    }

    /// Decompress a `GoDData` buffer. Byte order is carried across from the
    /// input, since a decompressed payload is read in whatever order its
    /// own format uses.
    public static func decompress(_ data: GoDData, expectedSize: Int? = nil) throws -> GoDData {
        let bytes = try decompress(data.rawBytes, expectedSize: expectedSize)
        return GoDData(byteStream: bytes, byteOrder: data.byteOrder)
    }
}

// MARK: - Frame decoding

/// Decodes one or more frames into a single output buffer.
///
/// State outlives a block on purpose: a literals section may reuse the
/// previous block's Huffman tree, a sequences section may reuse the previous
/// block's FSE tables, and the repeat-offset list runs the length of a
/// frame.
struct ZstdFrameDecoder {

    private(set) var output: [UInt8] = []

    private var huffmanTable: ZstdHuffmanTable?
    private var literalLengthTable: ZstdFSETable?
    private var offsetTable: ZstdFSETable?
    private var matchLengthTable: ZstdFSETable?
    private var repeatOffsets: (Int, Int, Int) = (1, 4, 8)

    mutating func reserve(_ count: Int) {
        output.reserveCapacity(count)
    }

    /// Decode the frame starting at `start` and return the offset just past
    /// it.
    mutating func decodeFrame(bytes: [UInt8], at start: Int) throws -> Int {
        guard start + 4 <= bytes.count else {
            throw ZstdError.corrupted("truncated frame magic")
        }
        let magic = readLE32(bytes, start)
        if magic & Zstd.skippableMagicMask == Zstd.skippableMagic {
            guard start + 8 <= bytes.count else {
                throw ZstdError.corrupted("truncated skippable frame header")
            }
            let size = Int(readLE32(bytes, start + 4))
            let end = start + 8 + size
            guard end <= bytes.count else {
                throw ZstdError.corrupted("skippable frame runs past the end of the buffer")
            }
            return end
        }
        guard magic == Zstd.frameMagic else {
            throw ZstdError.corrupted(String(format: "frame magic %08X is not Zstandard's", magic))
        }

        var cursor = start + 4
        let header = try readFrameHeader(bytes: bytes, at: &cursor)
        // A frame's repeat offsets start fresh; its entropy tables do too.
        repeatOffsets = (1, 4, 8)
        huffmanTable = nil
        literalLengthTable = nil
        offsetTable = nil
        matchLengthTable = nil

        let frameStartInOutput = output.count
        if let size = header.contentSize {
            output.reserveCapacity(frameStartInOutput + Int(size))
        }

        var isLast = false
        while !isLast {
            guard cursor + 3 <= bytes.count else {
                throw ZstdError.corrupted("truncated block header")
            }
            let blockHeader = UInt32(bytes[cursor])
                | UInt32(bytes[cursor + 1]) << 8
                | UInt32(bytes[cursor + 2]) << 16
            cursor += 3
            isLast = blockHeader & 1 == 1
            let blockType = (blockHeader >> 1) & 3
            let blockSize = Int(blockHeader >> 3)

            switch blockType {
            case 0:  // Raw
                guard cursor + blockSize <= bytes.count else {
                    throw ZstdError.corrupted("raw block runs past the end of the buffer")
                }
                output.append(contentsOf: bytes[cursor..<(cursor + blockSize)])
                cursor += blockSize
            case 1:  // RLE
                guard cursor < bytes.count else {
                    throw ZstdError.corrupted("truncated RLE block")
                }
                output.append(contentsOf: repeatElement(bytes[cursor], count: blockSize))
                cursor += 1
            case 2:  // Compressed
                guard cursor + blockSize <= bytes.count else {
                    throw ZstdError.corrupted("compressed block runs past the end of the buffer")
                }
                try decodeCompressedBlock(bytes: bytes, range: cursor..<(cursor + blockSize))
                cursor += blockSize
            default:
                throw ZstdError.corrupted("block type 3 is reserved")
            }
        }

        if let declared = header.contentSize {
            let produced = UInt64(output.count - frameStartInOutput)
            guard produced == declared else {
                throw ZstdError.corrupted("frame declares \(declared) bytes of content but produced \(produced)")
            }
        }

        if header.hasChecksum {
            guard cursor + 4 <= bytes.count else {
                throw ZstdError.corrupted("truncated frame checksum")
            }
            let declared = readLE32(bytes, cursor)
            cursor += 4
            let computed = UInt32(truncatingIfNeeded: XXHash64.hash(output[frameStartInOutput...]))
            guard declared == computed else {
                throw ZstdError.checksumMismatch(expected: declared, found: computed)
            }
        }
        return cursor
    }

    // MARK: - Frame header

    private struct FrameHeader {
        var contentSize: UInt64?
        var hasChecksum: Bool
    }

    private func readFrameHeader(bytes: [UInt8], at cursor: inout Int) throws -> FrameHeader {
        guard cursor < bytes.count else {
            throw ZstdError.corrupted("truncated frame header")
        }
        let descriptor = bytes[cursor]
        cursor += 1

        let contentSizeFlag = Int(descriptor >> 6)
        let singleSegment = (descriptor >> 5) & 1 == 1
        let hasChecksum = (descriptor >> 2) & 1 == 1
        let dictionaryIDFlag = Int(descriptor & 3)
        guard (descriptor >> 3) & 1 == 0 else {
            throw ZstdError.corrupted("frame header's reserved bit is set")
        }

        if !singleSegment {
            guard cursor < bytes.count else {
                throw ZstdError.corrupted("truncated window descriptor")
            }
            cursor += 1  // Window size only bounds memory; we hold the whole frame.
        }

        let dictionaryIDSize = [0, 1, 2, 4][dictionaryIDFlag]
        if dictionaryIDSize > 0 {
            guard cursor + dictionaryIDSize <= bytes.count else {
                throw ZstdError.corrupted("truncated dictionary ID")
            }
            var dictionaryID: UInt64 = 0
            for i in 0..<dictionaryIDSize {
                dictionaryID |= UInt64(bytes[cursor + i]) << (8 * i)
            }
            cursor += dictionaryIDSize
            guard dictionaryID == 0 else {
                throw ZstdError.unsupported("frame needs dictionary \(dictionaryID); dictionaries are not implemented")
            }
        }

        let contentSizeBytes = contentSizeFlag == 0 ? (singleSegment ? 1 : 0) : (1 << contentSizeFlag)
        var contentSize: UInt64?
        if contentSizeBytes > 0 {
            guard cursor + contentSizeBytes <= bytes.count else {
                throw ZstdError.corrupted("truncated frame content size")
            }
            var value: UInt64 = 0
            for i in 0..<contentSizeBytes {
                value |= UInt64(bytes[cursor + i]) << (8 * i)
            }
            cursor += contentSizeBytes
            // The 2-byte form is biased by 256; the format spends the low
            // values on the 1-byte form instead.
            contentSize = contentSizeBytes == 2 ? value + 256 : value
        }

        return FrameHeader(contentSize: contentSize, hasChecksum: hasChecksum)
    }

    // MARK: - Compressed block

    private mutating func decodeCompressedBlock(bytes: [UInt8], range: Range<Int>) throws {
        let (literals, literalBytes) = try decodeLiterals(bytes: bytes, range: range)
        let sequenceRange = (range.lowerBound + literalBytes)..<range.upperBound
        try decodeSequences(bytes: bytes, range: sequenceRange, literals: literals)
    }

    // MARK: - Literals

    private mutating func decodeLiterals(
        bytes: [UInt8],
        range: Range<Int>
    ) throws -> (literals: [UInt8], bytesRead: Int) {
        guard !range.isEmpty else {
            throw ZstdError.corrupted("missing literals section")
        }
        let base = range.lowerBound
        let first = bytes[base]
        let blockType = first & 3
        let sizeFormat = Int((first >> 2) & 3)

        switch blockType {
        case 0, 1:  // Raw, RLE
            let headerSize: Int
            let regeneratedSize: Int
            switch sizeFormat {
            case 1:
                headerSize = 2
                guard base + 2 <= range.upperBound else {
                    throw ZstdError.corrupted("truncated literals header")
                }
                regeneratedSize = Int(first >> 4) | Int(bytes[base + 1]) << 4
            case 3:
                headerSize = 3
                guard base + 3 <= range.upperBound else {
                    throw ZstdError.corrupted("truncated literals header")
                }
                regeneratedSize = Int(first >> 4) | Int(bytes[base + 1]) << 4 | Int(bytes[base + 2]) << 12
            default:  // 0 and 2 both mean the 1-byte form
                headerSize = 1
                regeneratedSize = Int(first >> 3)
            }

            if blockType == 0 {
                let start = base + headerSize
                guard start + regeneratedSize <= range.upperBound else {
                    throw ZstdError.corrupted("raw literals run past the end of the block")
                }
                return (Array(bytes[start..<(start + regeneratedSize)]), headerSize + regeneratedSize)
            } else {
                let start = base + headerSize
                guard start < range.upperBound else {
                    throw ZstdError.corrupted("truncated RLE literals")
                }
                return ([UInt8](repeating: bytes[start], count: regeneratedSize), headerSize + 1)
            }

        case 2, 3:  // Compressed, Treeless
            let streamCount = sizeFormat == 0 ? 1 : 4
            let headerSize: Int
            let fieldBits: Int
            switch sizeFormat {
            case 0, 1: headerSize = 3; fieldBits = 10
            case 2:    headerSize = 4; fieldBits = 14
            default:   headerSize = 5; fieldBits = 18
            }
            guard base + headerSize <= range.upperBound else {
                throw ZstdError.corrupted("truncated literals header")
            }
            var header: UInt64 = 0
            for i in 0..<headerSize {
                header |= UInt64(bytes[base + i]) << (8 * i)
            }
            let mask = (UInt64(1) << fieldBits) - 1
            let regeneratedSize = Int((header >> 4) & mask)
            let compressedSize = Int((header >> (4 + UInt64(fieldBits))) & mask)

            var cursor = base + headerSize
            let sectionEnd = cursor + compressedSize
            guard sectionEnd <= range.upperBound else {
                throw ZstdError.corrupted("literals section runs past the end of the block")
            }

            if blockType == 2 {
                let (table, treeBytes) = try ZstdHuffmanTable.read(
                    bytes: bytes,
                    range: cursor..<sectionEnd
                )
                huffmanTable = table
                cursor += treeBytes
            }
            guard let table = huffmanTable else {
                throw ZstdError.corrupted("treeless literals with no Huffman tree from a previous block")
            }

            var literals = [UInt8]()
            literals.reserveCapacity(regeneratedSize)

            if streamCount == 1 {
                try table.decode(
                    count: regeneratedSize,
                    bytes: bytes,
                    range: cursor..<sectionEnd,
                    into: &literals
                )
            } else {
                guard cursor + 6 <= sectionEnd else {
                    throw ZstdError.corrupted("truncated four-stream jump table")
                }
                var sizes = [Int]()
                for i in 0..<3 {
                    sizes.append(Int(bytes[cursor + i * 2]) | Int(bytes[cursor + i * 2 + 1]) << 8)
                }
                cursor += 6
                let totalKnown = sizes.reduce(0, +)
                let last = sectionEnd - cursor - totalKnown
                guard last >= 0 else {
                    throw ZstdError.corrupted("four-stream sizes exceed the literals section")
                }
                sizes.append(last)

                // Every stream but the last decodes the same count; the
                // last takes the remainder, so it can be up to 3 shorter.
                let perStream = (regeneratedSize + 3) / 4
                guard perStream * 3 <= regeneratedSize else {
                    throw ZstdError.corrupted("four-stream literals are too small to split")
                }
                var streamStart = cursor
                for (index, size) in sizes.enumerated() {
                    let count = index == 3 ? regeneratedSize - perStream * 3 : perStream
                    guard size > 0 || count == 0 else {
                        throw ZstdError.corrupted("empty literals stream \(index + 1) with \(count) symbols to decode")
                    }
                    if count > 0 {
                        try table.decode(
                            count: count,
                            bytes: bytes,
                            range: streamStart..<(streamStart + size),
                            into: &literals
                        )
                    }
                    streamStart += size
                }
            }
            guard literals.count == regeneratedSize else {
                throw ZstdError.corrupted("literals section produced \(literals.count) of \(regeneratedSize) bytes")
            }
            return (literals, headerSize + compressedSize)

        default:
            throw ZstdError.corrupted("unreachable literals block type")
        }
    }

    // MARK: - Sequences

    private mutating func decodeSequences(
        bytes: [UInt8],
        range: Range<Int>,
        literals: [UInt8]
    ) throws {
        guard !range.isEmpty else {
            // A block may be literals only, with the sequence count byte
            // omitted entirely when the literals fill the block.
            output.append(contentsOf: literals)
            return
        }
        var cursor = range.lowerBound
        let first = Int(bytes[cursor])
        cursor += 1
        var sequenceCount: Int
        if first < 128 {
            sequenceCount = first
        } else if first < 255 {
            guard cursor < range.upperBound else {
                throw ZstdError.corrupted("truncated sequence count")
            }
            sequenceCount = ((first - 128) << 8) + Int(bytes[cursor])
            cursor += 1
        } else {
            guard cursor + 2 <= range.upperBound else {
                throw ZstdError.corrupted("truncated sequence count")
            }
            sequenceCount = Int(bytes[cursor]) | Int(bytes[cursor + 1]) << 8
            sequenceCount += 0x7F00
            cursor += 2
        }

        if sequenceCount == 0 {
            output.append(contentsOf: literals)
            return
        }

        guard cursor < range.upperBound else {
            throw ZstdError.corrupted("missing symbol compression modes")
        }
        let modes = bytes[cursor]
        cursor += 1
        guard modes & 3 == 0 else {
            throw ZstdError.corrupted("symbol compression modes byte has its reserved bits set")
        }

        literalLengthTable = try readSequenceTable(
            mode: (modes >> 6) & 3,
            previous: literalLengthTable,
            predefined: ZstdSequenceTables.literalLength,
            maxSymbol: 35,
            maxTableLog: 9,
            bytes: bytes,
            cursor: &cursor,
            end: range.upperBound,
            name: "literal length"
        )
        offsetTable = try readSequenceTable(
            mode: (modes >> 4) & 3,
            previous: offsetTable,
            predefined: ZstdSequenceTables.offset,
            maxSymbol: 31,
            maxTableLog: 8,
            bytes: bytes,
            cursor: &cursor,
            end: range.upperBound,
            name: "offset"
        )
        matchLengthTable = try readSequenceTable(
            mode: (modes >> 2) & 3,
            previous: matchLengthTable,
            predefined: ZstdSequenceTables.matchLength,
            maxSymbol: 52,
            maxTableLog: 9,
            bytes: bytes,
            cursor: &cursor,
            end: range.upperBound,
            name: "match length"
        )

        guard let llTable = literalLengthTable,
              let ofTable = offsetTable,
              let mlTable = matchLengthTable else {
            throw ZstdError.corrupted("a sequence table is missing")
        }

        var reader = try ZstdBitReader(bytes: bytes, range: cursor..<range.upperBound)
        // Initial states are read literal-length first, then offset, then
        // match length — a different order from the per-sequence updates.
        var llState = ZstdFSEState(table: llTable, reader: &reader)
        var ofState = ZstdFSEState(table: ofTable, reader: &reader)
        var mlState = ZstdFSEState(table: mlTable, reader: &reader)

        var literalCursor = 0
        output.reserveCapacity(output.count + literals.count)

        for index in 0..<sequenceCount {
            let llCode = Int(llState.symbol)
            let mlCode = Int(mlState.symbol)
            let ofCode = Int(ofState.symbol)
            guard llCode < ZstdSequenceTables.literalLengthBaseline.count,
                  mlCode < ZstdSequenceTables.matchLengthBaseline.count,
                  ofCode <= 31 else {
                throw ZstdError.corrupted("sequence \(index) decodes an out-of-range symbol")
            }

            // Extra bits are taken offset-first, then match length, then
            // literal length.
            //
            // The window holds 64 bits, and one sequence can want far more
            // than that: up to 31 offset bits, 16 match-length bits and 16
            // literal-length bits, then 26 more to step the three states.
            // So it is reloaded three times — before the extra bits, between
            // match length and literal length, and after the state updates —
            // which caps each run at 54 bits. Reading straight through
            // instead works for the common sequence, where the lengths are
            // short, and silently returns stale bits for the rare long one:
            // 2.6 GB of real data is where that first showed up.
            reader.reload()
            let offsetValue = (1 << ofCode) + Int(reader.readBits(ofCode))
            let matchLength = ZstdSequenceTables.matchLengthBaseline[mlCode]
                + Int(reader.readBits(ZstdSequenceTables.matchLengthExtraBits[mlCode]))
            reader.reload()
            let literalLength = ZstdSequenceTables.literalLengthBaseline[llCode]
                + Int(reader.readBits(ZstdSequenceTables.literalLengthExtraBits[llCode]))

            let offset = try resolveOffset(offsetValue, literalLength: literalLength)

            guard literalCursor + literalLength <= literals.count else {
                throw ZstdError.corrupted("sequence \(index) needs more literals than the block holds")
            }
            output.append(contentsOf: literals[literalCursor..<(literalCursor + literalLength)])
            literalCursor += literalLength

            guard offset <= output.count else {
                throw ZstdError.corrupted("sequence \(index) matches \(offset) bytes back, before the start of the output")
            }
            var source = output.count - offset
            for _ in 0..<matchLength {
                output.append(output[source])
                source += 1
            }

            if index + 1 < sequenceCount {
                // States update literal length, match length, offset.
                llState.advance(reader: &reader)
                mlState.advance(reader: &reader)
                ofState.advance(reader: &reader)
            }
        }

        output.append(contentsOf: literals[literalCursor...])
    }

    /// Apply the repeat-offset rules and return the byte distance to match
    /// back by.
    private mutating func resolveOffset(_ offsetValue: Int, literalLength: Int) throws -> Int {
        guard offsetValue > 0 else {
            throw ZstdError.corrupted("offset value 0 is not encodable")
        }
        if offsetValue > 3 {
            let offset = offsetValue - 3
            repeatOffsets = (offset, repeatOffsets.0, repeatOffsets.1)
            return offset
        }
        // A zero literal length shifts the repeat codes along by one, which
        // is how the format spends the otherwise-wasted "repeat the offset
        // we just used" encoding.
        let repeatCode = offsetValue - 1 + (literalLength == 0 ? 1 : 0)
        if repeatCode == 0 {
            return repeatOffsets.0
        }
        let offset: Int
        switch repeatCode {
        case 1: offset = repeatOffsets.1
        case 2: offset = repeatOffsets.2
        default: offset = repeatOffsets.0 - 1
        }
        guard offset > 0 else {
            throw ZstdError.corrupted("repeat offset resolves to 0")
        }
        let third = repeatCode >= 2 ? repeatOffsets.1 : repeatOffsets.2
        repeatOffsets = (offset, repeatOffsets.0, third)
        return offset
    }

    private func readSequenceTable(
        mode: UInt8,
        previous: ZstdFSETable?,
        predefined: ZstdFSETable,
        maxSymbol: Int,
        maxTableLog: Int,
        bytes: [UInt8],
        cursor: inout Int,
        end: Int,
        name: String
    ) throws -> ZstdFSETable {
        switch mode {
        case 0:
            return predefined
        case 1:
            guard cursor < end else {
                throw ZstdError.corrupted("truncated RLE \(name) table")
            }
            let symbol = bytes[cursor]
            cursor += 1
            guard Int(symbol) <= maxSymbol else {
                throw ZstdError.corrupted("RLE \(name) symbol \(symbol) is out of range")
            }
            return .rle(symbol: symbol)
        case 2:
            let distribution = try ZstdFSETable.readDistribution(
                bytes: bytes,
                range: cursor..<end,
                maxSymbol: maxSymbol,
                maxTableLog: maxTableLog
            )
            cursor += distribution.bytesRead
            return try ZstdFSETable(distribution: distribution)
        default:
            guard let previous else {
                throw ZstdError.corrupted("\(name) table repeats a table no previous block defined")
            }
            return previous
        }
    }

    private func readLE32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        UInt32(bytes[index])
            | UInt32(bytes[index + 1]) << 8
            | UInt32(bytes[index + 2]) << 16
            | UInt32(bytes[index + 3]) << 24
    }
}
