//
//  XDFlagTable.swift
//  XD
//
//  XD's flags are two artifacts that are useless apart. The *values* are the
//  three bit banks in save section 8; the *schema* — how wide each flag is and
//  which bank it lives in — is `common.rel`'s `GeneralFlags` table. Nothing in
//  the save says where one flag ends and the next begins, so without the table
//  the banks are an undelimited bit soup.
//
//  This type is the schema half plus the bit codec. Full derivation, and the
//  evidence behind every rule below, in
//  `Documentation/Assembly Analysis/Data Structures/Flags.md`.
//

import GoDFoundation
import Structs

/// The `GeneralFlags` descriptor table, with each flag's bit position resolved.
public struct XDFlagTable: Equatable {

    /// One flag's schema. `bitPosition` is not read from the table — see
    /// `init(entries:)`.
    public struct Flag: Equatable {
        /// Index into the table; this is the id every `GSflag*` call passes.
        public let id: Int
        /// 1-3, a 1-based index into the layout chunk's `banks`. 0 means the
        /// flag has no storage at all; nothing in either retail table uses it.
        public let bank: Int
        /// 1-32. Most flags are 1 bit, but 149 of the 2324 are wider —
        /// counters and progress values, not booleans.
        public let bitLength: Int
        /// Bit offset within the bank, derived at load — see `init(entries:)`.
        public let bitPosition: Int
        /// The next flag in the debug menu's traversal chain, `-1` at the end.
        /// Carried so the table round-trips; nothing here reads it.
        public let nextFlagID: Int

        public var hasStorage: Bool { bank >= 1 && bitLength > 0 }
    }

    public let flags: [Flag]

    public enum Error: Swift.Error, CustomStringConvertible {
        case badRow(index: Int, reason: String)
        case bankOverflow(bank: Int, needed: Int, capacity: Int)
        case unknownBank(flag: Int, bank: Int)
        case missingColumn(name: String, found: [String])

        public var description: String {
            switch self {
            case let .badRow(index, reason):
                return "XD flag table: row \(index) is unusable — \(reason)"
            case let .bankOverflow(bank, needed, capacity):
                return "XD flag table: bank \(bank) needs \(needed) bits but the save gives it \(capacity)"
            case let .unknownBank(flag, bank):
                return "XD flag table: flag \(flag) names bank \(bank), which the layout doesn't declare"
            case let .missingColumn(name, found):
                return "Flag table: the CSV has no '\(name)' column — found \(found.joined(separator: ", "))"
            }
        }
    }

    /// One raw table row, exactly as the `GeneralFlags` CSV carries it.
    public struct RawEntry: Equatable {
        public let bankAndBitLength: UInt8
        public let reserved: UInt8
        /// Scratch on disc — zero in every entry of every region's table.
        public let bitPosition: UInt16
        public let nextFlagID: Int16

        public init(bankAndBitLength: UInt8, reserved: UInt8, bitPosition: UInt16, nextFlagID: Int16) {
            self.bankAndBitLength = bankAndBitLength
            self.reserved = reserved
            self.bitPosition = bitPosition
            self.nextFlagID = nextFlagID
        }
    }

    /// Resolves every flag's bit position, reproducing `GSflagInitBitPos`.
    ///
    /// The table on disc carries no bit positions — its `bitPosition` field is
    /// scratch that the game fills in at boot. The rule is a running total per
    /// bank, in table order: a flag sits immediately after every lower-numbered
    /// flag of the same bank. So the positions are a pure function of table
    /// order and bit widths, and inserting a flag shifts everything later in
    /// its bank.
    ///
    /// The game clamps a width of 0 up to 1 and anything above 32 down to 32,
    /// logging either; this does the same so a hand-edited table lands where
    /// the game would put it rather than somewhere else.
    public init(entries: [RawEntry]) {
        var cursors: [Int: Int] = [:]
        var resolved: [Flag] = []
        resolved.reserveCapacity(entries.count)
        for (index, entry) in entries.enumerated() {
            let bank = Int((entry.bankAndBitLength >> 6) & 0x3)
            var bitLength = Int(entry.bankAndBitLength & 0x3F)
            if bitLength == 0 { bitLength = 1 }
            if bitLength > 32 { bitLength = 32 }
            var position = 0
            if bank >= 1 {
                position = cursors[bank, default: 0]
                cursors[bank] = position + bitLength
            }
            resolved.append(Flag(
                id: index,
                bank: bank,
                bitLength: bitLength,
                bitPosition: position,
                nextFlagID: Int(entry.nextFlagID)
            ))
        }
        self.flags = resolved
    }

    /// Bits the table needs in each bank — what `GSflagInitBitPos` checks
    /// against the capacities `GSflagInit` was handed.
    public func bitsNeeded(inBank bank: Int) -> Int {
        flags.filter { $0.bank == bank }.reduce(0) { $0 + $1.bitLength }
    }

    // MARK: - Bit codec

