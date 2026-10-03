//
//  MSGFile.swift
//
//  Pokemon Colosseum / XD message string table.
//
//  Header (big-endian):
//    0x00  UInt32   reservedPrefix  (varies per file; not a magic)
//    0x04  UInt16   entry count
//    0x06  2 bytes  region code (ASCII, e.g. "US", "JP")
//    0x08  8 bytes  reservedSuffix (observed all-zero; preserved verbatim)
//
//  Entry table at 0x10, `count` × 8 bytes:
//    UInt32 id (low 20 bits effective), UInt32 offset (file-relative)
//
//  Strings: GS-encoded, terminator 0x0000, packed with no alignment.
//  Specials: 0xFFFF + 1-byte code + 0..4 param bytes (Colo/XD share layout).
//
//  The pool is *not* written in entry-table order. Across 221 real files
//  (211 XD, 10 Colosseum) 104 lay their strings out in some other order, so
//  an entry carries the rank of its string in the pool (`poolOrder`) as well
//  as its text. With that, laying the pool out in rank order reproduces all
//  221 byte-for-byte: the pool is contiguous, unpadded and unaligned, and no
//  two entries share a string. One file also carries strings no entry points
//  at (`detachedStrings`).
//

import Foundation
import GoDFoundation

public struct MSGFile: FileFormat, Equatable {
    public static let formatName = "msg"

    public var name: String = "msg"

    /// Colo and XD share the binary layout. The variant only affects how
    /// control codes are rendered to / parsed from the pretty JSON form.
    public enum Variant: String, Codable {
        case colo
        case xd

        var stringFormat: StringFormats {
            switch self {
            case .colo: return .gsColo
            case .xd:   return .gsXD
            }
        }
    }

    public struct Entry: Codable, Equatable {
        public let id: UInt32
        public var string: GSString
        /// Rank of this entry's string in the file's string pool, when the
        /// pool isn't written in entry order. `nil` means "wherever the
        /// layout puts it" — a new entry, or a file whose pool already runs
        /// in entry order — and those are laid out after every ranked string,
        /// in entry order.
        public var poolOrder: Int?
        /// The string's bytes, kept when the character codec can't reproduce
        /// them — a control code the game truncated, or one whose pretty
        /// form doesn't parse back to the same bytes. Set, it is what gets
        /// written, and `string` is only a best-effort reading of it.
        ///
        /// One string in 2312 across the six GameCube discs needs this:
        /// Colosseum JP's move viewer ends a string with a parameterless
        /// `FFFF 09`, where all 239 other occurrences of that code carry a
        /// parameter byte. Without the fallback the parser eats the null
        /// word as that parameter and runs on into the next string.
        public var rawBytes: [UInt8]?

        public init(id: UInt32, string: GSString, poolOrder: Int? = nil, rawBytes: [UInt8]? = nil) {
            self.id = id
            self.string = string
            self.poolOrder = poolOrder
            self.rawBytes = rawBytes
        }

        /// What this entry contributes to the pool, terminator excluded.
        var poolBytes: [UInt8] {
            rawBytes ?? string.rawData(byteOrder: .big).rawBytes
        }
    }

    /// A string sitting in the pool that no entry points at. XD JP's
    /// `M6_tower_1F.msg` declares one entry and carries 450 bytes of these
    /// ahead of it; dropping them would shrink the file and move every
    /// offset after them.
    public struct DetachedString: Codable, Equatable {
        /// Rank in the pool, in the same numbering as `Entry.poolOrder`.
        public var poolOrder: Int
        public var string: GSString

        public init(poolOrder: Int, string: GSString) {
            self.poolOrder = poolOrder
            self.string = string
        }
    }

