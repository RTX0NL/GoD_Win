//
//  GCIOperationTests.swift
//  GODOpsTests
//
//  Runs the real GCI dump/build operations against an InMemoryFST with
//  synthetic .gci files. The GCI envelope round-trips byte-identically
//  (header via the JSON manifest, body via region concatenation), so
//  the build tests assert exact byte equality with the original.
//

import XCTest
import Foundation
import GoDFoundation
import GameCube
import GeniusSonority
import Colosseum
@testable import GODOps

final class GCIOperationTests: XCTestCase {

    /// Mirrors GCIFileTests.makeXDGCIBytes — hand-laid DEntry header +
    /// deterministic LCG body, parametrised on gamecode + blockCount.
    private func makeGCIBytes(gamecode: String, blockCount: Int) -> GoDData {
        let bodyLength = blockCount * GCIFile.blockSize
        var bytes = [UInt8](repeating: 0, count: GCIFile.headerSize + bodyLength)

        let code = Array(gamecode.utf8)
        for i in 0..<min(4, code.count) { bytes[i] = code[i] }
        bytes[0x04] = 0x30; bytes[0x05] = 0x31      // makercode "01"
        bytes[0x06] = 0xFF                          // unused1
        bytes[0x07] = 0x02                          // bannerAndIconFlags
        let filename: [UInt8] = Array("pokemon_storys".utf8)
        for i in 0..<filename.count { bytes[0x08 + i] = filename[i] }
        bytes[0x28] = 0x12; bytes[0x29] = 0x34      // modtime = 0x12345678
        bytes[0x2A] = 0x56; bytes[0x2B] = 0x78
        bytes[0x2F] = 0x60                          // imageOffset
        bytes[0x31] = 0x02                          // iconFmt
        bytes[0x32] = 0x55; bytes[0x33] = 0x55      // animSpeed
        bytes[0x34] = 0x04                          // permissions
        bytes[0x37] = 0x05                          // firstBlock
        bytes[0x38] = UInt8((blockCount >> 8) & 0xFF)
        bytes[0x39] = UInt8(blockCount & 0xFF)
        bytes[0x3A] = 0xFF; bytes[0x3B] = 0xFF      // unused2
        bytes[0x3E] = 0x20                          // commentsAddr = 0x2000

        var rng: UInt32 = 0xDEADBEEF
        for i in 0..<bodyLength {
            rng = rng &* 1664525 &+ 1013904223
            bytes[GCIFile.headerSize + i] = UInt8(truncatingIfNeeded: rng >> 24)
        }
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func bodySlice(of gci: GoDData, _ range: Range<Int>) -> [UInt8] {
        let raw = gci.rawBytes
        return Array(raw[(GCIFile.headerSize + range.lowerBound)..<(GCIFile.headerSize + range.upperBound)])
    }

    private func dump(_ gci: GoDData, to outputFolder: Folder, in fst: InMemoryFST) throws {
        try fst.writeFile(gci, at: File("/project/save.gci"), overwrite: true)
        let config = GCIOps.DumpConfig(operations: [
            OperationConfig(
                operation: .dumpGCI(
                    gciFile: File("/project/save.gci"),
                    outputFolder: outputFolder,
                    overwrite: true
                ),
                enabled: .yes
            )
        ])
        try GCIOps.dump(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
    }

    private func build(from inputFolder: Folder, to gciFile: File, in fst: InMemoryFST) throws {
        let config = GCIOps.BuildConfig(operations: [
            OperationConfig(
                operation: .buildGCI(
                    inputFolder: inputFolder,
                    gciFile: gciFile,
                    overwrite: true
                ),
                enabled: .yes
            )
        ])
        try GCIOps.build(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
    }

    func testDumpXDGCISplitsManifestAndRegions() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(gamecode: "GXXE", blockCount: 0x2B)  // 0x56000 body
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        let header: GCIFile.Header = try fst.decodeJSON(from: out.file("gci-manifest.json"))
        XCTAssertEqual(header.gamecode, "GXXE")
        XCTAssertEqual(header.makercode, "01")
        XCTAssertEqual(header.filename, "pokemon_storys")
        XCTAssertEqual(header.blockCount, 0x2B)

        // Region files are exact slices of the GCI body.
        let regions: [(name: String, range: Range<Int>)] = [
            ("banner.bin",  0x00000..<0x02000),
            ("header0.bin", 0x02000..<0x04000),
            ("header1.bin", 0x04000..<0x06000),
            ("slot-a.bin",  0x06000..<0x2E000),
            ("slot-b.bin",  0x2E000..<0x56000),
        ]
        for region in regions {
            let data = try XCTUnwrap(fst.readFile(at: out.file(region.name)), "Missing \(region.name)")
            XCTAssertEqual(data.rawBytes, bodySlice(of: gci, region.range), "\(region.name) content mismatch")
        }
    }

    func testBuildXDGCIRoundTripsBytes() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(gamecode: "GXXE", blockCount: 0x2B)
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)
        try build(from: out, to: File("/project/rebuilt.gci"), in: fst)

        // The manifest header round-trips via Codable and the regions
        // concatenate back to the original body, so byte-identity holds.
        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.gci")))
        XCTAssertEqual(rebuilt.rawBytes, gci.rawBytes)
    }

