import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import TestSupport

/// MSG-specific behavior beyond the protocol members (which are covered
/// in FileFormatProtocolTests): inline control-code parsing, real-sample
/// parse assertions, reservedPrefix/suffix preservation.
final class MSGTests: XCTestCase {

    /// A string with `{Field Player}`, `{Color: #RRGGBB}`, and a newline
    /// control-code all round-trip via GSString's pretty form. Parses
    /// known bytes into a specific pretty string — no full roundtrip.
    func testSpecialCharactersParseIntoPrettyForm() throws {
        var raw: [UInt8] = []
        raw += [0x00, 0x00, 0x00, 0x00]
        raw += [0x00, 0x01]
        raw += [0x55, 0x53]
        raw += [UInt8](repeating: 0, count: 8)
        raw += [0x00, 0x00, 0x00, 0x05] + [0x00, 0x00, 0x00, 0x18]
        // "A" + {Field Player} + "B" + {Color: #FF8000} + newline + \0
        raw += [0x00, 0x41,
                0xFF, 0xFF, 0x2B,
                0x00, 0x42,
                0xFF, 0xFF, 0x08, 0xFF, 0x80, 0x00, 0xFF,
                0xFF, 0xFF, 0x00,
                0x00, 0x00]
        let file = try MSGFile(binary: GoDData(byteStream: raw, byteOrder: .big), variant: .xd)
        XCTAssertEqual(file.entries.count, 1)
        XCTAssertEqual(file.entries[0].string.string(format: .gsXD),
                       "A{Field Player}B{Color: #FF8000}\n")
    }