    public var variant: Variant
    /// Raw bytes 0x00..0x03 preserved for byte-identical rebuild.
    public var reservedPrefix: [UInt8]
    /// Raw bytes 0x06..0x07 (region code). Two ASCII bytes in the samples
    /// observed, but kept as raw bytes to support anything.
    public var region: [UInt8]
    /// Raw bytes 0x08..0x0F (observed all-zero). Preserved verbatim.
    public var reservedSuffix: [UInt8]
    public var entries: [Entry]
    /// Pool strings no entry references. Empty in all but one real file.
    public var detachedStrings: [DetachedString]
    /// Bytes after the pool that are not a string. A `.msg` file has none —
    /// all 221 real ones end on their last terminator — but a table embedded
    /// in a DOL or REL is padded out to a 4-byte boundary by its container,
    /// and those 1-3 bytes reach this parser as part of the chunk. Keeping
    /// them is what stops a rewritten chunk from shrinking and shifting
    /// every symbol after it.
    public var trailingBytes: [UInt8]

    public init(
        variant: Variant,
        reservedPrefix: [UInt8] = [0, 0, 0, 0],
        region: [UInt8] = [0x55, 0x53],         // "US"
        reservedSuffix: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0],
        entries: [Entry] = [],
        detachedStrings: [DetachedString] = [],
        trailingBytes: [UInt8] = []
    ) {
        self.variant = variant
        self.reservedPrefix = reservedPrefix
        self.region = region
        self.reservedSuffix = reservedSuffix
        self.entries = entries
        self.detachedStrings = detachedStrings
        self.trailingBytes = trailingBytes
    }

    // MARK: - FileFormat (binary)

    /// Parse from a single raw `.msg` binary. Defaults to XD control-code
    /// semantics; use `init(binary:variant:)` for Colo.
    public init(binaries: [FileData]) throws {
        guard let first = binaries.first else {
            throw MSGFile.invalidFileError
        }
        let stem = first.file.fileName.withoutExtensions
        try self.init(binary: first.data, variant: .xd, name: stem.isEmpty ? "msg" : stem)
    }

    public init(binary: GoDData, variant: Variant, name: String = "msg") throws {
        let data = binary.copy
        data.setByteOrder(.big)
        guard data.length >= 0x10 else { throw MSGFile.invalidFileError }

        // A Battle Revolution string table is a different format that
        // happens to use the same extension. Its count sits at +0x06, so
        // this parser would read zero strings at +0x04 and "succeed" with an
        // empty file — dropping every string it was handed. Refuse instead.
        if data.readString(atAddress: 0x00, format: .utf8, maxCharacters: 4) == "MESG" {
            throw MSGFileError.battleRevolutionStringTable()
        }

        let prefix: UInt32 = data.readValue(atAddress: 0x00) ?? 0
        guard let count: UInt16 = data.readValue(atAddress: 0x04) else {
            throw MSGFile.invalidFileError
        }
        let regionBytes = data.read(atAddress: 0x06, length: 2)?.rawBytes ?? [0, 0]
        let suffixBytes = data.read(atAddress: 0x08, length: 8)?.rawBytes
            ?? [UInt8](repeating: 0, count: 8)

        let tableStart = 0x10
        let tableEnd = tableStart + Int(count) * 8
        guard data.length >= tableEnd else { throw MSGFile.invalidFileError }

        // The table first, then the strings: a string's extent is decided by
        // where the next one starts, and reading it unbounded lets one
        // malformed control code swallow everything after it.
        var ids: [UInt32] = []
        var stringOffsets: [Int] = []
        ids.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            let entryOffset = tableStart + i * 8
            guard let rawId: UInt32 = data.readValue(atAddress: entryOffset),
                  let stringOffset: UInt32 = data.readValue(atAddress: entryOffset + 4) else {
                throw MSGFile.invalidFileError
            }
            ids.append(rawId)
            stringOffsets.append(Int(stringOffset))
        }

        var nextStringStart: [Int: Int] = [:]
        let sortedOffsets = Set(stringOffsets).sorted()
        for (index, offset) in sortedOffsets.enumerated() where index + 1 < sortedOffsets.count {
            nextStringStart[offset] = sortedOffsets[index + 1]
        }

        var entries: [Entry] = []
        entries.reserveCapacity(Int(count))
        for (id, offset) in zip(ids, stringOffsets) {
            entries.append(MSGFile.entry(
                id: id,
                at: offset,
                boundedBy: nextStringStart[offset],
                in: data,
                format: variant.stringFormat
            ))
        }

        // What's left of the pool once the entries have their extents: the
        // run before the first claimed string, and whatever follows the
        // last one.
        // The last string has no next one to bound it, so its own reading
        // says where the pool's claimed part ends.
        let lastEnd = sortedOffsets.last.flatMap { offset in
            stringOffsets.firstIndex(of: offset).map { offset + entries[$0].poolBytes.count + 2 }
        }
        let (detached, trailing) = MSGFile.poolRemainder(
            in: data,
            poolStart: tableEnd,
            firstClaimed: sortedOffsets.first,
            endOfClaimed: lastEnd,
            format: variant.stringFormat
        )

        // The pool's layout is a permutation of the entry table: rank every
        // string by the address it was read from, and both directions agree
        // on what "third string in the pool" means.
        let ranks = MSGFile.poolRanks(of: stringOffsets + detached.map(\.offset))
        for i in entries.indices {
            entries[i].poolOrder = ranks[stringOffsets[i]]
        }

        self.init(
            variant: variant,
            reservedPrefix: prefixBytes(prefix),
            region: regionBytes,
            reservedSuffix: suffixBytes,
            entries: entries,
            detachedStrings: detached.map {
                DetachedString(poolOrder: ranks[$0.offset] ?? 0, string: $0.string)
            },
            trailingBytes: trailing
        )
        self.name = name
    }

    /// Reads one entry's string, and checks the reading against the bytes.
    ///
    /// `bound` is where the next string starts, when there is one. Inside
    /// it the character codec is authoritative; where re-encoding what it
    /// read doesn't give the bytes back, the string is written back as the
    /// codec renders it and the file changes. Keeping the original bytes
    /// instead made a codec that can't read a control code look like one that
    /// can, so the two Colosseum JP strings that need it never got fixed.
    private static func entry(
        id: UInt32,
        at offset: Int,
        boundedBy bound: Int?,
        in data: GoDData,
        format: StringFormats
    ) -> Entry {
        guard let bound, bound > offset,
              let region = data.read(atAddress: offset, length: bound - offset) else {
            return Entry(id: id, string: data.readGSStringSafely(atAddress: offset, format: format))
        }
        region.setByteOrder(.big)
        let string = region.readGSStringSafely(atAddress: 0, format: format)

        return Entry(id: id, string: string)
    }

    /// The parts of the pool the entry table doesn't claim.
    ///
    /// There are only two, because an entry owns every byte from its string
    /// up to where the next one starts — the pool is contiguous, so the next
    /// string's address *is* the previous one's end, and treating a short
    /// parse as a gap invents strings out of the bytes the codec misread.
    /// So: the run before the first claimed string, and the run after the
    /// last. The first is bounded and read as strings; the second is where
    /// a container's padding sits, so it takes whole non-empty strings and
    /// hands back the rest verbatim.
    private static func poolRemainder(
        in data: GoDData,
        poolStart: Int,
        firstClaimed: Int?,
        endOfClaimed: Int?,
        format: StringFormats
    ) -> (detached: [(offset: Int, string: GSString)], trailing: [UInt8]) {
        var found: [(offset: Int, string: GSString)] = []

        func length(of string: GSString) -> Int {
            string.rawData(byteOrder: .big).length + 2
        }

        var cursor = poolStart
        if let firstClaimed {
            while cursor < firstClaimed {
                let string = data.readGSStringSafely(atAddress: cursor, format: format)
                guard cursor + length(of: string) <= firstClaimed else { break }
                found.append((cursor, string))
                cursor += max(length(of: string), 2)
            }
        }

        cursor = max(cursor, endOfClaimed ?? cursor)
        while cursor < data.length {
            let string = data.readGSStringSafely(atAddress: cursor, format: format)
            let size = length(of: string)
            guard size > 2, cursor + size <= data.length else { break }
            found.append((cursor, string))
            cursor += size
        }

        let trailing = cursor < data.length
            ? (data.read(atAddress: cursor, length: data.length - cursor)?.rawBytes ?? [])
            : []
        return (found, trailing)
    }

    /// Maps each pool address to its position in address order.
    private static func poolRanks(of offsets: [Int]) -> [Int: Int] {
        var ranks: [Int: Int] = [:]
        for (rank, offset) in Set(offsets).sorted().enumerated() {
            ranks[offset] = rank
        }
        return ranks
    }

    /// How many bytes the table at the start of `data` occupies.
    ///
    /// The entry table says where every string begins, and a string ends at
    /// its own terminator, so the file's extent is derivable rather than
    /// something the surrounding container has to guess. That matters for
    /// the tables embedded in `main.dol` and `common.rel`, where the
    /// disassembler's rule is "a chunk ends at the next symbol": XD's
    /// Japanese build has a symbol 776 bytes before the end of one table, so
    /// the chunk used to be cut there and the strings past it were lost.
    ///
    /// The walk uses XD's control-code semantics, which is safe for either
    /// game: the variants differ in how a code is *rendered*, not in how
    /// many bytes it occupies.
    ///
    /// Returns nil when the header doesn't parse or the pool runs past the
    /// buffer — a caller that can't be given an answer keeps its own bound.
    public static func measuredLength(of data: GoDData) -> Int? {
        let data = data.copy
        data.setByteOrder(.big)
        guard data.length >= 0x10 else { return nil }
        guard data.readString(atAddress: 0x00, format: .utf8, maxCharacters: 4) != "MESG" else { return nil }
        guard let count: UInt16 = data.readValue(atAddress: 0x04) else { return nil }

        let tableEnd = 0x10 + Int(count) * 8
        guard data.length >= tableEnd else { return nil }
        guard count > 0 else { return tableEnd }

        var lastStringStart = tableEnd
        for i in 0..<Int(count) {
            guard let offset: UInt32 = data.readValue(atAddress: 0x10 + i * 8 + 4) else { return nil }
            lastStringStart = max(lastStringStart, Int(offset))
        }
        guard lastStringStart >= tableEnd, lastStringStart < data.length else { return nil }

        let last = data.readGSStringSafely(atAddress: lastStringStart, format: .gsXD)
        let end = lastStringStart + last.rawData(byteOrder: .big).length + 2
        return end <= data.length ? end : nil
    }

    public var binaries: [FileData] {
        get throws {
            [FileData(file: File("\(name).\(MSGFile.formatName)"), data: try computedBinaryData)]
        }
    }

    private var computedBinaryData: GoDData {
        get throws {
            let out = GoDData(byteOrder: .big)

            // Header bytes 0x00..0x03
            for b in paddedBytes(reservedPrefix, to: 4) { out.append(UInt8(b)) }
            // Header bytes 0x04..0x05 — count. The field is a u16, so an
            // over-large table would trap on the conversion; reject it.
            guard entries.count <= 0xFFFF else {
                throw FileFormatErrors.failedToEncode(
                    format: MSGFile.formatName,
                    target: "entry count \(entries.count) exceeds the u16 header field maximum (65535)"
                )
            }
            out.append(UInt16(entries.count))
            // Header bytes 0x06..0x07 — region
            for b in paddedBytes(region, to: 2) { out.append(UInt8(b)) }
            // Header bytes 0x08..0x0F — reserved suffix
            for b in paddedBytes(reservedSuffix, to: 8) { out.append(UInt8(b)) }

            // Entries are written in the order they are held. Nothing in the
            // format requires the table to be sorted — the game finds a string
            // by scanning for its id, not by binary search — and sorting here
            // silently reordered whatever order the file was parsed in or the
            // user authored in the JSON.
            let tableStart = 0x10
            let tableLength = entries.count * 8

            // The pool runs in `poolOrder`, which is a different order from
            // the table in about half of the real files. Anything unranked —
            // a string the user added, or a file that never needed ranks —
            // follows in the order it is held.
            var poolItems: [(entryIndex: Int?, order: Int?, bytes: [UInt8])] = []
            for (index, entry) in entries.enumerated() {
                poolItems.append((index, entry.poolOrder, entry.poolBytes))
            }
            for detached in detachedStrings {
                poolItems.append((nil, detached.poolOrder, detached.string.rawData(byteOrder: .big).rawBytes))
            }
            let ranked = poolItems.enumerated()
                .filter { $0.element.order != nil }
                .sorted { ($0.element.order ?? 0, $0.offset) < ($1.element.order ?? 0, $1.offset) }
                .map(\.element)
            let unranked = poolItems.filter { $0.order == nil }

            // Each string is terminated by a null word and the next one
            // starts immediately after it — the game packs the pool with
            // no alignment. Rounding each start up to an even address
            // (which this used to do) is invisible in Colosseum, where
            // every character is two bytes wide, but XD's format is
            // variable-width: an odd-length body cost one pad byte per
            // string. That was the whole of the +546 bytes the three
            // DOL-embedded XD message tables used to gain on re-encode.
            var cursor = tableStart + tableLength
            var offsets = [Int](repeating: 0, count: entries.count)
            var pool: [UInt8] = []
            for item in ranked + unranked {
                if let index = item.entryIndex { offsets[index] = cursor }
                pool.append(contentsOf: item.bytes)
                pool.append(0); pool.append(0)
                cursor += item.bytes.count + 2
            }

            for (index, entry) in entries.enumerated() {
                out.append(entry.id)
                out.append(UInt32(offsets[index]))
            }

            for byte in pool { out.append(byte) }
            for byte in trailingBytes { out.append(byte) }

            return out
        }
    }

    // MARK: - FileFormat (outputs / JSON)

    public init(outputs: [FileData]) throws {
        let dict = outputs.byFile
        let suffix = ".\(MSGFile.formatName).json"
        guard let jsonKey = dict.keys.first(where: { $0.path.hasSuffix(suffix) }) else {
            throw MSGFile.missingOutputError(key: "*\(suffix)")
        }
        let stem = String(jsonKey.path.dropLast(suffix.count))
        guard let jsonData = dict[jsonKey] else {
            throw MSGFile.missingOutputError(key: jsonKey.path)
        }
        let decoder = JSONDecoder()
        let dto = try decoder.decode(DTO.self, from: jsonData.data)
        self.init(
            variant: dto.variant,
            reservedPrefix: MSGFile.bytesFromHex(dto.reservedPrefix) ?? [0, 0, 0, 0],
            region: MSGFile.bytesFromRegion(dto.region) ?? [0x55, 0x53],
            reservedSuffix: MSGFile.bytesFromHex(dto.reservedSuffix)
                ?? [UInt8](repeating: 0, count: 8),
            entries: dto.entries.map { e in
                let raw = e.raw.flatMap(MSGFile.bytesFromHex)
                return Entry(
                    id: e.id,
                    string: raw.map {
                        GoDData(byteStream: $0, byteOrder: .big)
                            .readGSStringSafely(atAddress: 0, format: dto.variant.stringFormat)
                    } ?? GSString(string: e.text ?? "", format: dto.variant.stringFormat),
                    poolOrder: e.poolOrder,
                    rawBytes: raw
                )
            },
            detachedStrings: (dto.detachedStrings ?? []).map { d in
                DetachedString(
                    poolOrder: d.poolOrder,
                    string: GSString(string: d.text, format: dto.variant.stringFormat)
                )
            },
            trailingBytes: dto.trailingBytes.flatMap(MSGFile.bytesFromHex) ?? []
        )
        self.name = stem.isEmpty ? "msg" : stem
    }

    public var outputs: [FileData] {
        get throws {
            // A pool that already runs in entry order needs no ranks, and
            // that is half the real files — leave the column out rather than
            // print 1, 2, 3… beside every string.
            let ranksAreEntryOrder = detachedStrings.isEmpty
                && entries.enumerated().allSatisfy { $0.element.poolOrder == nil || $0.element.poolOrder == $0.offset }
            let dto = DTO(
                variant: variant,
                reservedPrefix: MSGFile.hexFromBytes(reservedPrefix),
                region: MSGFile.regionFromBytes(region),
                reservedSuffix: MSGFile.hexFromBytes(reservedSuffix),
                entries: entries.map { e in
                    // Every entry gets its editable text, whether or not the
                    // pretty form parses back to the same bytes. Emitting hex
                    // instead for the ones that don't made the artifact honest
                    // and the codec's gaps invisible; a string that changes on
                    // the way back is a codec bug to fix, and it shows up as a
                    // file that no longer repacks.
                    DTO.EntryDTO(
                        id: e.id,
                        text: e.string.string(format: variant.stringFormat),
                        poolOrder: ranksAreEntryOrder ? nil : e.poolOrder,
                        raw: nil
                    )
                },
                detachedStrings: detachedStrings.isEmpty ? nil : detachedStrings.map { d in
                    DTO.DetachedStringDTO(
                        poolOrder: d.poolOrder,
                        text: d.string.string(format: variant.stringFormat)
                    )
                },
                trailingBytes: trailingBytes.isEmpty ? nil : MSGFile.hexFromBytes(trailingBytes)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data: Data = try encoder.encode(dto)
            return [FileData(file: jsonFilename, data: GoDData(data: data, byteOrder: .big))]
        }
    }

    // MARK: - JSON DTO

    private struct DTO: Codable {
        let variant: Variant
        let reservedPrefix: String   // hex
        let region: String           // ASCII if printable, else hex
        let reservedSuffix: String   // hex
        let entries: [EntryDTO]
        /// Absent when the pool runs in entry order, which is the common case.
        let detachedStrings: [DetachedStringDTO]?
        /// Hex. Absent for a `.msg` file; a table embedded in a DOL or REL
        /// carries its container's alignment padding here.
        let trailingBytes: String?

        struct EntryDTO: Codable {
            let id: UInt32
            /// The editable text. Absent only when the string's bytes don't
            /// survive being rendered and read back, in which case `raw`
            /// carries them instead.
            let text: String?
            /// Absent when the pool runs in entry order.
            let poolOrder: Int?
            /// Hex. Exactly one of `text` and `raw` is present.
            let raw: String?
        }

        struct DetachedStringDTO: Codable {
            let poolOrder: Int
            let text: String
        }
    }

    // MARK: - Helpers

    private static func hexFromBytes(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }

    private static func bytesFromHex(_ hex: String) -> [UInt8]? {
        let clean = hex.trimmingCharacters(in: .whitespaces)
        guard clean.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard let byte = UInt8(clean[idx..<next], radix: 16) else { return nil }
            out.append(byte)
            idx = next
        }
        return out
    }

    /// If `bytes` are two ASCII printables, render as a 2-char string;
    /// otherwise fall back to hex so the roundtrip is lossless.
    private static func regionFromBytes(_ bytes: [UInt8]) -> String {
        if bytes.count == 2, bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) {
            return String(decoding: bytes, as: UTF8.self)
        }
        return hexFromBytes(bytes)
    }

    private static func bytesFromRegion(_ region: String) -> [UInt8]? {
        if region.count == 2, region.allSatisfy({ $0.isASCII }) {
            return Array(region.utf8)
        }
        return bytesFromHex(region)
    }
}

