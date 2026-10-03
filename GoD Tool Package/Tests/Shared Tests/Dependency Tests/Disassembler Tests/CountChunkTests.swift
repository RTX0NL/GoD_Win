import XCTest
import Foundation
import GoDFoundation
import Structs
import Disassembler

/// The `count` chunk's declared type: how it decodes, what it accepts, and
/// the codec that reads and writes a count at that width.
final class CountChunkTests: XCTestCase {

    private func decode(_ json: String) throws -> TypeMap {
        try JSONDecoder().decode(TypeMap.self, from: Data(json.utf8))
    }

    func testTypeDefaultsToUInt32() throws {
        let map = try decode(#"{"chunks": [{"count": {"label": "n", "table": "t"}}]}"#)
        XCTAssertEqual(map.chunks, [.count(.init(label: "n", table: "t", type: .uint32))])
    }

    func testTypeIsDecodedAndRoundTrips() throws {
        let map = try decode(#"{"chunks": [{"count": {"label": "n", "table": "t", "type": "uint8"}}]}"#)
        XCTAssertEqual(map.chunks, [.count(.init(label: "n", table: "t", type: .uint8))])
        let encoded: Data = try JSONEncoder().encode(map)
        let again = try JSONDecoder().decode(TypeMap.self, from: encoded)
        XCTAssertEqual(again, map)
    }

    /// A count is an integer. The type is decoded as one, so a float or a
    /// struct name is rejected where the map is read.
    func testANonIntegerTypeIsRejected() {
        for type in ["float", "double", "Pokemon", "bool"] {
            XCTAssertThrowsError(
                try decode(#"{"chunks": [{"count": {"label": "n", "table": "t", "type": "\#(type)"}}]}"#), type
            )
        }
    }

    func testValidateNeedsTheCountedSymbolToBeADeclaredTable() throws {
        XCTAssertNoThrow(try decode(#"""
        {"chunks": [{"table": {"name": "t", "start": "t", "entryType": "E"}},
                    {"count": {"label": "n", "table": "t", "type": "uint16"}}]}
        """#).validate())
        XCTAssertThrowsError(try decode(#"{"chunks": [{"count": {"label": "n", "table": "t"}}]}"#).validate())
        XCTAssertThrowsError(try decode(#"""
        {"chunks": [{"file": {"label": "t", "extension": "msg"}}, {"count": {"label": "n", "table": "t"}}]}
        """#).validate())
    }

    func testCodecWritesBigEndianAtTheDeclaredWidth() {
        XCTAssertEqual(IntegerProperties.uint8.countBytes(7), [7])
        XCTAssertEqual(IntegerProperties.uint16.countBytes(0x1234), [0x12, 0x34])
        XCTAssertEqual(IntegerProperties.uint24.countBytes(0x010203), [1, 2, 3])
        XCTAssertEqual(IntegerProperties.uint32.countBytes(300), [0, 0, 1, 0x2C])
        XCTAssertEqual(IntegerProperties.int64.countBytes(1), [0, 0, 0, 0, 0, 0, 0, 1])
    }

    /// Truncating a count would report the wrong table length, so a count
    /// that doesn't fit is refused instead.
    func testCodecRefusesACountTheTypeCantHold() {
        XCTAssertNil(IntegerProperties.uint8.countBytes(256))
        XCTAssertNil(IntegerProperties.int8.countBytes(128))
        XCTAssertEqual(IntegerProperties.int8.countBytes(127), [0x7F])
        XCTAssertNil(IntegerProperties.uint16.countBytes(-1))
    }

    func testCodecReadsSignExtended() {
        XCTAssertEqual(IntegerProperties.uint16.countValue(of: [0xFF, 0xFE]), 65534)
        XCTAssertEqual(IntegerProperties.int16.countValue(of: [0xFF, 0xFE]), -2)
        XCTAssertEqual(IntegerProperties.int8.countValue(of: [0x05]), 5)
        XCTAssertEqual(IntegerProperties.uint32.countValue(of: [0, 0, 1, 0x2C]), 300)
    }
}