    /// Real XD message table has 432 entries and preserves the
    /// reservedPrefix bytes that live at header offset 0x00-0x03.
    func testRealXDSample_parsesIntoExpectedCountAndHeader() throws {
        let path = SampleCorpus.xdGameFile("pda_menu/pda_menu.msg")
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("pda_menu.msg not available")
        }
        let file = try MSGFile(binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big),
                               variant: .xd)
        XCTAssertEqual(file.entries.count, 432)
        XCTAssertEqual(file.region, [0x55, 0x53])
        XCTAssertEqual(file.reservedPrefix, [0, 0, 0, 1],
                       "pda_menu.msg's reservedPrefix is 0x00000001")
    }

    /// Per-variant pretty-printing diverges for Colo-only codes. `0x2C`
    /// becomes `{Rui}` under Colo, raw `{2C}` under XD.
    func testVariantControlsControlCodeRendering() throws {
        var raw: [UInt8] = []
        raw += [0x00, 0x00, 0x00, 0x00]
        raw += [0x00, 0x01]
        raw += [0x55, 0x53]
        raw += [UInt8](repeating: 0, count: 8)
        raw += [0x00, 0x00, 0x00, 0x01] + [0x00, 0x00, 0x00, 0x18]
        raw += [0xFF, 0xFF, 0x2C, 0x00, 0x00]

        let xd   = try MSGFile(binary: GoDData(byteStream: raw, byteOrder: .big), variant: .xd)
        let colo = try MSGFile(binary: GoDData(byteStream: raw, byteOrder: .big), variant: .colo)

        XCTAssertEqual(colo.entries[0].string.string(format: .gsColo), "{Rui}")
        XCTAssertEqual(xd.entries[0].string.string(format: .gsXD),     "{2C}")
    }

    /// Entries are written in the order they are held, not sorted by ID.
    ///
    /// The writer used to sort. Nothing in the format calls for it — the game
    /// looks a string up by scanning for its id — and sorting silently
    /// discarded whatever order the file was parsed in or the user authored
    /// in the JSON, which is a real edit being thrown away.
    func testBinaryData_preservesEntryOrder() throws {
        let msg = MSGFile(
            variant: .xd,
            entries: [
                .init(id: 3, string: GSString(string: "C", format: .gsXD)),
                .init(id: 1, string: GSString(string: "A", format: .gsXD)),
                .init(id: 2, string: GSString(string: "B", format: .gsXD))
            ]
        )
        let bytes = try msg.binaryData.rawBytes
        // Entry table at 0x10 × 8 bytes. First entry's ID is at bytes[0x10..<0x14].
        XCTAssertEqual(Array(bytes[0x10..<0x14]), [0x00, 0x00, 0x00, 0x03], "first = id 3")
        XCTAssertEqual(Array(bytes[0x18..<0x1C]), [0x00, 0x00, 0x00, 0x01], "second = id 1")
        XCTAssertEqual(Array(bytes[0x20..<0x24]), [0x00, 0x00, 0x00, 0x02], "third = id 2")
    }

    /// The string pool is packed with no alignment: body, null word, next
    /// string. Rounding each start up to an even address is invisible in
    /// Colosseum, where every character is two bytes, but XD's format is
    /// variable-width, and the pad byte per odd-length string was the whole
    /// of the +546 bytes the DOL-embedded XD tables gained on re-encode.
    func testBinaryData_packsStringPoolWithoutAlignment() throws {
        // A parameterless special code encodes as FF FF <id> — three bytes,
        // so the body length is odd and the old alignment would pad it.
        let odd = GSString(string: "{0D}", format: .gsXD)
        let msg = MSGFile(
            variant: .xd,
            entries: [
                .init(id: 1, string: odd),
                .init(id: 2, string: GSString(string: "A", format: .gsXD))
            ]
        )
        let bytes: [UInt8] = try msg.binaryData.rawBytes
        func offset(_ index: Int) -> Int {
            let p: Int = 0x10 + (index * 8) + 4
            var value = 0
            for byte in bytes[p..<(p + 4)] {
                value = (value << 8) | Int(byte)
            }
            return value
        }
        let bodyLength: Int = odd.rawData(byteOrder: ByteOrder.big).rawBytes.count
        XCTAssertEqual(bodyLength % 2, 1, "fixture must have an odd-length body to be meaningful")
        XCTAssertEqual(
            offset(1) - offset(0), bodyLength + 2,
            "second string must start immediately after the first's terminator"
        )
    }

    // MARK: - Pool layout

    /// The pool follows `poolOrder`, not the entry table. Half the real
    /// files lay their strings out in an order the table doesn't follow, and
    /// writing them in table order is what made 60 of Colosseum US's 131
    /// message files come back the same length and a different file.
    func testBinaryData_laysThePoolOutInPoolOrder() throws {
        let msg = MSGFile(
            variant: .xd,
            entries: [
                .init(id: 1, string: GSString(string: "AAAA", format: .gsXD), poolOrder: 2),
                .init(id: 2, string: GSString(string: "BB", format: .gsXD), poolOrder: 0),
                .init(id: 3, string: GSString(string: "CCC", format: .gsXD), poolOrder: 1)
            ]
        )
        let bytes: [UInt8] = try msg.binaryData.rawBytes
        func offset(_ index: Int) -> Int {
            let start = 0x10 + index * 8 + 4
            return bytes[start..<(start + 4)].reduce(0) { ($0 << 8) | Int($1) }
        }
        XCTAssertLessThan(offset(1), offset(2), "rank 0 before rank 1")
        XCTAssertLessThan(offset(2), offset(0), "rank 1 before rank 2")
        XCTAssertEqual(offset(1), 0x10 + 3 * 8, "the first-ranked string starts the pool")
    }

    /// A string the user added carries no rank, so it goes after everything
    /// that has one rather than displacing the layout.
    func testBinaryData_placesUnrankedStringsLast() throws {
        let msg = MSGFile(
            variant: .xd,
            entries: [
                .init(id: 1, string: GSString(string: "new", format: .gsXD)),
                .init(id: 2, string: GSString(string: "old", format: .gsXD), poolOrder: 0)
            ]
        )
        let bytes: [UInt8] = try msg.binaryData.rawBytes
        func offset(_ index: Int) -> Int {
            let start = 0x10 + index * 8 + 4
            return bytes[start..<(start + 4)].reduce(0) { ($0 << 8) | Int($1) }
        }
        XCTAssertLessThan(offset(1), offset(0), "the ranked string comes first")
    }

    /// A pool string no entry points at survives. XD JP's `M6_tower_1F.msg`
    /// declares one entry and carries 450 bytes of these ahead of it;
    /// dropping them would move every offset after them.
    func testUnreferencedPoolStringsSurviveTheRoundTrip() throws {
        let original = MSGFile(
            variant: .xd,
            entries: [.init(id: 7, string: GSString(string: "kept", format: .gsXD), poolOrder: 1)],
            detachedStrings: [.init(poolOrder: 0, string: GSString(string: "orphan", format: .gsXD))]
        )
        let bytes = try original.binaryData
        let reparsed = try MSGFile(binary: bytes, variant: .xd)
        XCTAssertEqual(reparsed.entries.count, 1)
        XCTAssertEqual(reparsed.detachedStrings.count, 1)
        XCTAssertEqual(reparsed.detachedStrings.first?.string.string(format: .gsXD), "orphan")
        XCTAssertEqual(try reparsed.binaryData.rawBytes, bytes.rawBytes)
    }

    /// A table embedded in a DOL or REL arrives padded out to a 4-byte
    /// boundary by its container. Dropping those bytes shrank the chunk and
    /// shifted every symbol after it; they are kept verbatim instead.
    func testTrailingContainerPaddingIsKept() throws {
        let table = MSGFile(
            variant: .xd,
            entries: [.init(id: 1, string: GSString(string: "abc", format: .gsXD))]
        )
        var padded: [UInt8] = try table.binaryData.rawBytes
        padded.append(contentsOf: [0, 0, 0])
        let parsed = try MSGFile(binary: GoDData(byteStream: padded, byteOrder: .big), variant: .xd)
        XCTAssertEqual(parsed.trailingBytes, [0, 0, 0])
        XCTAssertEqual(try parsed.binaryData.rawBytes, padded, "padding must survive the rebuild")
        XCTAssertEqual(
            try MSGFile(outputs: try parsed.outputs).binaryData.rawBytes, padded,
            "and survive the JSON artifact too"
        )
    }

    /// A control code the game truncated must not eat the string after it.
    ///
    /// Colosseum's `FFFF 09` takes a parameter byte — in 239 of its 240
    /// appearances across the three discs. The one exception ends a string
    /// in XD JP's move viewer with no parameter at all, so a parser that
    /// always reads one swallows the terminating null word, keeps going
    /// into the next string, and writes the file back 50 bytes longer with
    /// one string duplicated inside another. Reading each string bounded by
    /// the next one's start is what stops that.
    func testATruncatedControlCodeDoesNotSwallowTheNextString() throws {
        // Two strings: the first ends on a parameterless FFFF 09.
        var bytes: [UInt8] = [0, 0, 0, 0]                   // reserved prefix
        bytes += [0, 2]                                     // count
        bytes += [0x55, 0x53]                               // region "US"
        bytes += [UInt8](repeating: 0, count: 8)            // reserved suffix
        bytes += [0, 0, 0, 1, 0, 0, 0, 0x20]                // entry 1 → 0x20
        bytes += [0, 0, 0, 2, 0, 0, 0, 0x27]                // entry 2 → 0x27
        bytes += [0x30, 0x42, 0xFF, 0xFF, 0x09, 0x00, 0x00] // "あ" + truncated code
        bytes += [0x30, 0x44, 0x00, 0x00]                   // "い"

        let parsed = try MSGFile(binary: GoDData(byteStream: bytes, byteOrder: .big), variant: .colo)
        XCTAssertEqual(parsed.entries.count, 2)
        XCTAssertEqual(
            parsed.entries[0].rawBytes, [0x30, 0x42, 0xFF, 0xFF, 0x09],
            "a string the codec can't reproduce keeps its bytes"
        )
        XCTAssertEqual(
            parsed.entries[1].string.string(format: .gsColo),
            GSString(string: "\u{3044}", format: .gsColo).string(format: .gsColo),
            "the second string must survive intact"
        )
        XCTAssertEqual(try parsed.binaryData.rawBytes, bytes, "and the file must rebuild byte-for-byte")
        XCTAssertEqual(
            try MSGFile(outputs: try parsed.outputs).binaryData.rawBytes, bytes,
            "through the JSON artifact too"
        )
    }

    /// The JSON's `text` is the editable form, so it has to be one that
    /// reads back as the same bytes. Where it isn't, the entry carries
    /// `raw` instead — a text field that silently rewrites the string on
    /// the way back in would be worse than not offering one.
    func testAnUnrenderableStringIsCarriedAsRawHexInTheJSON() throws {
        let file = MSGFile(
            variant: .colo,
            entries: [.init(
                id: 9,
                string: GSString(string: "", format: .gsColo),
                rawBytes: [0x30, 0x42, 0xFF, 0xFF, 0x09]
            )]
        )
        let artifacts = try file.outputs
        let json = try XCTUnwrap(artifacts.first?.data.rawBytes)
        let text = String(decoding: json, as: UTF8.self)
        XCTAssertTrue(text.contains("\"raw\""), "the entry must be written as raw bytes")
        XCTAssertFalse(text.contains("\"text\""), "and must not offer a text field that isn't authoritative")
        XCTAssertEqual(
            try MSGFile(outputs: artifacts).binaryData.rawBytes,
            try file.binaryData.rawBytes
        )
    }

    /// A PBR string table must be refused, not parsed as an empty one.
    ///
    /// PBR's `MESG` keeps its string count at +0x06; this parser reads a
    /// count at +0x04, where PBR has zero. Without the magic check the parse
    /// "succeeds" with no strings, and a build from that result would write
    /// an empty file over every string on the disc.
    func testRejectsABattleRevolutionStringTable() {
        var raw: [UInt8] = Array("MESG".utf8)
        raw += [0x00, 0x00]                       // id high bits
        raw += [0x00, 0x01]                       // one string
        raw += [0x00, 0x00, 0x00, 0x01]           // table id
        raw += Array("USUK".utf8)                 // language
        raw += [0x00, 0x00, 0x00, 0x14]           // offset of the one string
        raw += [0x00, 0x41, 0xFF, 0xFF, 0xFF, 0xFF]

        XCTAssertThrowsError(
            try MSGFile(binary: GoDData(byteStream: raw, byteOrder: .big), variant: .xd)
        ) { error in
            XCTAssertTrue("\(error)".contains("Battle Revolution"), "\(error)")
        }
    }
}
