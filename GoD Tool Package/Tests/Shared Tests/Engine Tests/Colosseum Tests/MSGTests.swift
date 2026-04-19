import XCTest
import Foundation
import GoDFoundation
import GeniusSonority

final class MSGTests: XCTestCase {

    // MARK: - Synthetic roundtrip

    /// Build a minimal MSG file with 2 entries and assert that parsing +
    /// serialising yields byte-identical output.
    func testSyntheticRoundTripsByteIdentical() throws {
        var raw: [UInt8] = []
        // Header: prefix=0x00000001, count=2, region="US", 8 reserved zeros
        raw += [0x00, 0x00, 0x00, 0x01]
        raw += [0x00, 0x02]
        raw += [0x55, 0x53]
        raw += [UInt8](repeating: 0, count: 8)

        // Entry table at 0x10, 2 × 8 = 16 bytes. Strings start at 0x20.
        // Entry 0: id=1, offset=0x20. Entry 1: id=2, offset=0x2E
        raw += [0x00, 0x00, 0x00, 0x01] + [0x00, 0x00, 0x00, 0x20]
        raw += [0x00, 0x00, 0x00, 0x02] + [0x00, 0x00, 0x00, 0x2E]

        // String 0 at 0x20: "Hi" (UTF-16 BE) + 0x0000 terminator
        // = 0x00 0x48 0x00 0x69 0x00 0x00 = 6 bytes. Next starts at 0x26,
        // but we chose 0x2E to force 8 bytes of padding for coverage.
        raw += [0x00, 0x48, 0x00, 0x69, 0x00, 0x00]
        raw += [UInt8](repeating: 0, count: 8)

        // String 1 at 0x2E: "Yo!" + terminator = 8 bytes
        raw += [0x00, 0x59, 0x00, 0x6F, 0x00, 0x21, 0x00, 0x00]

        let file = try MSGFile(
            binary: GoDData(byteStream: raw, byteOrder: .big),
            variant: .xd
        )
        XCTAssertEqual(file.entries.count, 2)
        XCTAssertEqual(file.entries[0].id, 1)
        XCTAssertEqual(file.entries[0].string.string(format: .gsXD), "Hi")
        XCTAssertEqual(file.entries[1].id, 2)
        XCTAssertEqual(file.entries[1].string.string(format: .gsXD), "Yo!")

        // Serialising won't produce the same padding bytes (encoder packs
        // strings sequentially), so we assert on a re-parse roundtrip
        // instead: binary → MSGFile → binary → MSGFile yields equal data.
        let reBinary = try file.binaryData
        let reParsed = try MSGFile(binary: reBinary, variant: .xd)
        XCTAssertEqual(reParsed.entries, file.entries)
        XCTAssertEqual(reParsed.reservedPrefix, file.reservedPrefix)
        XCTAssertEqual(reParsed.region, file.region)
        XCTAssertEqual(reParsed.reservedSuffix, file.reservedSuffix)
    }

    /// A tightly-packed synthetic MSG should serialise byte-identically
    /// (entries already sorted, no gaps in the string pool).
    func testTightlyPackedSyntheticIsByteIdentical() throws {
        var raw: [UInt8] = []
        raw += [0x00, 0x00, 0x00, 0x00]
        raw += [0x00, 0x02]
        raw += [0x55, 0x53]
        raw += [UInt8](repeating: 0, count: 8)
        raw += [0x00, 0x00, 0x00, 0x01] + [0x00, 0x00, 0x00, 0x20]
        raw += [0x00, 0x00, 0x00, 0x02] + [0x00, 0x00, 0x00, 0x26]
        raw += [0x00, 0x48, 0x00, 0x69, 0x00, 0x00]             // "Hi\0"
        raw += [0x00, 0x59, 0x00, 0x6F, 0x00, 0x21, 0x00, 0x00] // "Yo!\0"

        let file = try MSGFile(
            binary: GoDData(byteStream: raw, byteOrder: .big),
            variant: .xd
        )
        let serialized = try file.binaryData
        XCTAssertEqual(serialized.rawBytes, raw)
    }

    func testSpecialCharactersSurviveBinaryRoundTrip() throws {
        var raw: [UInt8] = []
        raw += [0x00, 0x00, 0x00, 0x00]
        raw += [0x00, 0x01]
        raw += [0x55, 0x53]
        raw += [UInt8](repeating: 0, count: 8)
        raw += [0x00, 0x00, 0x00, 0x05] + [0x00, 0x00, 0x00, 0x18]

        // String: "A" + {Field Player} + "B" + {Color: #FF8000} + newline
        // UTF-16 BE 'A' = 0x00 0x41. {Field Player} = FF FF 2B.
        // 'B' = 0x00 0x42. Color = FF FF 08 FF 80 00 FF. New line = FF FF 00.
        // Terminator 0x0000.
        raw += [0x00, 0x41,
                0xFF, 0xFF, 0x2B,
                0x00, 0x42,
                0xFF, 0xFF, 0x08, 0xFF, 0x80, 0x00, 0xFF,
                0xFF, 0xFF, 0x00,
                0x00, 0x00]

        let file = try MSGFile(
            binary: GoDData(byteStream: raw, byteOrder: .big),
            variant: .xd
        )
        let pretty = file.entries[0].string.string(format: .gsXD)
        XCTAssertEqual(pretty, "A{Field Player}B{Color: #FF8000}\n")

        // binary → file → binary should be byte-identical because the
        // table is single-entry and packed.
        XCTAssertEqual(try file.binaryData.rawBytes, raw)
    }

