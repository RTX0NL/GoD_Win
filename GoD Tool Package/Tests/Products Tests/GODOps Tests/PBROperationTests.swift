//
//  PBROperationTests.swift
//  GODOpsTests
//
//  These tests used to pin the behaviour of a *placeholder* PBR dump that
//  wrote nothing and reported a failed task. The dump is real now — it
//  unpacks the disc's FSYS archives and types `common.fsys`'s data tables —
//  so they cover what it actually does instead.
//
//  The focus here is the failure policy, because it's what stopped a JP dump
//  dead: one table the engine can't type used to throw and abandon every
//  table after it, plus the operations chained behind it.
//

import XCTest
import Foundation
import GoDFoundation
import GoDEngine
import Structs
import GeniusSonority
import PBR
@testable import GODOps

final class PBROperationTests: XCTestCase {

    private func dumpConfig(
        genius: Folder = Folder("/project/Engines/GeniusSonority Engine")
    ) -> PBROps.DumpConfig {
        PBROps.DumpConfig(operations: [
            OperationConfig(
                operation: .dumpPBR(
                    fstFolder: Folder("/project/Unpacked"),
                    outputFolder: Folder("/project/Output"),
                    overwrite: true,
                    dolphinEngine: Folder("/project/Engines/Dolphin Engine"),
                    geniusSonorityEngine: genius
                ),
                enabled: .yes
            )
        ])
    }

    /// The unpack needs the Genius Sonority engine to know PBR's archive
    /// conventions, so a missing engine folder is a hard error rather than a
    /// silent no-op.
    func testPBRDumpThrowsWhenTheGeniusSonorityEngineIsMissing() {
        XCTAssertThrowsError(
            try PBROps.dump(
                config: dumpConfig(), settings: .default,
                fileSystem: InMemoryFST(), logger: SilentLogger()
            )
        )
    }

    // MARK: - common.fsys table typing

    /// Builds a minimal unpacked tree holding one `common.fsys` member whose
    /// header declares `stride`, so the typing step can be pointed at a table
    /// that either matches its struct or doesn't.
    private func makeUnpackedTree(
        tableIndex: Int,
        entryCount: Int,
        stride: Int
    ) throws -> (fst: InMemoryFST, unpacked: Folder, binary: File) {
        let fst = InMemoryFST()
        let unpacked = Folder("/project/Unpacked")
        let binary = File("/Data/Common/common_\(String(format: "%04d", tableIndex)).bin")

        // header: entry_count, entry_size, string_pool_offset, string_pool_size,
        //         entries_offset, entries_size, … (0x30 bytes total)
        let headerSize = 0x30
        var bytes = [UInt8](repeating: 0, count: headerSize + entryCount * stride)
        func put(_ value: Int, at offset: Int) {
            bytes[offset]     = UInt8((value >> 24) & 0xFF)
            bytes[offset + 1] = UInt8((value >> 16) & 0xFF)
            bytes[offset + 2] = UInt8((value >> 8) & 0xFF)
            bytes[offset + 3] = UInt8(value & 0xFF)
        }
        put(entryCount, at: 0x00)
        put(stride, at: 0x04)
        put(headerSize, at: 0x08)
        put(0, at: 0x0C)
        put(headerSize, at: 0x10)
        put(entryCount * stride, at: 0x14)
        put(bytes.count, at: 0x20)   // relocation_table_offset = end of file

        try fst.writeFile(
            GoDData(byteStream: bytes, byteOrder: .big),
            at: unpacked.file(binary.path), overwrite: true
        )

        // Registry entries are positional: the entry's index in this list is
        // the common.fsys member index the table descriptors are keyed on.
        let filler = FSYSArchive.Entry.MetaData(
            name: "pad", fileType: "bin", identifier: 0,
            compress: false, includesFullFilename: nil
        )
        var entries = (0 ..< tableIndex).map {
            FSYSRegistry.Entry(metadata: filler, file: File("/Data/Common/pad_\($0).bin"))
        }
        entries.append(FSYSRegistry.Entry(
            metadata: .init(name: "table", fileType: "bin", identifier: 0,
                            compress: false, includesFullFilename: nil),
            file: binary
        ))
        let archiveMetaData = FSYSArchive.MetaData(
            unknownFlag1: false, unknownFlag2: false, debugFlag: false,
            unknown1: 0, unknown2: 0, unknown3: 0, unknown4: 0
        )
        let registry = FSYSRegistry(groupID: 0, metaData: archiveMetaData, entries: entries)
        try fst.encodeJSON(
            registry, to: unpacked.folder("Archives").file("common.fsys.json"), overwrite: true
        )
        return (fst, unpacked, binary)
    }

    private func typeTables(
        _ fst: InMemoryFST, _ unpacked: Folder, japanese: Bool, logger: Logger
    ) throws {
        let engines = Folder("/project/Engines")
        let pbr = installEngine(try PBREngine.defaults(), under: engines, in: fst)
        let config = PBROps.DumpConfig(operations: [
            OperationConfig(
                operation: .dumpCommonTables(
                    unpackedFolder: unpacked, overwrite: true,
                    japanese: japanese, pbrEngine: pbr
                ),
                enabled: .yes
            )
        ])
        try PBROps.dump(config: config, settings: .default, fileSystem: fst, logger: logger)
    }

