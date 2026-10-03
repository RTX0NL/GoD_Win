//
//  ZstdFSE.swift
//
//  Finite State Entropy — the tANS coder Zstandard uses for its sequence
//  symbols and for the Huffman weight table. A table description gives each
//  symbol a *normalized count*: how many of the table's `1 << tableLog`
//  states decode to it. Decoding walks a state through those slots,
//  refilling it with bits from the stream as it goes.
//
//  Reference: RFC 8878 §4.1, facebook/zstd `lib/common/fse_decompress.c`
//

import Foundation

struct ZstdFSETable {

    struct Entry {
        var symbol: UInt8
        var nbBits: UInt8
        var newState: UInt16
    }

    /// log2 of the table size. Zero means a single-symbol (RLE) table,
    /// which reads no bits at all.
    let tableLog: Int
    let entries: [Entry]

    /// A table that always decodes one symbol and never reads a bit.
    static func rle(symbol: UInt8) -> ZstdFSETable {
        ZstdFSETable(tableLog: 0, entries: [Entry(symbol: symbol, nbBits: 0, newState: 0)])
    }

    // MARK: - Table description

    /// A decoded normalized-count table, as read from a stream.
    struct Distribution {
        var counts: [Int16]      // indexed by symbol, one per symbol 0...maxSymbol
        var maxSymbol: Int
        var tableLog: Int
        var bytesRead: Int
    }

    /// Read an FSE table description (RFC 8878 §4.1.1).
    ///
    /// - Parameters:
    ///   - maxSymbol: the largest symbol the caller's alphabet allows.
    ///   - maxTableLog: the largest accuracy log the caller's alphabet allows.
    static func readDistribution(
        bytes: [UInt8],
        range: Range<Int>,
        maxSymbol maxSymbolLimit: Int,
        maxTableLog: Int
    ) throws -> Distribution {
        guard !range.isEmpty else {
            throw ZstdError.corrupted("empty FSE table description")
        }
        var reader = ZstdForwardBitReader(bytes: bytes, range: range)

        let tableLog = Int(reader.read(4)) + 5
        guard tableLog <= maxTableLog else {
            throw ZstdError.corrupted("FSE accuracy log \(tableLog) exceeds the \(maxTableLog) this table allows")
        }

        var counts = [Int16](repeating: 0, count: maxSymbolLimit + 1)
        var remaining = (1 << tableLog) + 1
        var threshold = 1 << tableLog
        var nbBits = tableLog + 1
        var symbol = 0
        var previousWasZero = false

        while remaining > 1 && symbol <= maxSymbolLimit {
            if previousWasZero {
                // A zero count is followed by a run of 2-bit repeat codes;
                // 0b11 means "three more zeroes, keep reading".
                while reader.peek(2) == 3 {
                    symbol += 3
                    _ = reader.read(2)
                }
                symbol += Int(reader.read(2))
                previousWasZero = false
                // A run may end exactly on the alphabet's last symbol, which
                // is a normal finish: the symbols it skipped keep their zero
                // counts. Overshooting it is the error, caught below.
                if symbol > maxSymbolLimit { break }
            }

            let max = (2 * threshold - 1) - remaining
            var count: Int
            if Int(reader.peek(nbBits - 1)) < max {
                count = Int(reader.read(nbBits - 1))
            } else {
                count = Int(reader.read(nbBits))
                if count >= threshold { count -= max }
            }
            count -= 1                       // -1 encodes "low probability"

            remaining -= abs(count)
            counts[symbol] = Int16(count)
            symbol += 1
            previousWasZero = (count == 0)

            if remaining < threshold {
                if remaining <= 1 { break }
                nbBits = Int(ZstdBitReader.highestSetBit(UInt32(remaining))) + 1
                threshold = 1 << (nbBits - 1)
            }
        }

        guard remaining == 1 else {
            throw ZstdError.corrupted("FSE table's counts do not fill its \(1 << tableLog) states")
        }
        guard symbol <= maxSymbolLimit + 1 else {
            throw ZstdError.corrupted("FSE table describes more symbols than the alphabet has")
        }
        let bytesRead = reader.bytesConsumed
        guard bytesRead <= range.count else {
            throw ZstdError.corrupted("FSE table description runs past the end of its section")
        }
        return Distribution(
            counts: counts,
            maxSymbol: max(0, symbol - 1),
            tableLog: tableLog,
            bytesRead: bytesRead
        )
    }

