import XCTest
import Foundation
import GoDFoundation
import GeniusSonority

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
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/pda_menu/pda_menu.msg"
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
}