    /// Reads one flag out of its bank, per `_flagGet`.
    ///
    /// Banks are big-endian `u32` words and bit 0 is a word's LSB. A multi-bit
    /// flag may straddle a word boundary, which is why the wide path pulls in
    /// the following word — the game does the same.
    public static func value(of flag: Flag, in bank: [UInt32]) -> UInt32 {
        guard flag.hasStorage else { return 0 }
        func word(_ index: Int) -> UInt32 {
            guard index >= 0, index < bank.count else { return 0 }
            return bank[index]
        }
        let wordIndex = flag.bitPosition >> 5
        let bit = flag.bitPosition & 0x1F
        let low = word(wordIndex)
        var raw: UInt32
        if bit == 0 {
            raw = low
        } else {
            raw = (word(wordIndex + 1) << (32 - UInt32(bit))) | (low >> UInt32(bit))
        }
        if flag.bitLength >= 32 { return raw }
        return raw & ((1 << UInt32(flag.bitLength)) - 1)
    }

    /// Writes one flag into its bank, per `_flagSet`. Values wider than the
    /// flag are masked down, as the game does after logging.
    public static func setValue(_ value: UInt32, of flag: Flag, in bank: inout [UInt32]) {
        guard flag.hasStorage else { return }
        let mask: UInt32 = flag.bitLength >= 32 ? .max : (1 << UInt32(flag.bitLength)) - 1
        let v = value & mask
        let wordIndex = flag.bitPosition >> 5
        let bit = flag.bitPosition & 0x1F
        guard wordIndex < bank.count else { return }
        bank[wordIndex] &= ~(mask << UInt32(bit))
        bank[wordIndex] |= (v << UInt32(bit))
        // The part that spilled past this word's top bit.
        if bit != 0, flag.bitLength + bit > 32, wordIndex + 1 < bank.count {
            let shift = UInt32(32 - bit)
            bank[wordIndex + 1] &= ~(mask >> shift)
            bank[wordIndex + 1] |= (v >> shift)
        }
    }

    // MARK: - Bank <-> words

    /// Banks are read and written as big-endian `u32` words, which is the unit
    /// the bit codec works in. A bank whose byte length isn't a multiple of 4
    /// would be a malformed engine declaration, so the tail is simply ignored.
    public static func words(of bytes: ArraySlice<UInt8>) -> [UInt32] {
        let base = bytes.startIndex
        return stride(from: 0, to: bytes.count - (bytes.count % 4), by: 4).map { offset in
            (UInt32(bytes[base + offset]) << 24)
                | (UInt32(bytes[base + offset + 1]) << 16)
                | (UInt32(bytes[base + offset + 2]) << 8)
                | UInt32(bytes[base + offset + 3])
        }
    }

    public static func bytes(of words: [UInt32]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(words.count * 4)
        for word in words {
            out.append(UInt8((word >> 24) & 0xFF))
            out.append(UInt8((word >> 16) & 0xFF))
            out.append(UInt8((word >> 8) & 0xFF))
            out.append(UInt8(word & 0xFF))
        }
        return out
    }

    // MARK: - Loading the table

    /// Column names the table CSV must carry. Everything else in the file is
    /// ignored, which is what lets one codec read both games' tables.
    public enum Column {
        public static let bankAndBitLength = "bankAndBitLength"
        public static let nextFlagID = "nextFlagID"
    }

    /// Reads a flag descriptor table from the CSV a REL/DOL dump writes for it.
    ///
    /// Read **by column name, not by byte offset**. XD's descriptor is 6 bytes
    /// and Colosseum's is 8, with the bit position and the chain link at
    /// different offsets in each — but both declare the same named fields, so
    /// naming the columns removes the stride from this codec entirely. A game
    /// whose table gains a field costs nothing here.
    ///
    /// The on-disc `bitPosition` column is deliberately not read: it is scratch
    /// the game fills in at boot, zero in every entry of every retail table,
    /// and `init(entries:)` recomputes it.
    public static func load(csv text: String) throws -> (table: XDFlagTable, warnings: [String]) {
        let rows = try CSV.parse(text)
        guard let header = rows.first else {
            throw Error.badRow(index: 0, reason: "the table CSV has no header row")
        }
        guard let packedColumn = header.firstIndex(of: Column.bankAndBitLength) else {
            throw Error.missingColumn(name: Column.bankAndBitLength, found: header)
        }
        // The chain link is only carried so the table round-trips; a table
        // without it still decodes flags correctly.
        let linkColumn = header.firstIndex(of: Column.nextFlagID)

        var entries: [RawEntry] = []
        var warnings: [String] = []
        for (offset, row) in rows.dropFirst().enumerated() {
            if row.allSatisfy(\.isEmpty) { continue }
            let index = offset + 1
            guard row.count > packedColumn,
                  let packed = UInt8(row[packedColumn].trimmingCharacters(in: .whitespaces)) else {
                throw Error.badRow(index: index, reason: "'\(Column.bankAndBitLength)' is not a byte value")
            }
            var link: Int16 = -1
            if let linkColumn, row.count > linkColumn,
               let value = Int(row[linkColumn].trimmingCharacters(in: .whitespaces)) {
                link = Int16(truncatingIfNeeded: value)
            }
            entries.append(RawEntry(
                bankAndBitLength: packed,
                reserved: 0,
                bitPosition: 0,
                nextFlagID: link
            ))
        }
        if linkColumn == nil {
            warnings.append("no '\(Column.nextFlagID)' column — the debug-menu chain won't round-trip")
        }
        return (XDFlagTable(entries: entries), warnings)
    }
}