    // MARK: - Table construction

    /// Build a decoding table from normalized counts.
    ///
    /// Symbols with a count of -1 ("low probability") take the states at the
    /// very top of the table; everything else is spread across the rest with
    /// the reference's fixed stride, which is what makes two independent
    /// implementations agree on which state means which symbol.
    init(distribution: Distribution) throws {
        let tableLog = distribution.tableLog
        let tableSize = 1 << tableLog
        let tableMask = tableSize - 1
        guard tableSize > 1 else {
            throw ZstdError.corrupted("FSE table too small")
        }

        var table = [Entry](repeating: Entry(symbol: 0, nbBits: 0, newState: 0), count: tableSize)
        var symbolNext = [Int](repeating: 0, count: distribution.maxSymbol + 1)
        var highThreshold = tableSize - 1

        for symbol in 0...distribution.maxSymbol {
            let count = Int(distribution.counts[symbol])
            if count == -1 {
                table[highThreshold].symbol = UInt8(symbol)
                highThreshold -= 1
                symbolNext[symbol] = 1
            } else {
                symbolNext[symbol] = count
            }
        }

        // Spread the remaining symbols. The step is the reference's
        // (size/2 + size/8 + 3), chosen to be coprime with the table size.
        let step = (tableSize >> 1) + (tableSize >> 3) + 3
        var position = 0
        for symbol in 0...distribution.maxSymbol {
            let count = Int(distribution.counts[symbol])
            guard count > 0 else { continue }
            for _ in 0..<count {
                table[position].symbol = UInt8(symbol)
                position = (position + step) & tableMask
                while position > highThreshold {
                    position = (position + step) & tableMask
                }
            }
        }
        guard position == 0 else {
            throw ZstdError.corrupted("FSE table's counts do not tile its states")
        }

        for state in 0..<tableSize {
            let symbol = Int(table[state].symbol)
            let nextState = symbolNext[symbol]
            symbolNext[symbol] = nextState + 1
            let nbBits = tableLog - Int(ZstdBitReader.highestSetBit(UInt32(nextState)))
            table[state].nbBits = UInt8(nbBits)
            table[state].newState = UInt16((nextState << nbBits) - tableSize)
        }

        self.tableLog = tableLog
        self.entries = table
    }

    private init(tableLog: Int, entries: [Entry]) {
        self.tableLog = tableLog
        self.entries = entries
    }

    /// Build a table directly from a fixed distribution — how the
    /// predefined sequence tables are made.
    init(predefinedCounts counts: [Int16], tableLog: Int) throws {
        try self.init(distribution: Distribution(
            counts: counts,
            maxSymbol: counts.count - 1,
            tableLog: tableLog,
            bytesRead: 0
        ))
    }
}

/// One decoder's position in an FSE-coded stream.
struct ZstdFSEState {
    let table: ZstdFSETable
    var state: Int

    init(table: ZstdFSETable, reader: inout ZstdBitReader) {
        self.table = table
        self.state = Int(reader.readBits(table.tableLog))
    }

    @inline(__always)
    var symbol: UInt8 { table.entries[state].symbol }

    @inline(__always)
    var entry: ZstdFSETable.Entry { table.entries[state] }

    /// Advance to the next state, taking this state's refill bits.
    @inline(__always)
    mutating func advance(reader: inout ZstdBitReader) {
        let e = table.entries[state]
        state = Int(e.newState) + Int(reader.readBits(Int(e.nbBits)))
    }

    /// Read this state's symbol and advance — the combined operation the
    /// Huffman-weight and literal-length paths use.
    @inline(__always)
    mutating func next(reader: inout ZstdBitReader) -> UInt8 {
        let e = table.entries[state]
        state = Int(e.newState) + Int(reader.readBits(Int(e.nbBits)))
        return e.symbol
    }
}
