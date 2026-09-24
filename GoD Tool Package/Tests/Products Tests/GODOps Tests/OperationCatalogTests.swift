//
//  OperationCatalogTests.swift
//  GODOpsTests
//
//  The MCP server describes operations from the embedded Configuration
//  Reference. These keep that embedding honest: the copy matches the file,
//  every operation is documented in the form the catalog reads, every name
//  is a real operation, and every JSON example in the document decodes.
//

import XCTest
import Foundation
@testable import GODOps

final class OperationCatalogTests: XCTestCase {

    /// `Documentation/GODDESS Configuration Reference.md`, located from this
    /// file so the test needs no environment.
    private var referenceFile: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 5 { url.deleteLastPathComponent() }   // → repository root
        return url.appendingPathComponent("Documentation/GODDESS Configuration Reference.md")
    }

    // MARK: - Embedding

    func testEmbeddedReferenceMatchesTheDocument() throws {
        guard let onDisk = try? String(contentsOf: referenceFile, encoding: .utf8) else {
            throw XCTSkip("Configuration Reference not found at \(referenceFile.path)")
        }
        let embedded = OperationReference.markdown
        guard embedded != onDisk else { return }
        // A whole-document mismatch is unreadable; point at the first line
        // that differs.
        let embeddedLines = embedded.components(separatedBy: "\n")
        let diskLines = onDisk.components(separatedBy: "\n")
        let firstDifference = zip(embeddedLines, diskLines).enumerated()
            .first { $0.element.0 != $0.element.1 }
            .map { "line \($0.offset + 1): embedded \($0.element.0.debugDescription) vs file \($0.element.1.debugDescription)" }
            ?? "same up to line \(min(embeddedLines.count, diskLines.count)); embedded has \(embeddedLines.count) lines, file \(diskLines.count)"
        XCTFail(
            "the embedded reference is stale — run scripts/gen_operation_reference.py "
            + "(\(embedded.utf8.count) vs \(onDisk.utf8.count) bytes; \(firstDifference))"
        )
    }

    // MARK: - Coverage

    func testEveryOperationHasASectionAndAMarker() {
        for name in OperationName.allCases {
            let section = OperationCatalog.section(for: name)
            XCTAssertNotNil(section, "\(name.rawValue) has no `**`\(name.rawValue)`**` marker in the operation reference")
            guard let entry = OperationCatalog.entry(for: name) else {
                XCTFail("\(name.rawValue): marker line is not `**`name`** *(shape)* — summary.`")
                continue
            }
            XCTAssertTrue(["flat", "container"].contains(entry.shape), "\(name.rawValue): shape \(entry.shape)")
            XCTAssertFalse(entry.summary.isEmpty, "\(name.rawValue): empty summary")
            XCTAssertTrue(entry.summary.hasSuffix("."), "\(name.rawValue): summary should be a sentence, got \(entry.summary)")
        }
        XCTAssertEqual(OperationCatalog.entries.count, OperationName.allCases.count)
    }

    /// Decoding `{ "<name>": { "config": {} } }` fails for every operation —
    /// the config is empty — but it fails *inside* the payload. A name that
    /// isn't a case fails before that, with the enum's "invalid number of
    /// keys" mismatch, which is what an `OperationName` with no operation
    /// behind it would produce.
    func testEveryNameIsAnOperationCase() {
        func isUnknownKey(_ error: Error) -> Bool {
            if case DecodingError.typeMismatch(let type, _) = error {
                return String(describing: type) == "Operations"
            }
            return false
        }
        // The probe itself: a made-up name must trip the enum's own check.
        XCTAssertThrowsError(try decodeOperation("{ \"notAnOperation\": { \"config\": {} } }")) { error in
            XCTAssertTrue(isUnknownKey(error), "probe: expected the enum's key mismatch, got \(error)")
        }
        for name in OperationName.allCases {
            XCTAssertThrowsError(try decodeOperation("{ \"\(name.rawValue)\": { \"config\": {} } }")) { error in
                XCTAssertFalse(isUnknownKey(error), "\(name.rawValue) is not a GoddessConfig.Operations case")
            }
        }
    }

    // MARK: - What the tools serve

    func testListingNamesEveryOperation() {
        let listing = OperationCatalog.listing
        for name in OperationName.allCases {
            XCTAssertTrue(listing.contains("- `\(name.rawValue)` *("), "listing lacks \(name.rawValue)")
        }
        XCTAssertTrue(listing.contains("describe_operation"))
    }

    func testDescriptionCarriesTheSectionAndTheConventions() throws {
        let text = try XCTUnwrap(OperationCatalog.description(of: "compress"))
        XCTAssertTrue(text.hasPrefix("### "))
        XCTAssertTrue(text.contains("**`compress`**"))
        XCTAssertTrue(text.contains("**`decompressFiles`**"), "the whole family section is served")
        XCTAssertTrue(text.contains("## JSON conventions"))
        XCTAssertNil(OperationCatalog.description(of: "notAnOperation"))
    }

    func testSummariesReadAsOneSentence() throws {
        let compress = try XCTUnwrap(OperationCatalog.entry(for: .compress))
        XCTAssertEqual(compress, .init(name: "compress", shape: "flat", summary: "compress one file."))
        let cisoBuild = try XCTUnwrap(OperationCatalog.entry(for: .cisoBuild))
        XCTAssertTrue(cisoBuild.summary.hasPrefix("compress a raw ISO into a `.ciso`"), cisoBuild.summary)
        let coloSaveBuild = try XCTUnwrap(OperationCatalog.entry(for: .coloSaveBuild))
        XCTAssertEqual(coloSaveBuild.shape, "container", "shared marker line spelled *(containers)*")
    }

    // MARK: - Examples

    /// Every complete JSON example in the reference decodes as what it
    /// claims to be: an operation object, a toggled wrapper, or a config
    /// file. Fragments with an ellipsis are skipped.
    func testReferenceExamplesDecode() throws {
        var checked = 0
        for block in jsonBlocks(in: OperationReference.markdown) {
            guard !block.contains("…"), !block.contains("...") else { continue }
            let data = Data(block.utf8)
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let keys = Set(object.keys)

            if keys == ["operation", "enabled"] {
                let wrapper = try JSONDecoder().decode(OperationConfig<GoddessConfig.Operations>.self, from: data)
                let inner = try XCTUnwrap((object["operation"] as? [String: Any])?.keys.first)
                XCTAssertEqual(wrapper.operation.name.rawValue, inner)
                checked += 1
            } else if keys.contains("operations"), keys.contains("name") {
                _ = try JSONDecoder().decode(GoddessConfig.self, from: data)
                checked += 1
            } else if keys.count == 1, let key = keys.first, let name = OperationName(rawValue: key) {
                let operation = try JSONDecoder().decode(GoddessConfig.Operations.self, from: data)
                XCTAssertEqual(operation.name, name)
                checked += 1
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 6, "expected the reference's examples to be exercised")
    }

    // MARK: - Helpers

    private func decodeOperation(_ json: String) throws -> GoddessConfig.Operations {
        try JSONDecoder().decode(GoddessConfig.Operations.self, from: Data(json.utf8))
    }

    private func jsonBlocks(in markdown: String) -> [String] {
        var blocks: [String] = []
        var current: [String]? = nil
        for line in markdown.components(separatedBy: "\n") {
            if current == nil, line.trimmingCharacters(in: .whitespaces) == "```json" {
                current = []
            } else if let open = current, line.trimmingCharacters(in: .whitespaces) == "```" {
                blocks.append(open.joined(separator: "\n"))
                current = nil
            } else {
                current?.append(line)
            }
        }
        return blocks
    }
}
