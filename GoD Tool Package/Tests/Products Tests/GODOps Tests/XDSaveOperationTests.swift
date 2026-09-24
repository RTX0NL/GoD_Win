//
//  XDSaveOperationTests.swift
//  GODOpsTests
//
//  Runs the real XD save dump/build operations against an InMemoryFST
//  with synthetic slots. The dump picks the latest slot (higher save
//  counter) and dumps only that one; the build reconstructs it from
//  scratch (header region + per-section artifacts) and replaces only
//  that physical slot, leaving the other slot's original bytes to pass
//  through untouched.
//
//  The fixture gives one section that tiles its struct exactly (Config,
//  index 0 → dumps as JSON) and one that's shorter than its struct
//  (Trainer1, index 1 → dumps as .bin), so both reconstruction paths
//  are exercised. Everything outside the header + those two sections is
//  zero, matching the from-scratch rebuild (which zeroes inter-section
//  gaps), so a no-edit round-trip is byte-identical.
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import XD
import Structs
@testable import GODOps

final class XDSaveOperationTests: XCTestCase {

    private let configIndex = 0
    private let trainer1Index = 1
    // Trainer1's engine struct is 0x8EC; sizing the section shorter
    // forces the dump to emit a .bin instead of JSON.
    private let trainer1Size = 0x4F8

    private func configLength() throws -> Int {
        try XDEngine.defaults().getStruct("XDSaveConfig").length
    }

    // MARK: - Fixture

    private func writeU16BE(_ bytes: inout [UInt8], at offset: Int, _ value: Int) {
        bytes[offset]     = UInt8((value >> 8) & 0xFF)
        bytes[offset + 1] = UInt8(value & 0xFF)
    }

    /// Writes the TOC offset entry for `index`: relative offset stored
    /// as [lo u16 BE, hi u16 BE] at slot[0x40 + 4*index].
    private func writeOffset(_ bytes: inout [UInt8], index: Int, absolute: Int) {
        let rel = absolute - XDSaveSlot.subBlockBaseOffset
        let base = XDSaveSlot.offsetTableOffset + index * 4
        writeU16BE(&bytes, at: base, rel & 0xFFFF)
        writeU16BE(&bytes, at: base + 2, (rel >> 16) & 0xFFFF)
    }

    private func fillDeterministic(_ bytes: inout [UInt8], from offset: Int, count: Int, seed: UInt32) {
        var rng = seed
        for i in 0..<count {
            rng = rng &* 1664525 &+ 1013904223
            bytes[offset + i] = UInt8(truncatingIfNeeded: rng >> 24)
        }
    }

