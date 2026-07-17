import XCTest
import Foundation
import GoDFoundation

/// `HexInt` emits a canonical `"0x..."` JSON string and is lenient on
/// decode (hex string, decimal string, or plain JSON number) so we can
/// retrofit the type onto fields whose old JSON was a bare integer.
final class HexIntTests: XCTestCase {

    private func encodedString(_ value: HexInt) throws -> String {
        // JSONEncoder wraps a single-value container in quotes, so
        // encode inside a one-field struct to see the shape that ends
        // up in real output.
        struct Wrap: Encodable { let v: HexInt }
        let encoder = JSONEncoder()
        let data: Data = try encoder.encode(Wrap(v: value))
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func decode(_ json: String) throws -> HexInt {
        struct Wrap: Decodable { let v: HexInt }
        let data = Data(json.utf8)
        return try JSONDecoder().decode(Wrap.self, from: data).v
    }

    // MARK: - Encode

    func testHexInt_encodesSmallValueAsHexString() throws {
        XCTAssertEqual(try encodedString(0x2A), #"{"v":"0x2a"}"#)
    }

    func testHexInt_encodesLargeAddressAsHexString() throws {
        XCTAssertEqual(try encodedString(0x80479FC8), #"{"v":"0x80479fc8"}"#)
    }

    func testHexInt_encodesZeroAsLiteralZero() throws {
        XCTAssertEqual(try encodedString(0), #"{"v":"0x0"}"#)
    }

    func testHexInt_encodesNegativeWithLeadingMinus() throws {
        XCTAssertEqual(try encodedString(-16), #"{"v":"-0x10"}"#)
    }

    // MARK: - Decode

    func testHexInt_decodesHexString() throws {
        XCTAssertEqual(try decode(#"{"v":"0x80479fc8"}"#).value, 0x80479FC8)
    }

    func testHexInt_decodesUppercaseHex() throws {
        XCTAssertEqual(try decode(#"{"v":"0X80479FC8"}"#).value, 0x80479FC8)
    }

    func testHexInt_decodesDecimalString() throws {
        XCTAssertEqual(try decode(#"{"v":"42"}"#).value, 42)
    }

    func testHexInt_decodesPlainNumber() throws {
        XCTAssertEqual(try decode(#"{"v":2147483647}"#).value, 2147483647)
    }

    func testHexInt_stripsUnderscoresAndWhitespace() throws {
        XCTAssertEqual(try decode(#"{"v":"0x8047_9FC8"}"#).value, 0x80479FC8)
        XCTAssertEqual(try decode(#"{"v":"  0x2A  "}"#).value, 0x2A)
    }

    func testHexInt_rejectsGarbage() {
        XCTAssertThrowsError(try decode(#"{"v":"not a number"}"#))
        XCTAssertThrowsError(try decode(#"{"v":"0xZZ"}"#))
    }

    // MARK: - Roundtrip

    func testHexInt_roundtripsThroughJSON() throws {
        let original = HexInt(0x1234_ABCD)
        let encoded = try encodedString(original)
        let decoded = try decode(encoded)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Convenience

    func testHexInt_integerLiteralAndEquality() {
        let a: HexInt = 0x40
        XCTAssertEqual(a, HexInt(64))
        XCTAssertTrue(a == 64)
        XCTAssertTrue(64 == a)
    }

    func testHexInt_widthConversions() {
        let x = HexInt(0xFFFF_FFFF)
        XCTAssertEqual(x.uint32, 0xFFFF_FFFF)
        XCTAssertEqual(x.uint16, 0xFFFF)
        XCTAssertEqual(x.uint8,  0xFF)
    }
}
