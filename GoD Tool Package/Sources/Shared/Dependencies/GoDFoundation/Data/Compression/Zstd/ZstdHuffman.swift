//
//  ZstdHuffman.swift
//
//  Zstandard's Huffman coder, used for the literals of a compressed block.
//
//  The tree is transmitted as one *weight* per symbol rather than a code
//  length: weight w means the symbol's code is `maxBits + 1 - w` bits long
//  and occupies `1 << (w - 1)` slots of the decoding table. The last
//  symbol's weight is never sent — it is whatever makes the table add up to
//  a power of two, which is also the check that the description was read
//  correctly.
//
//  Reference: RFC 8878 §4.2.1, facebook/zstd `lib/common/huf.h`
//

import Foundation

struct ZstdHuffmanTable {

    struct Entry {
        var symbol: UInt8
        var nbBits: UInt8
    }

    /// Bits consumed by one table lookup — the longest code in the tree.
    let maxBits: Int
    /// `1 << maxBits` entries, indexed by the next `maxBits` bits of the
    /// stream.
    let entries: [Entry]

    static let maxTableLog = 11
    static let maxSymbolCount = 256

    /// Parse a Huffman tree description and return the table plus how many
    /// bytes it occupied.
    static func read(bytes: [UInt8], range: Range<Int>) throws -> (table: ZstdHuffmanTable, bytesRead: Int) {
        guard !range.isEmpty else {
            throw ZstdError.corrupted("missing Huffman tree description")
        }
        let header = Int(bytes[range.lowerBound])
        var weights: [UInt8]
        let bytesRead: Int

        if header >= 128 {
            // Direct representation: one 4-bit weight per nibble, high
            // nibble first.
            let count = header - 127
            let nibbleBytes = (count + 1) / 2
            guard range.lowerBound + 1 + nibbleBytes <= range.upperBound else {
                throw ZstdError.corrupted("Huffman weights run past the end of the literals section")
            }
            weights = [UInt8]()
            weights.reserveCapacity(count)
            for i in 0..<count {
                let byte = bytes[range.lowerBound + 1 + i / 2]
                weights.append(i % 2 == 0 ? (byte >> 4) : (byte & 0x0F))
            }
            bytesRead = 1 + nibbleBytes
        } else {
            // FSE-compressed weights. `header` is the compressed size.
            guard range.lowerBound + 1 + header <= range.upperBound else {
                throw ZstdError.corrupted("FSE-coded Huffman weights run past the end of the literals section")
            }
            weights = try decodeFSEWeights(
                bytes: bytes,
                range: (range.lowerBound + 1)..<(range.lowerBound + 1 + header)
            )
            bytesRead = 1 + header
        }

        return (try ZstdHuffmanTable(weights: weights), bytesRead)
    }