    private func makePlaintextSlot(
        counter: UInt32,
        seed: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE, 0xF0, 0x0D, 0xFA, 0xCE],
        payloadSeed: UInt32 = 0xFEEDF00D
    ) throws -> GoDData {
        var bytes = [UInt8](repeating: 0, count: XDSaveSlot.slotSize)
        let configLen = try configLength()
        let configOffset = XDSaveSlot.subBlockBaseOffset          // 0xA8
        let trainer1Offset = configOffset + configLen

        // +0x00..0x08: plaintext header (magic + reserved + counter).
        bytes[0x00] = 0x01; bytes[0x01] = 0x01; bytes[0x02] = 0x01
        bytes[0x03] = 0x00
        bytes[0x04] = UInt8((counter >> 24) & 0xFF)
        bytes[0x05] = UInt8((counter >> 16) & 0xFF)
        bytes[0x06] = UInt8((counter >> 8) & 0xFF)
        bytes[0x07] = UInt8(counter & 0xFF)

        // +0x08..0x10: cipher key seed — plaintext.
        for i in 0..<seed.count { bytes[0x08 + i] = seed[i] }

        // TOC: sizes at +0x20 (u16 BE), offsets at +0x40.
        writeU16BE(&bytes, at: XDSaveSlot.sizeTableOffset + configIndex * 2, configLen)
        writeU16BE(&bytes, at: XDSaveSlot.sizeTableOffset + trainer1Index * 2, trainer1Size)
        writeOffset(&bytes, index: configIndex, absolute: configOffset)
        writeOffset(&bytes, index: trainer1Index, absolute: trainer1Offset)

        // Section payloads. Everything else (gaps, padding) stays zero.
        fillDeterministic(&bytes, from: configOffset, count: configLen, seed: payloadSeed)
        fillDeterministic(&bytes, from: trainer1Offset, count: trainer1Size, seed: payloadSeed ^ 0x5A5A5A5A)

        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func encrypted(_ plaintext: GoDData) throws -> GoDData {
        let copy = GoDData(byteStream: plaintext.rawBytes, byteOrder: .big)
        try XDSaveCipher.encrypt(slot: copy)
        return copy
    }

    private func makeProject() -> (fst: InMemoryFST, xdEngine: Folder) {
        let fst = InMemoryFST()
        let engine = installEngine(try! XDEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        return (fst, engine)
    }

    private func runDump(
        fst: InMemoryFST,
        xdEngine: Folder,
        unpacked: Folder,
        out: Folder,
        decrypted: Bool
    ) throws {
        let config = XDSaveOps.DumpConfig(operations: [
            OperationConfig(
                operation: .dumpXDSave(
                    unpackedFolder: unpacked,
                    outputFolder: out,
                    overwrite: true,
                    decrypted: decrypted,
                    xdEngine: xdEngine
                ),
                enabled: .yes
            )
        ])
        try XDSaveOps.dump(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
    }

    private func runBuild(
        fst: InMemoryFST,
        xdEngine: Folder,
        input: Folder,
        unpacked: Folder,
        decrypted: Bool
    ) throws {
        let config = XDSaveOps.BuildConfig(operations: [
            OperationConfig(
                operation: .buildXDSave(
                    inputFolder: input,
                    unpackedFolder: unpacked,
                    overwrite: true,
                    decrypted: decrypted,
                    xdEngine: xdEngine
                ),
                enabled: .yes
            )
        ])
        try XDSaveOps.build(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
    }

    // MARK: - Dump

    func testDumpPicksLatestSlotAndWritesArtifacts() throws {
        let (fst, engineFolder) = makeProject()
        // Slot B has the higher counter → it's the latest.
        let plainA = try makePlaintextSlot(counter: 0x0000_0100)
        let plainB = try makePlaintextSlot(counter: 0x0000_0200, payloadSeed: 0x0BADF00D)
        let unpacked = Folder("/project/Unpacked")
        try fst.writeFile(try encrypted(plainA), at: unpacked.file("slot-a.bin"), overwrite: true)
        try fst.writeFile(try encrypted(plainB), at: unpacked.file("slot-b.bin"), overwrite: true)

        let out = Folder("/project/Save")
        try runDump(fst: fst, xdEngine: engineFolder, unpacked: unpacked, out: out, decrypted: false)

        let save: XDSaveOps.SaveMetadata = try fst.decodeJSON(from: out.file("save-metadata.json"))
        XCTAssertFalse(save.decrypted)
        XCTAssertEqual(save.latestSlot, "B")
        XCTAssertEqual(save.slotA.counter, 0x0000_0100)
        XCTAssertEqual(save.slotB.counter, 0x0000_0200)

        // Only one slot folder exists, and it carries the latest slot.
        let latest = out.folder(XDSaveOps.latestSlotFolderName)
        let meta: XDSaveOps.SlotMetadata = try fst.decodeJSON(from: latest.file("slot-metadata.json"))
        XCTAssertEqual(meta.physicalSlot, "B")
        XCTAssertEqual(meta.header.counter, 0x0000_0200)
        // The slot header is real save data — cipher seed, checksum tags
        // and the sub-block tables — so it is dumped as editable JSON
        // rather than base64 inside this manifest.
        XCTAssertEqual(meta.headerRegionFile, XDSaveOps.slotHeaderJSONFilename)
        XCTAssertNotNil(fst.readFile(at: latest.file(XDSaveOps.slotHeaderJSONFilename))?.allData)

        // Config (index 0) tiles its struct → JSON; Trainer1 (index 1)
        // is short → .bin.
        let config = try XCTUnwrap(meta.sections.first { $0.index == configIndex })
        XCTAssertEqual(config.json, "00-Config.json")
        XCTAssertNil(config.bin)
        XCTAssertNotNil(fst.readFile(at: latest.file("00-Config.json"))?.allData)

        let trainer1 = try XCTUnwrap(meta.sections.first { $0.index == trainer1Index })
        XCTAssertNil(trainer1.json)
        XCTAssertEqual(trainer1.bin, "01-Trainer.bin")
        XCTAssertEqual(trainer1.length, trainer1Size)
    }

    func testDumpDecryptedPassthroughSkipsCipher() throws {
        let (fst, engineFolder) = makeProject()
        let plainA = try makePlaintextSlot(counter: 9)
        let plainB = try makePlaintextSlot(counter: 4, payloadSeed: 0x0BADF00D)
        let unpacked = Folder("/project/Unpacked")
        try fst.writeFile(plainA, at: unpacked.file("slot-a.bin"), overwrite: true)
        try fst.writeFile(plainB, at: unpacked.file("slot-b.bin"), overwrite: true)

        let out = Folder("/project/Save")
        try runDump(fst: fst, xdEngine: engineFolder, unpacked: unpacked, out: out, decrypted: true)

        let save: XDSaveOps.SaveMetadata = try fst.decodeJSON(from: out.file("save-metadata.json"))
        XCTAssertTrue(save.decrypted)
        XCTAssertEqual(save.latestSlot, "A", "slot A has the higher counter")
        let latest = out.folder(XDSaveOps.latestSlotFolderName)
        let raw = try XCTUnwrap(fst.readFile(at: latest.file("raw-slot.bin"))?.allData)
        XCTAssertEqual(raw.rawBytes, plainA.rawBytes)
    }

    func testDumpMissingSlotThrows() throws {
        let (fst, engineFolder) = makeProject()
        let unpacked = Folder("/project/Unpacked")
        try fst.writeFile(try makePlaintextSlot(counter: 1), at: unpacked.file("slot-a.bin"), overwrite: true)
        // slot-b.bin intentionally absent.

        XCTAssertThrowsError(
            try runDump(fst: fst, xdEngine: engineFolder, unpacked: unpacked, out: Folder("/project/Save"), decrypted: true)
        ) { error in
            guard case XDSaveOpsErrors.missingSlot = error else {
                return XCTFail("Expected XDSaveOpsErrors.missingSlot, got \(error)")
            }
        }
    }

    /// A freshly formatted memory-card file: `01 01 01` then zeroes to the
    /// end of the first 0x2000 block, then 0xFF fill. This is what every
    /// never-saved XD card on a real memory card looks like, and it used to
    /// dump "successfully" with an empty section list — the failure only
    /// surfaced at build time, as "section 0 has no reconstructed bytes".
    private func blankCardSlot() -> GoDData {
        var bytes = [UInt8](repeating: 0, count: XDSaveCipher.slotSize)
        bytes[0] = 1; bytes[1] = 1; bytes[2] = 1
        for i in 0x2000..<bytes.count { bytes[i] = 0xFF }
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    func testDumpRejectsABlankNeverSavedCard() throws {
        let (fst, engineFolder) = makeProject()
        let unpacked = Folder("/project/Unpacked")
        // Both slots blank — the card has never been saved to.
        try fst.writeFile(blankCardSlot(), at: unpacked.file("slot-a.bin"), overwrite: true)
        try fst.writeFile(blankCardSlot(), at: unpacked.file("slot-b.bin"), overwrite: true)

        XCTAssertThrowsError(
            try runDump(fst: fst, xdEngine: engineFolder, unpacked: unpacked, out: Folder("/project/Save"), decrypted: false)
        ) { error in
            guard case XDSaveOpsErrors.noValidSlot = error else {
                return XCTFail("Expected XDSaveOpsErrors.noValidSlot, got \(error)")
            }
        }
    }

    func testDumpPrefersTheValidSlotOverAHigherCounter() throws {
        let (fst, engineFolder) = makeProject()
        let unpacked = Folder("/project/Unpacked")
        // Slot A is blank; slot B is a real save with a *lower* counter than
        // the garbage slot A decrypts to. The intact slot is the one to dump.
        try fst.writeFile(blankCardSlot(), at: unpacked.file("slot-a.bin"), overwrite: true)
        try fst.writeFile(try encrypted(try makePlaintextSlot(counter: 7)), at: unpacked.file("slot-b.bin"), overwrite: true)

        let out = Folder("/project/Save")
        try runDump(fst: fst, xdEngine: engineFolder, unpacked: unpacked, out: out, decrypted: false)

        let metadata = try XCTUnwrap(fst.readFile(at: out.file("save-metadata.json"))?.allData)
        let decoded = try JSONDecoder().decode(XDSaveOps.SaveMetadata.self, from: metadata.data)
        XCTAssertEqual(decoded.latestSlot, "B")
        XCTAssertEqual(decoded.slotA.checksumValid, false, "the blank slot must be recorded as failing its checksum")
        XCTAssertEqual(decoded.slotB.checksumValid, true)
    }

    // MARK: - Build

    func testBuildFromScratchReplacesLatestSlotOnly() throws {
        let (fst, engineFolder) = makeProject()
        let plainA = try makePlaintextSlot(counter: 0x0000_0100)
        let plainB = try makePlaintextSlot(counter: 0x0000_0200, payloadSeed: 0x0BADF00D)
        let encA = try encrypted(plainA)
        let encB = try encrypted(plainB)

        // The unpacked GCI folder holds both original encrypted slots.
        let unpacked = Folder("/project/Unpacked")
        try fst.writeFile(encA, at: unpacked.file("slot-a.bin"), overwrite: true)
        try fst.writeFile(encB, at: unpacked.file("slot-b.bin"), overwrite: true)

        let out = Folder("/project/Save")
        try runDump(fst: fst, xdEngine: engineFolder, unpacked: unpacked, out: out, decrypted: false)

        // Build writes back into the same unpacked folder.
        try runBuild(fst: fst, xdEngine: engineFolder, input: out, unpacked: unpacked, decrypted: false)

        // Slot A (non-latest) is untouched — byte-identical to the original.
        let rebuiltA = try XCTUnwrap(fst.readFile(at: unpacked.file("slot-a.bin"))?.allData)
        XCTAssertEqual(rebuiltA.rawBytes, encA.rawBytes, "non-latest slot A must pass through unchanged")

        // Slot B (latest) is a from-scratch rebuild — encrypted, and it
        // decrypts back to the original plaintext with valid checksums.
        let rebuiltB = try XCTUnwrap(fst.readFile(at: unpacked.file("slot-b.bin"))?.allData)
        let decrypted = GoDData(byteStream: rebuiltB.rawBytes, byteOrder: .big)
        XCTAssertEqual(try XDSaveCipher.decrypt(slot: decrypted), true, "rebuilt slot B checksum must validate")
        XCTAssertEqual(decrypted.rawBytes, plainB.rawBytes, "rebuilt slot B plaintext must match original")
    }

    /// The header dumps as JSON with named fields, and those fields
    /// decode back to exactly the bytes they came from — so it is both
    /// readable and lossless.
    func testSlotHeaderIsDumpedAsStructuredJSON() throws {
        let (fst, engineFolder) = makeProject()
        let plainA = try makePlaintextSlot(counter: 0x0000_0100)
        let plainB = try makePlaintextSlot(counter: 0x0000_0200, payloadSeed: 0x0BADF00D)
        let unpacked = Folder("/project/Unpacked")
        try fst.writeFile(try encrypted(plainA), at: unpacked.file("slot-a.bin"), overwrite: true)
        try fst.writeFile(try encrypted(plainB), at: unpacked.file("slot-b.bin"), overwrite: true)

        let out = Folder("/project/Save")
        try runDump(fst: fst, xdEngine: engineFolder, unpacked: unpacked, out: out, decrypted: false)

        let latest = out.folder(XDSaveOps.latestSlotFolderName)
        let json = try XCTUnwrap(
            fst.readFile(at: latest.file(XDSaveOps.slotHeaderJSONFilename))?.allData,
            "slot-header.json should exist"
        )

        // Named fields, not a blob.
        let engine = try XDEngine(from: engineFolder, in: fst)
        let definition = try XCTUnwrap(
            try? engine.getStruct(XDSaveOps.slotHeaderStructName) as StructDefinition
        )
        XCTAssertEqual(definition.length, XDSaveSlot.subBlockBaseOffset)

        // And they decode back to the original header bytes exactly.
        let decoded = try StructData(definition: definition, json: json)
        XCTAssertEqual(
            decoded.data.rawBytes,
            Array(plainB.rawBytes[0..<XDSaveSlot.subBlockBaseOffset])
        )
    }

    func testEditedConfigFieldSurvivesRebuild() throws {
        let (fst, engineFolder) = makeProject()
        // Slot A is the latest here.
        let plainA = try makePlaintextSlot(counter: 0x0000_0900)
        let plainB = try makePlaintextSlot(counter: 0x0000_0100, payloadSeed: 0x0BADF00D)
        let unpacked = Folder("/project/Unpacked")
        try fst.writeFile(try encrypted(plainA), at: unpacked.file("slot-a.bin"), overwrite: true)
        try fst.writeFile(try encrypted(plainB), at: unpacked.file("slot-b.bin"), overwrite: true)

        let out = Folder("/project/Save")
        try runDump(fst: fst, xdEngine: engineFolder, unpacked: unpacked, out: out, decrypted: false)

        // Edit the Config JSON: set gcGameIndex to a known value.
        let latest = out.folder(XDSaveOps.latestSlotFolderName)
        let configFile = latest.file("00-Config.json")
        let json = try XCTUnwrap(fst.readFile(at: configFile)?.allData)
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: json.data) as? [String: Any])
        var data = try XCTUnwrap(root["data"] as? [String: Any])
        // JSON keys are the property names exactly as declared.
        let gameIndexKey = "gcGameIndex"
        XCTAssertNotNil(data[gameIndexKey], "expected key '\(gameIndexKey)' in Config JSON; keys: \(data.keys.sorted())")
        // gcGameIndex is a GameVersion enum — edit it with a case name.
        let newGameValue = "ruby"
        data[gameIndexKey] = newGameValue
        root["data"] = data
        let edited = try JSONSerialization.data(withJSONObject: root)
        try fst.writeFile(GoDData(byteStream: [UInt8](edited), byteOrder: .big), at: configFile, overwrite: true)

        // Build, then re-dump from the rebuilt slot and confirm the edit
        // persisted through encrypt → decrypt → re-parse.
        try runBuild(fst: fst, xdEngine: engineFolder, input: out, unpacked: unpacked, decrypted: false)

        // Rebuilt latest slot must still validate.
        let rebuiltA = try XCTUnwrap(fst.readFile(at: unpacked.file("slot-a.bin"))?.allData)
        let decrypted = GoDData(byteStream: rebuiltA.rawBytes, byteOrder: .big)
        XCTAssertEqual(try XDSaveCipher.decrypt(slot: decrypted), true, "rebuilt slot checksum must validate")

        let out2 = Folder("/project/Save2")
        try runDump(fst: fst, xdEngine: engineFolder, unpacked: unpacked, out: out2, decrypted: false)
        let latest2 = out2.folder(XDSaveOps.latestSlotFolderName)
        let json2 = try XCTUnwrap(fst.readFile(at: latest2.file("00-Config.json"))?.allData)
        let root2 = try XCTUnwrap(try JSONSerialization.jsonObject(with: json2.data) as? [String: Any])
        let data2 = try XCTUnwrap(root2["data"] as? [String: Any])
        let gameIndex2 = try XCTUnwrap(data2[gameIndexKey] as? String)
        XCTAssertEqual(gameIndex2, newGameValue, "edited gcGameIndex must survive the rebuild")
    }

    func testBuildSectionSizeMismatchThrows() throws {
        let (fst, engineFolder) = makeProject()
        let plainA = try makePlaintextSlot(counter: 0x0000_0300)
        let plainB = try makePlaintextSlot(counter: 0x0000_0100, payloadSeed: 0x0BADF00D)
        let unpacked = Folder("/project/Unpacked")
        try fst.writeFile(try encrypted(plainA), at: unpacked.file("slot-a.bin"), overwrite: true)
        try fst.writeFile(try encrypted(plainB), at: unpacked.file("slot-b.bin"), overwrite: true)

        let out = Folder("/project/Save")
        try runDump(fst: fst, xdEngine: engineFolder, unpacked: unpacked, out: out, decrypted: false)

        // Corrupt the Trainer .bin to the wrong length.
        let latest = out.folder(XDSaveOps.latestSlotFolderName)
        try fst.writeFile(GoDData(byteStream: [1, 2, 3], byteOrder: .big), at: latest.file("01-Trainer.bin"), overwrite: true)

        XCTAssertThrowsError(
            try runBuild(fst: fst, xdEngine: engineFolder, input: out, unpacked: unpacked, decrypted: false)
        ) { error in
            guard case XDSaveOpsErrors.sectionSizeMismatch = error else {
                return XCTFail("Expected sectionSizeMismatch, got \(error)")
            }
        }
    }
}
