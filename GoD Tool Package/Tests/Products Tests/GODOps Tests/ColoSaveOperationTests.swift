//
//  ColoSaveOperationTests.swift
//  GODOpsTests
//
//  Runs the real Colosseum save dump/build operations against an
//  InMemoryFST with synthetic slots. The dump picks the latest slot
//  (highest save counter) and dumps only that one; the build
//  reconstructs it from scratch (header region + per-section artifacts)
//  and replaces only that physical slot, leaving the other two slots'
//  original bytes to pass through untouched.
//
//  Colo's 7 sections tile the whole slot (a trailing catch-all covers
//  the remainder). Config/Trainer1/PCBox/Daycare (indices 0,1,2,4) are
//  `.struct` sections → JSON; BattleData/StrategyMemo/Tail (3,5,6) are
//  opaque `.binary` → `.bin`, exercising both reconstruction paths.
//
//  The typed sections route through the gsColo string codec, which
//  null-terminates + zero-pads name buffers. Real saves are already
//  codec-stable, but the synthetic LCG fixture below fills name buffers
//  with random bytes, so the fixture is normalized through the structs
//  up-front (`normalizedSlot`) to model realistic data — otherwise a
//  from-scratch rebuild would legitimately differ in the post-null
//  bytes the game never preserves.
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import Structs
import Colosseum
@testable import GODOps

final class ColoSaveOperationTests: XCTestCase {

    private let expectedSections: [(index: Int, name: String, offset: Int, length: Int)] = [
        (0, "Config",       0x0008, 0x0070),
        (1, "Trainer",      0x0078, 0x0B18),
        (2, "PCBox",         0x0B90, 0x6DEC),
        (3, "PCItemsAndMail", 0x797C, 0x07F4),
        (4, "Daycare",       0x8170, 0x0140),
        (5, "StrategyMemo",  0x82B0, 0x1774),
        (6, "Tail",          0x9A24, 0x145DC),
    ]

    /// Section indices that dump as typed JSON (`.struct`). Every Colo
    /// section is now typed — including Tail (index 6), fully decomposed.
    private let typedSectionIndices: Set<Int> = [0, 1, 2, 3, 4, 5, 6]