// MARK: - Free helpers

private func prefixBytes(_ value: UInt32) -> [UInt8] {
    [
        UInt8((value >> 24) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >>  8) & 0xFF),
        UInt8( value        & 0xFF)
    ]
}

private func paddedBytes(_ bytes: [UInt8], to length: Int) -> [UInt8] {
    if bytes.count == length { return bytes }
    if bytes.count > length  { return Array(bytes.prefix(length)) }
    return bytes + [UInt8](repeating: 0, count: length - bytes.count)
}

public extension MSGFile.Variant {
    /// Parses the `variant` string an operation config carries. Anything other
    /// than a Colosseum spelling means XD, which is what the ad-hoc parser
    /// this replaces did at each call site.
    init(configValue: String) {
        switch configValue.lowercased() {
        case "colo", "colosseum": self = .colo
        default:                  self = .xd
        }
    }
}

/// Errors specific to the Colosseum/XD message format.
public enum MSGFileError: GoDError {
    /// The data is Battle Revolution's `MESG` string table. The two formats
    /// share the `.msg` extension and nothing else — see `PBRStringTable`.
    case battleRevolutionStringTable(ErrorTrace = .init())

    public var description: String {
        switch self {
        case let .battleRevolutionStringTable(trace):
            return "Error: this is a Battle Revolution string table ('MESG'), not a "
                + "Colosseum/XD message file. The two formats share an extension and "
                + "nothing else — dump it with `pbrStringsDump`.\n\(trace)"
        }
    }
}