    /// A table whose disc stride matches its struct types into CSV + header,
    /// and the raw `.bin` is replaced.
    func testMatchingTableIsTypedIntoCSV() throws {
        // US index 19 is `Items`, stride 0x28.
        let (fst, unpacked, binary) = try makeUnpackedTree(
            tableIndex: 19, entryCount: 4, stride: 0x28
        )
        try typeTables(fst, unpacked, japanese: false, logger: SilentLogger())

        XCTAssertNotNil(
            fst.readFile(at: unpacked.file("/Data/Common/Items/Items.csv")),
            "a matching table should produce its row CSV"
        )
        XCTAssertNotNil(
            fst.readFile(at: unpacked.file("/Data/Common/Items/Items.header.json")),
            "…and its header JSON"
        )
        XCTAssertNil(
            fst.readFile(at: unpacked.file(binary.path)),
            "the raw member is replaced by the typed files"
        )
    }

    /// The case that used to abort the whole operation: the disc's own
    /// `entry_size` disagrees with the bound struct. The table must keep its
    /// raw bytes, the run must continue, and the log must say which table and
    /// why — a silent skip would look like the table simply wasn't known.
    func testMismatchedStrideDemotesToRawBinaryAndWarns() throws {
        // US index 19 is `Items` (0x28); hand it a disc that says 0x30.
        let (fst, unpacked, binary) = try makeUnpackedTree(
            tableIndex: 19, entryCount: 4, stride: 0x30
        )
        let logger = RecordingLogger()
        XCTAssertNoThrow(try typeTables(fst, unpacked, japanese: false, logger: logger))

        XCTAssertNotNil(
            fst.readFile(at: unpacked.file(binary.path)),
            "a table that can't be typed keeps its raw binary"
        )
        XCTAssertNil(
            fst.readFile(at: unpacked.file("/Data/Common/Items/Items.csv")),
            "…and writes no partial typed artifacts"
        )
        let warning = try XCTUnwrap(
            logger.warnings.first { $0.contains("Items") },
            "expected a warning naming the table; got \(logger.warnings)"
        )
        XCTAssertTrue(warning.contains("48") || warning.contains("0x30"),
                      "the warning should report the disc's stride: \(warning)")
    }

    /// A member index no descriptor claims is left alone — that's "not a
    /// known table", which is different from "known and undecodable".
    func testUnknownTableIndexIsLeftUntouched() throws {
        let (fst, unpacked, binary) = try makeUnpackedTree(
            tableIndex: 40, entryCount: 2, stride: 0x10
        )
        let logger = RecordingLogger()
        try typeTables(fst, unpacked, japanese: false, logger: logger)

        XCTAssertNotNil(fst.readFile(at: unpacked.file(binary.path)))
        XCTAssertTrue(logger.warnings.isEmpty,
                      "an unmapped index isn't a failure: \(logger.warnings)")
    }

    // MARK: - Typed-table round trip (dump → repack)

    /// The repack half of the contract: a table the dump typed into
    /// header JSON + row CSV must reassemble byte-for-byte through the FSYS
    /// pack path (`resolveArchiveEntries` → `reassembleDataTable`). The
    /// synthetic member is all-zero, so CSV's padding-drop can't mask a
    /// reconstruction bug — any divergence here is a real layout error.
    func testTypedTableReassemblesByteExactThroughPackPath() throws {
        // US index 19 is `Items`, stride 0x28 — the same table the typing
        // test above exercises, so we know the dump produces its CSV+header.
        let (fst, unpacked, binary) = try makeUnpackedTree(
            tableIndex: 19, entryCount: 4, stride: 0x28
        )
        let originalFile = try XCTUnwrap(
            fst.readFile(at: unpacked.file(binary.path)),
            "the synthetic table binary should exist before typing"
        )
        let original = try XCTUnwrap(originalFile.allData).rawBytes

        // Dump: replaces the raw member with typed files and folds a
        // `dataTable` descriptor onto its registry entry.
        let engines = Folder("/project/Engines")
        let pbr = installEngine(try PBREngine.defaults(), under: engines, in: fst)
        let dumpConfig = PBROps.DumpConfig(operations: [
            OperationConfig(
                operation: .dumpCommonTables(
                    unpackedFolder: unpacked, overwrite: true,
                    japanese: false, pbrEngine: pbr
                ),
                enabled: .yes
            )
        ])
        try PBROps.dump(config: dumpConfig, settings: .default, fileSystem: fst, logger: SilentLogger())

        // Reload the rewritten registry and find the typed member.
        let registryFile = unpacked.folder("Archives").file("common.fsys.json")
        let registry: FSYSRegistry = try fst.decodeJSON(from: registryFile)
        let typedEntry = try XCTUnwrap(
            registry.entries.first { $0.dataTable != nil },
            "the dump should have folded a dataTable onto the Items member"
        )
        let dataTable = try XCTUnwrap(typedEntry.dataTable)

        // Resolve the reconstruction structs the same way the build op does.
        let structEngine = try GenericEngine(combining: [pbr], in: fst)
        var defs = [String: StructDefinition]()
        defs[dataTable.entryStructName]  = try structEngine.getStruct(dataTable.entryStructName)
        defs[dataTable.headerStructName] = try structEngine.getStruct(dataTable.headerStructName)

        // Repack: reassemble the FSYS entry from the typed files.
        let genius = GeniusSonorityEngine.defaultEngine(for: .battleRevolution)
        let rebuilt = try genius.resolveArchiveEntries(
            registryEntry: typedEntry, sourceFolder: unpacked,
            fileSystem: fst, structDefinitions: defs
        )
        XCTAssertEqual(rebuilt.count, 1, "a typed table reassembles to a single member")
        XCTAssertEqual(
            Array(rebuilt[0].data.rawBytes), Array(original),
            "the typed table must reassemble byte-for-byte"
        )
    }
}
