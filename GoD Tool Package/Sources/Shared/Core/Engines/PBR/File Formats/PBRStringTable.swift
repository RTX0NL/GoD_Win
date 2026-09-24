//
//  PBRStringTable.swift
//  PBR
//
//  Parser and serializer for Battle Revolution's `MESG` string table.
//
//  This is *not* the Genius Sonority `.msg` that Colosseum and XD use. The
//  two share an extension and nothing else: GS keys its entries by a stored
//  id in an 8-byte record, PBR stores a bare offset per string and gets the
//  id from a separate directory (`PBRStringDirectory`); GS terminates a
//  string with a null, PBR with `FFFFFFFF`; the control codes are unrelated
//  vocabularies. Nothing here is shared with `MSGFile`, deliberately.
//
//  Layout (big-endian):
//
//  ```
//  +0x00  char[4]  'MESG'
//  +0x04  u16      high bits a string id is matched against — zero on every
//                  retail table, preserved rather than assumed
//  +0x06  u16      string count
//  +0x08  u32      table id; this is what the directory addresses, so it is
//                  the table's identity and not its position on the disc
//  +0x0C  char[4]  language code, e.g. 'USUK', 'GRGR'
//  +0x10  u32 × N  absolute offset of each string
//         bodies   UTF-16BE code units and `FFFF`-prefixed control words,
//                  each terminated by `FFFFFFFF`
//  ```
//
//  The bodies tile exactly: the first starts where the offset table ends,
//  each one ends where the next begins, and the last ends at EOF. Verified
//  over all four tables of the PAL disc — 21,812 strings — which is also
//  what confirms the control words' parameter lengths, since a wrong length
//  would desynchronise the walk and land the next string off its offset.
//

import Foundation
import GoDFoundation

public struct PBRStringTable {
    public static let formatName = "mesg"
    public static let magic = "MESG"
    /// Offset table, and so the first string body, starts here.
    public static let headerSize = 0x10

    public enum Error: GoDError {
        case notAStringTable(ErrorTrace = .init())
        case truncated(ErrorTrace = .init())
        case tooManyStrings(count: Int, ErrorTrace = .init())

        public var description: String {
            switch self {
            case let .notAStringTable(trace):
                return "Error: not a PBR string table (no 'MESG' magic).\n\(trace)"
            case let .truncated(trace):
                return "Error: PBR string table ends inside its offset table.\n\(trace)"
            case let .tooManyStrings(count, trace):
                return "Error: a PBR string table holds at most 65535 strings; this one has \(count).\n\(trace)"
            }
        }
    }

    /// The table's identity, as the directory addresses it.
    public var tableID: Int
    /// The four-character language code at +0x0C.
    public var languageCode: String
    /// The `u16` at +0x04. Zero on every retail table; carried so a build
    /// writes back whatever was there rather than a guess.
    public var idHighBits: Int
    /// Strings in index order. A string's index is its position here plus
    /// one — indexes are 1-based in the directory.
    public var strings: [GSString]

    public init(tableID: Int, languageCode: String, idHighBits: Int = 0, strings: [GSString] = []) {
        self.tableID = tableID
        self.languageCode = languageCode
        self.idHighBits = idHighBits
        self.strings = strings
    }

    public init(binary: GoDReadable) throws {
        guard binary.readString(atAddress: 0x00, format: .utf8, maxCharacters: 4) == Self.magic else {
            throw Error.notAStringTable()
        }
        guard let highBits: UInt16 = binary.readValue(atAddress: 0x04),
              let count: UInt16 = binary.readValue(atAddress: 0x06),
              let tableID: UInt32 = binary.readValue(atAddress: 0x08),
              let language = binary.readString(atAddress: 0x0C, format: .utf8, maxCharacters: 4)
        else {
            throw Error.truncated()
        }

        self.idHighBits = Int(highBits)
        self.tableID = Int(tableID)
        self.languageCode = language
        self.strings = []
        self.strings.reserveCapacity(Int(count))

        for index in 0..<Int(count) {
            guard let offset: UInt32 = binary.readValue(atAddress: Self.headerSize + index * 4) else {
                throw Error.truncated()
            }
            // An empty string is a bare terminator, which reads back as no
            // characters at all — valid, and it has to stay valid or the
            // offsets after it shift.
            strings.append(binary.readGSStringSafely(atAddress: Int(offset), format: .gsPBR))
        }
    }

    /// Byte length of one string on disc: its characters plus the
    /// four-byte terminator.
    private func length(of string: GSString) -> Int {
        string.rawData(byteOrder: .big).length + 4
    }

    public func rawData() throws -> GoDData {
        guard strings.count <= 0xFFFF else {
            throw Error.tooManyStrings(count: strings.count)
        }
        let data = GoDData(byteOrder: .big)
        data.append(GoDData(string: Self.magic, format: .utf8))
        data.append(UInt16(idHighBits & 0xFFFF))
        data.append(UInt16(strings.count))
        data.append(UInt32(tableID))
        data.append(GoDData(string: languageCode, format: .utf8))

        var bodyOffset = Self.headerSize + strings.count * 4
        for string in strings {
            data.append(UInt32(bodyOffset))
            bodyOffset += length(of: string)
        }
        for string in strings {
            data.append(string.rawData(byteOrder: .big))
            data.append(UInt32(0xFFFFFFFF))
        }
        return data
    }

    /// Whether `data` opens with the `MESG` magic. Used to pick the string
    /// tables out of a folder of message binaries without parsing each one.
    public static func isStringTable(_ data: GoDReadable) -> Bool {
        data.readString(atAddress: 0x00, format: .utf8, maxCharacters: 4) == magic
    }
}
