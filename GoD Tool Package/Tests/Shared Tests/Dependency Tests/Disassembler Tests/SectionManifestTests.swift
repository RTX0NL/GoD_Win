import XCTest
import Foundation
import GoDFoundation
import Disassembler
import TestSupport

/// Encode/decode tests for `DataSectionManifest` / `TextSectionManifest`
/// (the `manifest.json` each disassembled section carries) against
/// hand-authored golden fixtures, plus the `ManifestReader` filesystem
/// wiring via `InMemoryFST`.
final class SectionManifestTests: XCTestCase {

    /// The model equivalent of `manifest_data_sample.json` — one chunk of
    /// every ChunkType.
    private func expectedDataManifest() -> DataSectionManifest {
        DataSectionManifest(section: "data0", chunks: [
            .init(label: "lbl_80456200", type: .binary, file: "lbl_80456200.bin", size: 16),
            .init(label: "trainer_table", type: .table, file: "trainer_table.json",
                  structType: "Trainer", countLabel: "trainer_count"),
            .init(label: "player_start", type: .struct, file: "player_start.json",
                  structType: "Vector3"),
            .init(label: "intro_text", type: .file, file: "intro_text.msg",
                  size: 256, fileExtension: "msg"),
            .init(label: "boot_hook", type: .assembly, file: "boot_hook.s"),
        ])
    }

    private func expectedTextManifest() -> TextSectionManifest {
        TextSectionManifest(section: "text0", files: ["000_start.s", "001_main.s"])
    }

    // MARK: - Decode

    func testDataManifest_decode_recoversModel() throws {
        let json = try Fixtures.data("manifest_data_sample.json")
        let parsed = try JSONDecoder().decode(DataSectionManifest.self, from: json.data)
        XCTAssertEqual(parsed, expectedDataManifest())
    }

    func testTextManifest_decode_recoversModel() throws {
        let json = try Fixtures.data("manifest_text_sample.json")
        let parsed = try JSONDecoder().decode(TextSectionManifest.self, from: json.data)
        XCTAssertEqual(parsed, expectedTextManifest())
    }

    // MARK: - Encode

    func testDataManifest_encode_matchesGoldenJSON() throws {
        let encoded: Data = try JSONEncoder().encode(expectedDataManifest())
        let golden = try Fixtures.data("manifest_data_sample.json")
        assertJSONEqual(encoded, golden.data)
    }

    func testTextManifest_encode_matchesGoldenJSON() throws {
        let encoded: Data = try JSONEncoder().encode(expectedTextManifest())
        let golden = try Fixtures.data("manifest_text_sample.json")
        assertJSONEqual(encoded, golden.data)
    }

    // MARK: - ManifestReader (filesystem wiring)

    func testManifestReader_readsManifestJSONFromFolder() throws {
        let fs = InMemoryFST()
        let folder = Folder("/data0")
        try fs.createFolder(at: folder, overwrite: true)
        try fs.writeFile(try Fixtures.data("manifest_data_sample.json"),
                         at: folder.file("manifest.json"), overwrite: true)

        let read = ManifestReader().readDataManifest(from: folder, fileSystem: fs)
        XCTAssertEqual(read, expectedDataManifest())
    }

    func testManifestReader_missingManifestReturnsNil() {
        let fs = InMemoryFST()
        let folder = Folder("/empty")
        try? fs.createFolder(at: folder, overwrite: true)
        XCTAssertNil(ManifestReader().readDataManifest(from: folder, fileSystem: fs))
        XCTAssertNil(ManifestReader().readTextManifest(from: folder, fileSystem: fs))
    }
}