    func testDumpColoGCISplitsPreambleAndSlots() throws {
        let fst = InMemoryFST()
        let gci = makeGCIBytes(gamecode: "GC6E", blockCount: 0x30)  // 0x60000 body
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        let preamble = try XCTUnwrap(fst.readFile(at: out.file("preamble.bin")))
        XCTAssertEqual(preamble.rawBytes, bodySlice(of: gci, 0x00000..<0x06000))
        for i in 0..<ColoSaveCardFile.slotCount {
            let start = ColoSaveCardFile.preambleSize + i * ColoSaveCardFile.slotSize
            let slot = try XCTUnwrap(fst.readFile(at: out.file("slot-\(i + 1).bin")), "Missing slot-\(i + 1).bin")
            XCTAssertEqual(slot.rawBytes, bodySlice(of: gci, start..<(start + ColoSaveCardFile.slotSize)))
        }

        try build(from: out, to: File("/project/rebuilt.gci"), in: fst)
        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.gci")))
        XCTAssertEqual(rebuilt.rawBytes, gci.rawBytes)
    }

    func testGenericGCIDumpsUnsplitBodyAndRoundTrips() throws {
        let fst = InMemoryFST()
        // Gamecode outside the known XD/Colo shapes — body dumped unsplit.
        let gci = makeGCIBytes(gamecode: "GALE", blockCount: 2)
        let out = Folder("/project/Dump")
        try dump(gci, to: out, in: fst)

        let body = try XCTUnwrap(fst.readFile(at: out.file("body.bin")))
        XCTAssertEqual(body.rawBytes, bodySlice(of: gci, 0..<(2 * GCIFile.blockSize)))
        XCTAssertNil(fst.readFile(at: out.file("slot-a.bin")))
        XCTAssertNil(fst.readFile(at: out.file("preamble.bin")))

        try build(from: out, to: File("/project/rebuilt.gci"), in: fst)
        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.gci")))
        XCTAssertEqual(rebuilt.rawBytes, gci.rawBytes)
    }

    func testDumpMissingInputThrows() throws {
        let fst = InMemoryFST()
        let config = GCIOps.DumpConfig(operations: [
            OperationConfig(
                operation: .dumpGCI(
                    gciFile: File("/project/missing.gci"),
                    outputFolder: Folder("/project/Dump"),
                    overwrite: true
                ),
                enabled: .yes
            )
        ])
        XCTAssertThrowsError(
            try GCIOps.dump(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
        ) { error in
            guard case GCIOpsErrors.inputNotFound = error else {
                return XCTFail("Expected GCIOpsErrors.inputNotFound, got \(error)")
            }
        }
    }
}