    /// Build the decoding table from the transmitted weights, deriving the
    /// final symbol's weight from what is left over.
    init(weights transmitted: [UInt8]) throws {
        guard !transmitted.isEmpty, transmitted.count < ZstdHuffmanTable.maxSymbolCount else {
            throw ZstdError.corrupted("Huffman tree describes \(transmitted.count) symbols")
        }
        var weights = transmitted

        var totalWeight = 0
        for w in weights {
            guard w <= ZstdHuffmanTable.maxTableLog else {
                throw ZstdError.corrupted("Huffman weight \(w) exceeds the format's maximum")
            }
            if w > 0 { totalWeight += 1 << (Int(w) - 1) }
        }
        guard totalWeight > 0 else {
            throw ZstdError.corrupted("Huffman tree has no present symbols")
        }

        let maxBits = Int(ZstdBitReader.highestSetBit(UInt32(totalWeight))) + 1
        guard maxBits <= ZstdHuffmanTable.maxTableLog else {
            throw ZstdError.corrupted("Huffman tree needs \(maxBits) bits, more than the format allows")
        }
        let leftover = (1 << maxBits) - totalWeight
        guard leftover > 0, leftover & (leftover - 1) == 0 else {
            throw ZstdError.corrupted("Huffman weights leave \(leftover) states, which is not one symbol's worth")
        }
        weights.append(UInt8(ZstdBitReader.highestSetBit(UInt32(leftover)) + 1))

        // Codes go to symbols sorted by weight ascending, then by symbol
        // value — the canonical order both ends agree on. A symbol of
        // weight w claims `1 << (w - 1)` consecutive table slots.
        var table = [Entry](repeating: Entry(symbol: 0, nbBits: 0), count: 1 << maxBits)
        var position = 0
        for weight in 1...maxBits {
            for (symbol, w) in weights.enumerated() where Int(w) == weight {
                let slots = 1 << (weight - 1)
                let nbBits = UInt8(maxBits + 1 - weight)
                guard position + slots <= table.count else {
                    throw ZstdError.corrupted("Huffman codes overflow their table")
                }
                for i in 0..<slots {
                    table[position + i] = Entry(symbol: UInt8(symbol), nbBits: nbBits)
                }
                position += slots
            }
        }
        guard position == table.count else {
            throw ZstdError.corrupted("Huffman codes fill \(position) of \(table.count) table slots")
        }

        self.maxBits = maxBits
        self.entries = table
    }

    // MARK: - Weight stream

    /// Decode an FSE-coded weight stream. Two states share one bitstream,
    /// alternating, and the stream ends by running out of bits rather than
    /// by a count.
    private static func decodeFSEWeights(bytes: [UInt8], range: Range<Int>) throws -> [UInt8] {
        let distribution = try ZstdFSETable.readDistribution(
            bytes: bytes,
            range: range,
            maxSymbol: ZstdHuffmanTable.maxTableLog,
            maxTableLog: 6
        )
        let table = try ZstdFSETable(distribution: distribution)
        let streamStart = range.lowerBound + distribution.bytesRead
        guard streamStart < range.upperBound else {
            throw ZstdError.corrupted("Huffman weight stream is empty")
        }
        var reader = try ZstdBitReader(bytes: bytes, range: streamStart..<range.upperBound)
        var first = ZstdFSEState(table: table, reader: &reader)
        var second = ZstdFSEState(table: table, reader: &reader)

        let limit = ZstdHuffmanTable.maxSymbolCount - 1
        var weights = [UInt8]()
        weights.reserveCapacity(limit)
        while true {
            guard weights.count + 2 <= limit else {
                throw ZstdError.corrupted("Huffman weight stream describes more than \(limit) symbols")
            }
            weights.append(first.next(reader: &reader))
            if reader.reload() == .overflow {
                weights.append(second.next(reader: &reader))
                break
            }
            guard weights.count + 2 <= limit else {
                throw ZstdError.corrupted("Huffman weight stream describes more than \(limit) symbols")
            }
            weights.append(second.next(reader: &reader))
            if reader.reload() == .overflow {
                weights.append(first.next(reader: &reader))
                break
            }
        }
        return weights
    }

    // MARK: - Decoding

    /// Decode exactly `count` symbols from one Huffman stream into `out`.
    func decode(
        count: Int,
        bytes: [UInt8],
        range: Range<Int>,
        into out: inout [UInt8]
    ) throws {
        guard count > 0 else { return }
        var reader = try ZstdBitReader(bytes: bytes, range: range)
        let table = entries
        let bits = maxBits
        var produced = 0
        // Four symbols between reloads: at most 4 × 11 bits, plus the 7
        // that can be left over after a reload, stays inside the 64-bit
        // window.
        while produced < count {
            reader.reload()
            let batch = min(4, count - produced)
            for _ in 0..<batch {
                let entry = table[Int(reader.lookBits(bits))]
                reader.skipBits(Int(entry.nbBits))
                out.append(entry.symbol)
            }
            produced += batch
        }
    }
}
