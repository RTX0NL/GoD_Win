import XCTest
import Foundation
import GoDFoundation
import Disassembler
import TestSupport

/// Encode/decode tests for `RelSymbolIndex` — the sidecar naming REL
/// relocation pointer indices. `SymbolEntry` has a custom Codable that
/// accepts either a bare string or an object `{name, countIndex}`.
final class RelSymbolIndexTests: XCTestCase {

    private let goldenJSON = """
    {
      "symbols" : {
        "3" : "shop_data",
        "7" : { "name" : "trainer_list", "countIndex" : 8 },
        "8" : "trainer_count"
      }
    }
    """.data(using: .utf8)!

    private func expectedIndex() -> RelSymbolIndex {
        RelSymbolIndex(symbols: [
            "3": .name("shop_data"),
            "7": .withCount(name: "trainer_list", countIndex: 8),
            "8": .name("trainer_count"),
        ])
    }

    /// DECODE: both entry shapes (bare string / object) parse.
    func testRelSymbolIndex_decode_acceptsBothEntryShapes() throws {
        let parsed = try JSONDecoder().decode(RelSymbolIndex.self, from: goldenJSON)
        XCTAssertEqual(parsed, expectedIndex())
        XCTAssertEqual(parsed.name(for: 3), "shop_data")
        XCTAssertEqual(parsed.name(for: 7), "trainer_list")
        XCTAssertEqual(parsed.countIndex(for: 7), 8)
        XCTAssertNil(parsed.countIndex(for: 3))
        XCTAssertNil(parsed.name(for: 99))
    }

    /// ENCODE: bare names re-encode as strings, linked names as objects.
    func testRelSymbolIndex_encode_matchesGoldenJSON() throws {
        let encoded: Data = try JSONEncoder().encode(expectedIndex())
        assertJSONEqual(encoded, goldenJSON)
    }

    /// `namedIndices` sorts numerically by index.
    func testRelSymbolIndex_namedIndices_sortedByIndex() throws {
        let parsed = try JSONDecoder().decode(RelSymbolIndex.self, from: goldenJSON)
        XCTAssertEqual(parsed.namedIndices.map(\.index), [3, 7, 8])
    }
}
