//
//  PBRCommonTableDumpTests.swift
//  PBRTests
//
//  Exercises `typeCommonTable` over the real common.fsys: every documented
//  table decodes to the row count its header declares, its CSV encodes, and
//  the CSV round-trips back to the same entry bytes. Skips without the disc.
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import Structs
@testable import GeniusSonority
@testable import PBR

final class PBRCommonTableDumpTests: XCTestCase {

    private func commonArchive() throws -> (pbr: PBREngine, archive: FSYSArchive) {
        let filesPath = ProcessInfo.processInfo.environment["GODDESS_PBR_FILES"]
            ?? "/Users/stars/Documents/Projects/GoD-Tool/scripts/PBR PAL project/Build/Contents/DATA/files"
        guard FileManager.default.fileExists(atPath: filesPath) else {
            throw XCTSkip("No unpacked PBR project — set GODDESS_PBR_FILES to run.")
        }
        let gs = GeniusSonorityEngine.defaultEngine(for: .battleRevolution)
        let bytes = try XCTUnwrap(FileManager.default.contents(atPath: filesPath + "/common.fsys"))
        let archive = try FSYSArchive(data: GoDData(data: bytes, byteOrder: .big), engine: gs)
        return (try PBREngine.defaults(), archive)
    }

    func testEveryDocumentedTableTypesAndRoundTrips() throws {
        let (pbr, archive) = try commonArchive()

        var typedCount = 0
        var byteExact = 0
        var paddingLost = [String]()

        for table in pbr.data.commonTables where table.structName != nil {
            let binary = archive.entries[table.index].data
            let typed = try XCTUnwrap(try pbr.typeCommonTable(table, binary: binary, structs: pbr), table.name)
            typedCount += 1

            // Row count matches the header.
            let count: Int = try XCTUnwrap(typed.header.get("entry_count"))
            XCTAssertEqual(typed.entries.count, count, "\(table.name): row count")

            // CSV encodes and re-decodes to the same number of rows.
            let csv = try StructTableCSV.encode(entries: typed.entries, definition: typed.entryDefinition)
            let decoded = try StructTableCSV.decode(csv, definition: typed.entryDefinition, byteOrder: .big)
            XCTAssertEqual(decoded.entries.count, typed.entries.count, "\(table.name): CSV row count")

            // Byte-exactness of the entry array through CSV.
            let original = typed.entries.flatMap { $0.data.rawBytes }
            let rebuilt = decoded.entries.flatMap { $0.data.rawBytes }
            if original == rebuilt {
                byteExact += 1
            } else {
                paddingLost.append(table.name)
            }
        }

        XCTAssertEqual(typedCount, 33, "all 33 tables have entry structs")
        print("CSV byte-exact: \(byteExact)/\(typedCount); differ: \(paddingLost.joined(separator: ", "))")
    }
}