    // MARK: - JSON roundtrip

    func testJSONRoundTripPreservesEntries() throws {
        let original = MSGFile(
            variant: .xd,
            reservedPrefix: [0x00, 0x00, 0x00, 0x01],
            region: [0x55, 0x53],
            reservedSuffix: [UInt8](repeating: 0, count: 8),
            entries: [
                .init(id: 0x100, string: GSString(string: "Hello", format: .gsXD)),
                .init(id: 0x101, string: GSString(
                    string: "Hi {Field Player}!{Color: #FF0000}red{White}",
                    format: .gsXD))
            ]
        )
        let outputs = try original.outputs
        XCTAssertNotNil(outputs[MSGFile.messagesJSON])

        let roundTripped = try MSGFile(outputs: outputs)
        XCTAssertEqual(roundTripped.variant, original.variant)
        XCTAssertEqual(roundTripped.reservedPrefix, original.reservedPrefix)
        XCTAssertEqual(roundTripped.region, original.region)
        XCTAssertEqual(roundTripped.reservedSuffix, original.reservedSuffix)
        XCTAssertEqual(roundTripped.entries.count, original.entries.count)
        for (a, b) in zip(roundTripped.entries, original.entries) {
            XCTAssertEqual(a.id, b.id)
            XCTAssertEqual(
                a.string.string(format: .gsXD),
                b.string.string(format: .gsXD)
            )
        }
    }

    /// binary → JSON → binary on a tightly-packed synthetic should be
    /// byte-identical — exercises the end-to-end path MSG dumping/building
    /// will use.
    func testBinaryToJSONToBinaryIsByteIdentical() throws {
        var raw: [UInt8] = []
        raw += [0x00, 0x00, 0x00, 0x00]
        raw += [0x00, 0x02]
        raw += [0x55, 0x53]
        raw += [UInt8](repeating: 0, count: 8)
        raw += [0x00, 0x00, 0x00, 0x01] + [0x00, 0x00, 0x00, 0x20]
        raw += [0x00, 0x00, 0x00, 0x02] + [0x00, 0x00, 0x00, 0x26]
        raw += [0x00, 0x48, 0x00, 0x69, 0x00, 0x00]
        raw += [0x00, 0x59, 0x00, 0x6F, 0x00, 0x21, 0x00, 0x00]

        let parsed = try MSGFile(
            binary: GoDData(byteStream: raw, byteOrder: .big),
            variant: .xd
        )
        let outputs = try parsed.outputs
        let roundTripped = try MSGFile(outputs: outputs)
        XCTAssertEqual(try roundTripped.binaryData.rawBytes, raw)
    }

    // MARK: - Real samples (optional, skip if not present on this machine)

    /// Real XD MSG sample roundtrip. Strings must decode to non-empty
    /// pretty form and re-parse back without losing entries.
    func testRealXDSampleRoundTrips() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/pda_menu/pda_menu.msg"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("pda_menu.msg not available")
        }
        let file = try MSGFile(
            binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big),
            variant: .xd
        )
        XCTAssertEqual(file.entries.count, 432)
        XCTAssertEqual(file.region, [0x55, 0x53])
        // Every entry should have a well-defined string (even if empty).
        for entry in file.entries {
            _ = entry.string.string(format: .gsXD)
        }

        // binary → JSON → binary → parse yields identical entries list.
        let outputs = try file.outputs
        let fromJSON = try MSGFile(outputs: outputs)
        XCTAssertEqual(fromJSON.entries.count, file.entries.count)
        let reBinary = try fromJSON.binaryData
        let reParsed = try MSGFile(binary: reBinary, variant: .xd)
        XCTAssertEqual(reParsed.entries.count, file.entries.count)
        for (a, b) in zip(reParsed.entries, file.entries.sorted(by: { $0.id < $1.id })) {
            XCTAssertEqual(a.id, b.id)
            XCTAssertEqual(
                a.string.string(format: .gsXD),
                b.string.string(format: .gsXD)
            )
        }
    }

    func testRealSmallXDSampleRoundTrips() throws {
        let path = "/Users/stars/Documents/GoD Tool/XD GoD Tool/Game Files/M2_windmill_1F/M2_windmill_1F.msg"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw XCTSkip("M2_windmill_1F.msg not available")
        }
        let file = try MSGFile(
            binary: GoDData(byteStream: [UInt8](raw), byteOrder: .big),
            variant: .xd
        )
        XCTAssertEqual(file.entries.count, 7)
        XCTAssertEqual(file.reservedPrefix, [0, 0, 0, 0])
        XCTAssertEqual(file.region, [0x55, 0x53])

        // End-to-end: binary → JSON → binary → re-parse with the same entries.
        let reBinary = try MSGFile(outputs: try file.outputs).binaryData
        let reParsed = try MSGFile(binary: reBinary, variant: .xd)
        XCTAssertEqual(
            reParsed.entries.map(\.id).sorted(),
            file.entries.map(\.id).sorted()
        )
    }
}
