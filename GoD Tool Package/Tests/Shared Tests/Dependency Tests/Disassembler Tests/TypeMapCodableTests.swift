import XCTest
import Foundation
import GoDFoundation
import Disassembler
import TestSupport

/// Encode/decode tests for `TypeMap` — the user-authored file describing
/// typed regions in data sections — against a hand-authored golden fixture.
/// `TypeMap.Chunk` has a custom Codable (`{"table":…}` / `{"single":…}` /
/// `{"file":…}`), so the wire shape is worth pinning.
final class TypeMapCodableTests: XCTestCase {

    /// The model equivalent of `typemap_sample.json` — every chunk variant,
    /// including a table that declares its entry count and one that leaves it
    /// out, which means "as many as fit before the next label".
    private func expectedTypeMap() -> TypeMap {
        TypeMap(
            chunks: [
                .table(.init(name: "Trainers", start: "trainer_table",
                             entryType: "Trainer", count: 3)),
                .table(.init(name: "Items", start: "item_table",
                             entryType: "Item")),
                .single(.init(label: "player_start", type: "Vector3")),
                .file(.init(label: "intro_text", extension: "msg", size: 256)),
            ]
        )
    }

    /// DECODE: the golden JSON decodes to the expected model.
    func testTypeMap_decode_recoversModel() throws {
        let json = try Fixtures.data("typemap_sample.json")
        let parsed = try JSONDecoder().decode(TypeMap.self, from: json.data)
        XCTAssertEqual(parsed, expectedTypeMap())
    }

    /// ENCODE: the model encodes back to the golden JSON (semantically).
    func testTypeMap_encode_matchesGoldenJSON() throws {
        let encoded: Data = try JSONEncoder().encode(expectedTypeMap())
        let golden = try Fixtures.data("typemap_sample.json")
        assertJSONEqual(encoded, golden.data)
    }

    /// An unknown chunk key must fail decoding rather than silently drop.
    func testTypeMap_unknownChunkKind_throws() {
        let bad = #"{"chunks":[{"mystery":{"label":"x"}}]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(TypeMap.self, from: bad))
    }
}