    /// Codec-normalizes a plaintext slot the way dump→build does: each
    /// typed section is round-tripped bytes → `StructData` → JSON →
    /// `StructData` → bytes, which null-terminates + zero-pads string
    /// fields exactly as the build path does (the plain `data:` init
    /// keeps the original bytes verbatim — only the JSON re-encode
    /// applies the codec). Header/body checksums are then recomputed.
    /// Binary sections pass through untouched. Idempotent on already-
    /// clean (real) saves.
    private func normalizedSlot(_ plain: GoDData, engine: ColosseumEngine) throws -> GoDData {
        let encoder = JSONEncoder()
        func normalizeRow(_ row: GoDData, _ def: StructDefinition) throws -> [UInt8] {
            let parsed: StructData = StructData(definition: def, data: row)
            let json: Data = try encoder.encode(parsed)
            let rebuilt = try StructData(definition: def, json: GoDData(byteStream: [UInt8](json), byteOrder: .big))
            return rebuilt.data.rawBytes
        }
        var bytes = plain.rawBytes
        var cursor = engine.data.bodyBaseOffset
        for (index, spec) in engine.data.saveSections.enumerated() {
            guard let typeName = engine.data.sectionStructTypes[index],
                  let def = try? engine.getStruct(typeName) as StructDefinition else { continue }
            let perEntry = def.length
            let total = (spec.type == .table) ? perEntry * (spec.count ?? 1) : perEntry
            let offset = cursor
            cursor += total
            guard spec.type != .binary else { continue }
            var out: [UInt8] = []
            let count = (spec.type == .table) ? (spec.count ?? 0) : 1
            for i in 0..<count {
                let row = GoDData(byteStream: Array(bytes[(offset + i * perEntry)..<(offset + (i + 1) * perEntry)]), byteOrder: .big)
                out += try normalizeRow(row, def)
            }
            bytes.replaceSubrange(offset..<(offset + total), with: out)
        }
        ColoSaveCipher.setChecksums(&bytes)
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    /// Prepared plaintext slot — checksums already set, so it equals
    /// what the dump op writes to raw-slot.bin after decrypting.
    private func makePreparedSlot(counter: UInt32, seed: UInt32) -> GoDData {
        var bytes = [UInt8](repeating: 0, count: ColoSaveCipher.slotSize)

        // "GC6E" magic + save counter; header checksum at 0x0C..0x10
        // stays zero until setChecksums fills it.
        bytes[0] = 0x47; bytes[1] = 0x43; bytes[2] = 0x36; bytes[3] = 0x45
        bytes[4] = UInt8((counter >> 24) & 0xFF)
        bytes[5] = UInt8((counter >> 16) & 0xFF)
        bytes[6] = UInt8((counter >> 8) & 0xFF)
        bytes[7] = UInt8(counter & 0xFF)

        var rng: UInt32 = seed
        for i in 0x10..<bytes.count {
            rng = rng &* 1664525 &+ 1013904223
            bytes[i] = UInt8(truncatingIfNeeded: rng >> 24)
        }

        // Keep the Config section's playTimeSeconds float (slot+0x28)
        // benign — 50.0 — so its JSON sidecar holds a plain value.
        bytes[0x28] = 0x42; bytes[0x29] = 0x48; bytes[0x2A] = 0x00; bytes[0x2B] = 0x00

        ColoSaveCipher.setChecksums(&bytes)
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func makeProject() throws -> (fst: InMemoryFST, engine: Folder) {
        let fst = InMemoryFST()
        let engine = installEngine(try ColosseumEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        return (fst, engine)
    }

    /// Counters [1, 3, 2] → slot index 1 is the latest.
    private func makeSlots() -> [GoDData] {
        [
            makePreparedSlot(counter: 1, seed: 0x11111111),
            makePreparedSlot(counter: 3, seed: 0x22222222),
            makePreparedSlot(counter: 2, seed: 0x33333333),
        ]
    }
    private let latestSlotIndex = 1

    private func encrypted(_ plain: GoDData) throws -> GoDData {
        let enc = GoDData(byteStream: plain.rawBytes, byteOrder: .big)
        try ColoSaveCipher.encrypt(slot: enc)
        return enc
    }

    private func writeEncryptedSlots(_ plains: [GoDData], under unpacked: Folder, in fst: InMemoryFST) throws {
        for (i, plain) in plains.enumerated() {
            try fst.writeFile(try encrypted(plain), at: unpacked.file("slot-\(i + 1).bin"), overwrite: true)
        }
    }

    private func runDump(fst: InMemoryFST, engine: Folder, unpacked: Folder, out: Folder, decrypted: Bool) throws {
        let config = ColoSaveOps.DumpConfig(operations: [
            OperationConfig(
                operation: .dumpColosseumSave(
                    unpackedFolder: unpacked,
                    outputFolder: out,
                    overwrite: true,
                    decrypted: decrypted,
                    colosseumEngine: engine
                ),
                enabled: .yes
            )
        ])
        try ColoSaveOps.dump(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
    }

    private func runBuild(fst: InMemoryFST, engine: Folder, input: Folder, unpacked: Folder, decrypted: Bool) throws {
        let config = ColoSaveOps.BuildConfig(operations: [
            OperationConfig(
                operation: .buildColosseumSave(
                    inputFolder: input,
                    unpackedFolder: unpacked,
                    overwrite: true,
                    decrypted: decrypted,
                    colosseumEngine: engine
                ),
                enabled: .yes
            )
        ])
        try ColoSaveOps.build(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
    }

    // MARK: - Dump

    func testDumpPicksLatestSlotAndWritesArtifacts() throws {
        let (fst, engineFolder) = try makeProject()
        let plains = makeSlots()
        let unpacked = Folder("/project/Unpacked")
        try writeEncryptedSlots(plains, under: unpacked, in: fst)

        let out = Folder("/project/Save")
        try runDump(fst: fst, engine: engineFolder, unpacked: unpacked, out: out, decrypted: false)

        let save: ColoSaveOps.SaveMetadata = try fst.decodeJSON(from: out.file("save-metadata.json"))
        XCTAssertFalse(save.decrypted)
        XCTAssertEqual(save.slots.map(\.counter), [1, 3, 2])
        XCTAssertEqual(save.latestSlotIndex, latestSlotIndex)
        for summary in save.slots {
            XCTAssertEqual(summary.headerChecksumValid, true)
            XCTAssertEqual(summary.bodyChecksumValid, true)
        }

        let latest = out.folder(ColoSaveOps.latestSlotFolderName)
        let meta: ColoSaveOps.SlotMetadata = try fst.decodeJSON(from: latest.file("slot-metadata.json"))
        XCTAssertEqual(meta.physicalSlotIndex, latestSlotIndex)
        XCTAssertEqual(meta.header.magic, Array("GC6E".utf8))
        XCTAssertEqual(meta.header.counter, 3)
        XCTAssertFalse(meta.headerRegion.isEmpty)

        // Header region = the 8 header bytes of the latest slot.
        let headerData = try XCTUnwrap(Data(base64Encoded: meta.headerRegion))
        XCTAssertEqual([UInt8](headerData), Array(plains[latestSlotIndex].rawBytes[0..<0x08]))

        XCTAssertEqual(meta.sections.map(\.index), expectedSections.map(\.index))
        let plainLatest = plains[latestSlotIndex].rawBytes
        for expected in expectedSections {
            let entry = try XCTUnwrap(meta.sections.first { $0.index == expected.index })
            XCTAssertEqual(entry.offset, expected.offset)
            XCTAssertEqual(entry.length, expected.length)
            if typedSectionIndices.contains(expected.index) {
                // Typed sections dump as JSON, no `.bin`.
                let stem = String(format: "%02d-%@", expected.index, expected.name)
                XCTAssertEqual(entry.json, "\(stem).json")
                XCTAssertNil(entry.bin)
                XCTAssertNotNil(fst.readFile(at: latest.file("\(stem).json")), "\(stem).json missing")
            } else {
                // Opaque binary sections dump their raw slice.
                XCTAssertNil(entry.json)
                let binName = try XCTUnwrap(entry.bin)
                let bin = try XCTUnwrap(fst.readFile(at: latest.file(binName))?.allData)
                XCTAssertEqual(
                    bin.rawBytes,
                    Array(plainLatest[expected.offset..<(expected.offset + expected.length)]),
                    "\(binName) content mismatch"
                )
            }
        }
    }

    func testDumpDecryptedPassthroughSkipsCipher() throws {
        let (fst, engineFolder) = try makeProject()
        let plains = makeSlots()
        let unpacked = Folder("/project/Unpacked")
        for (i, plain) in plains.enumerated() {
            try fst.writeFile(plain, at: unpacked.file("slot-\(i + 1).bin"), overwrite: true)
        }

        let out = Folder("/project/Save")
        try runDump(fst: fst, engine: engineFolder, unpacked: unpacked, out: out, decrypted: true)

        let save: ColoSaveOps.SaveMetadata = try fst.decodeJSON(from: out.file("save-metadata.json"))
        XCTAssertTrue(save.decrypted)
        XCTAssertEqual(save.latestSlotIndex, latestSlotIndex)
        for summary in save.slots {
            XCTAssertNil(summary.headerChecksumValid)
            XCTAssertNil(summary.bodyChecksumValid)
        }
        let latest = out.folder(ColoSaveOps.latestSlotFolderName)
        let raw = try XCTUnwrap(fst.readFile(at: latest.file("raw-slot.bin"))?.allData)
        XCTAssertEqual(raw.rawBytes, plains[latestSlotIndex].rawBytes)
    }

    func testDumpMissingSlotThrows() throws {
        let (fst, engineFolder) = try makeProject()
        let plains = makeSlots()
        let unpacked = Folder("/project/Unpacked")
        // Write only two of the three required slots.
        try fst.writeFile(plains[0], at: unpacked.file("slot-1.bin"), overwrite: true)
        try fst.writeFile(plains[1], at: unpacked.file("slot-2.bin"), overwrite: true)

        XCTAssertThrowsError(
            try runDump(fst: fst, engine: engineFolder, unpacked: unpacked, out: Folder("/project/Save"), decrypted: true)
        ) { error in
            guard case ColoSaveOpsErrors.missingSlot = error else {
                return XCTFail("Expected ColoSaveOpsErrors.missingSlot, got \(error)")
            }
        }
    }

    // MARK: - Build

    func testBuildFromScratchReplacesLatestSlotOnly() throws {
        let (fst, engineFolder) = try makeProject()
        let plains = makeSlots()
        let encSlots = try plains.map { try encrypted($0) }

        let unpacked = Folder("/project/Unpacked")
        for (i, enc) in encSlots.enumerated() {
            try fst.writeFile(enc, at: unpacked.file("slot-\(i + 1).bin"), overwrite: true)
        }

        let out = Folder("/project/Save")
        try runDump(fst: fst, engine: engineFolder, unpacked: unpacked, out: out, decrypted: false)
        try runBuild(fst: fst, engine: engineFolder, input: out, unpacked: unpacked, decrypted: false)

        // Non-latest slots pass through byte-identically.
        for i in 0..<ColoSaveCardFile.slotCount where i != latestSlotIndex {
            let passthrough = try XCTUnwrap(fst.readFile(at: unpacked.file("slot-\(i + 1).bin"))?.allData)
            XCTAssertEqual(passthrough.rawBytes, encSlots[i].rawBytes, "non-latest slot \(i + 1) must pass through unchanged")
        }

        // Latest slot is rebuilt from scratch — encrypted, decrypts with
        // valid checksums, and matches the codec-normalized plaintext
        // (typed sections round-trip through the gsColo string codec;
        // real saves are already codec-stable, the LCG fixture isn't).
        let rebuilt = try XCTUnwrap(fst.readFile(at: unpacked.file("slot-\(latestSlotIndex + 1).bin"))?.allData)
        let decrypted = GoDData(byteStream: rebuilt.rawBytes, byteOrder: .big)
        let result = try ColoSaveCipher.decrypt(slot: decrypted)
        XCTAssertTrue(result.headerValid, "rebuilt header checksum invalid")
        XCTAssertTrue(result.bodyValid, "rebuilt body SHA-1 invalid")
        let expected = try normalizedSlot(plains[latestSlotIndex], engine: ColosseumEngine.defaults())
        XCTAssertEqual(decrypted.rawBytes, expected.rawBytes, "rebuilt plaintext must match normalized original")
    }

    func testEditedConfigFieldSurvivesRebuild() throws {
        let (fst, engineFolder) = try makeProject()
        let plains = makeSlots()
        let unpacked = Folder("/project/Unpacked")
        try writeEncryptedSlots(plains, under: unpacked, in: fst)

        let out = Folder("/project/Save")
        try runDump(fst: fst, engine: engineFolder, unpacked: unpacked, out: out, decrypted: false)

        // Edit the Config JSON: gcGameIndex (lowercased JSON key).
        let latest = out.folder(ColoSaveOps.latestSlotFolderName)
        let configFile = latest.file("00-Config.json")
        let json = try XCTUnwrap(fst.readFile(at: configFile)?.allData)
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: json.data) as? [String: Any])
        var data = try XCTUnwrap(root["data"] as? [String: Any])
        let gameIndexKey = "gcGameIndex"
        XCTAssertNotNil(data[gameIndexKey], "expected key '\(gameIndexKey)'; keys: \(data.keys.sorted())")
        // gcGameIndex is a GameVersion enum — edit it with a case name.
        let newGameValue = "ruby"
        data[gameIndexKey] = newGameValue
        root["data"] = data
        let edited = try JSONSerialization.data(withJSONObject: root)
        try fst.writeFile(GoDData(byteStream: [UInt8](edited), byteOrder: .big), at: configFile, overwrite: true)

        try runBuild(fst: fst, engine: engineFolder, input: out, unpacked: unpacked, decrypted: false)

        // Rebuilt latest slot must still validate.
        let rebuilt = try XCTUnwrap(fst.readFile(at: unpacked.file("slot-\(latestSlotIndex + 1).bin"))?.allData)
        let decrypted = GoDData(byteStream: rebuilt.rawBytes, byteOrder: .big)
        let result = try ColoSaveCipher.decrypt(slot: decrypted)
        XCTAssertTrue(result.headerValid && result.bodyValid, "rebuilt checksums must validate")

        // Re-dump and confirm the edit persisted.
        let out2 = Folder("/project/Save2")
        try runDump(fst: fst, engine: engineFolder, unpacked: unpacked, out: out2, decrypted: false)
        let latest2 = out2.folder(ColoSaveOps.latestSlotFolderName)
        let json2 = try XCTUnwrap(fst.readFile(at: latest2.file("00-Config.json"))?.allData)
        let root2 = try XCTUnwrap(try JSONSerialization.jsonObject(with: json2.data) as? [String: Any])
        let data2 = try XCTUnwrap(root2["data"] as? [String: Any])
        let gameIndex2 = try XCTUnwrap(data2[gameIndexKey] as? String)
        XCTAssertEqual(gameIndex2, newGameValue, "edited gcGameIndex must survive the rebuild")
    }

    func testBuildMissingArtifactThrows() throws {
        let (fst, engineFolder) = try makeProject()
        let plains = makeSlots()
        let unpacked = Folder("/project/Unpacked")
        try writeEncryptedSlots(plains, under: unpacked, in: fst)

        let out = Folder("/project/Save")
        try runDump(fst: fst, engine: engineFolder, unpacked: unpacked, out: out, decrypted: false)

        // Every Colo section is now typed, so a section always
        // reconstructs to its struct's fixed length (the size-mismatch
        // guard is only reachable for `.binary` sections — see the XD
        // test). Instead assert the build rejects a *missing* artifact:
        // delete a section's JSON and expect a missingArtifact throw.
        let latest = out.folder(ColoSaveOps.latestSlotFolderName)
        try fst.deleteFile(at: latest.file("00-Config.json"))

        XCTAssertThrowsError(
            try runBuild(fst: fst, engine: engineFolder, input: out, unpacked: unpacked, decrypted: false)
        ) { error in
            guard case ColoSaveOpsErrors.missingArtifact = error else {
                return XCTFail("Expected missingArtifact, got \(error)")
            }
        }
    }
}
