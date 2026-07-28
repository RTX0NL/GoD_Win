//
//  ColoXDOperationTests.swift
//  GODOpsTests
//
//  Runs the real ColoXD unpackFSYS/packFSYS operations against an InMemoryFST
//  seeded with the FixtureCatalog FSYS sample — no disk, no real ROM.
//  unpackFSYS routes extracted entries to engine-resolved folders and writes
//  only the registry JSON into the configured output folder; packFSYS rebuilds
//  the archive from that registry. A dumpATX/buildATX pair rides along using
//  the ATX fixture.
//

import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import FixtureCatalog
import TestSupport
@testable import GODOps

final class ColoXDOperationTests: XCTestCase {

    private let archiveFile = File("/project/files/fsys_sample.fsys")
    private let registryFolder = Folder("/project/Archives")
    private let registryFile = File("/project/Archives/fsys_sample.json")

    /// Engine-resolved destinations for the fixture's four entries when the
    /// archive name is "fsys_sample" (not a map/menu/battlefield FSYS):
    /// msg → misc messages, scd/dat/gtx → their standard type folders.
    /// Order matches `FSYSFixtures.entries()`.
    private let expectedExtractedPaths = [
        "/Data/Text/Messages/Misc/town_talk.msg",
        "/Assets/Scripts/battle_script.scd",
        "/Assets/Models/Characters And Objects/model_data.dat",
        "/Assets/Images/Misc/menu_texture.gtx",
    ]

    private func makeProject() -> (fst: InMemoryFST, gsFolder: Folder, gsEngine: GeniusSonorityEngine) {
        let fst = InMemoryFST()
        let gsEngine = FSYSFixtures.engine()
        let gsFolder = installEngine(gsEngine, under: Folder("/project/Engines"), in: fst)
        return (fst, gsFolder, gsEngine)
    }

    private func unpack(
        fsysFile: File,
        outputFolder: Folder,
        gsFolder: Folder,
        fst: InMemoryFST
    ) throws {
        let config = ColoXD.DumpConfig(operations: [
            OperationConfig(
                operation: .unpackFSYS(
                    fsysFile: fsysFile,
                    outputFolder: outputFolder,
                    overwrite: true,
                    geniusSonorityEngine: gsFolder
                ),
                enabled: .yes
            )
        ])
        try ColoXD.dump(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
    }

    private func pack(
        registryFile: File,
        outputFile: File,
        gsFolder: Folder,
        fst: InMemoryFST
    ) throws {
        // Registry entry paths are absolute, so the source folder is the root.
        let config = ColoXD.BuildConfig(operations: [
            OperationConfig(
                operation: .packFSYS(
                    registryFile: registryFile,
                    outputFile: outputFile,
                    sourceFolder: Folder("/"),
                    overwrite: true,
                    geniusSonorityEngine: gsFolder
                ),
                enabled: .yes
            )
        ])
        try ColoXD.build(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())
    }

    // MARK: - unpackFSYS

    func testUnpackFSYSExtractsEntriesAndWritesRegistry() throws {
        let (fst, gsFolder, gsEngine) = makeProject()
        let blob = try FSYSFixtures.model().data(groupID: FSYSFixtures.groupID, engine: gsEngine)
        try fst.writeFile(blob, at: archiveFile, overwrite: true)

        try unpack(fsysFile: archiveFile, outputFolder: registryFolder, gsFolder: gsFolder, fst: fst)

        // Every fixture entry lands at its engine-resolved path with exact bytes.
        let expected = FSYSFixtures.entries()
        for (entry, path) in zip(expected, expectedExtractedPaths) {
            let extracted = try XCTUnwrap(
                fst.readFile(at: File(path)),
                "\(entry.filename) should be extracted to \(path)"
            )
            assertBytesEqual(extracted, entry.data, entry.filename)
        }

        // The registry JSON records the group ID, archive metadata, and the
        // per-entry metadata + extraction paths pack needs.
        XCTAssertNotNil(fst.inspectFile(at: registryFile))
        let registry: FSYSRegistry = try fst.decodeJSON(from: registryFile)
        XCTAssertEqual(registry.groupID, FSYSFixtures.groupID)
        XCTAssertFalse(registry.metaData.debugFlag)
        XCTAssertEqual(registry.entries.count, expected.count)
        for ((registryEntry, fixtureEntry), path) in zip(zip(registry.entries, expected), expectedExtractedPaths) {
            XCTAssertEqual(registryEntry.file.path, path)
            XCTAssertEqual(registryEntry.metadata.name, fixtureEntry.metadata.name)
            XCTAssertEqual(registryEntry.metadata.fileType, fixtureEntry.metadata.fileType)
            XCTAssertEqual(registryEntry.metadata.identifier, fixtureEntry.metadata.identifier)
            XCTAssertEqual(registryEntry.metadata.compress, fixtureEntry.metadata.compress)
        }
    }

    func testUnpackFSYSMissingInputThrows() throws {
        let (fst, gsFolder, _) = makeProject()
        XCTAssertThrowsError(
            try unpack(
                fsysFile: File("/project/files/missing.fsys"),
                outputFolder: registryFolder,
                gsFolder: gsFolder,
                fst: fst
            )
        )
    }

    // MARK: - packFSYS

    func testPackFSYSRebuildsArchiveFromUnpackedOutput() throws {
        let (fst, gsFolder, gsEngine) = makeProject()
        let blob = try FSYSFixtures.model().data(groupID: FSYSFixtures.groupID, engine: gsEngine)
        try fst.writeFile(blob, at: archiveFile, overwrite: true)
        try unpack(fsysFile: archiveFile, outputFolder: registryFolder, gsFolder: gsFolder, fst: fst)

        let packedFile = File("/project/rebuilt/fsys_sample.fsys")
        try pack(registryFile: registryFile, outputFile: packedFile, gsFolder: gsFolder, fst: fst)

        // The packed archive parses back to the fixture model 1:1.
        let packed = try XCTUnwrap(fst.readFile(at: packedFile))
        let parsed = try FSYSArchive(data: packed, engine: gsEngine)
        let expected = FSYSFixtures.entries()
        XCTAssertEqual(parsed.groupID, FSYSFixtures.groupID)
        XCTAssertEqual(parsed.entries.count, expected.count)
        for (p, e) in zip(parsed.entries, expected) {
            XCTAssertEqual(p.metadata.name, e.metadata.name)
            XCTAssertEqual(p.metadata.fileType, e.metadata.fileType)
            XCTAssertEqual(p.metadata.identifier, e.metadata.identifier)
            XCTAssertEqual(p.metadata.compress, e.metadata.compress)
            assertBytesEqual(p.data, e.data, "\(e.metadata.name): payload")
        }

        // FSYS rebuild targets a 1:1 match — the whole archive is
        // byte-identical to the original input.
        assertBytesEqual(packed, blob, "packed archive")
    }

    func testUnpackPackUnpackRoundtripIsStable() throws {
        let (fst, gsFolder, gsEngine) = makeProject()
        let blob = try FSYSFixtures.model().data(groupID: FSYSFixtures.groupID, engine: gsEngine)
        try fst.writeFile(blob, at: archiveFile, overwrite: true)
        try unpack(fsysFile: archiveFile, outputFolder: registryFolder, gsFolder: gsFolder, fst: fst)

        let firstRegistryBytes = try XCTUnwrap(fst.readFile(at: registryFile)).rawBytes
        let firstExtractedBytes = expectedExtractedPaths.map { fst.readFile(at: File($0))?.rawBytes }

        let packedFile = File("/project/rebuilt/fsys_sample.fsys")
        try pack(registryFile: registryFile, outputFile: packedFile, gsFolder: gsFolder, fst: fst)

        // Second unpack (same archive name → same extraction targets) must
        // reproduce the first round exactly.
        let secondRegistryFolder = Folder("/project/Archives2")
        try unpack(fsysFile: packedFile, outputFolder: secondRegistryFolder, gsFolder: gsFolder, fst: fst)

        let secondRegistryBytes = try XCTUnwrap(
            fst.readFile(at: secondRegistryFolder.file("fsys_sample.json"))
        ).rawBytes
        assertBytesEqual(secondRegistryBytes, firstRegistryBytes, "registry JSON")
        for (path, first) in zip(expectedExtractedPaths, firstExtractedBytes) {
            let second = try XCTUnwrap(fst.readFile(at: File(path))).rawBytes
            assertBytesEqual(second, try XCTUnwrap(first), path)
        }
    }

    // MARK: - dumpATX / buildATX

    func testDumpATXThenBuildATXRoundtrips() throws {
        let (fst, _, _) = makeProject()
        // Canonical form (reader(writer(model))) so dump → build is a byte
        // fixed point; RGBA32 frames make the PNG roundtrip lossless.
        let model = try readerCanonicalized(ATXFixtures.model())
        let atxBytes = try XCTUnwrap(model.binaries.first).data
        let atxFile = File("/project/files/atx_sample.atx")
        try fst.writeFile(atxBytes, at: atxFile, overwrite: true)

        let dumpConfig = ColoXD.DumpConfig(operations: [
            OperationConfig(
                operation: .dumpAssets(
                    format: .texture,
                    input: .file(atxFile),
                    outputFolder: Folder("/project/ATX"),
                    overwrite: true
                ),
                enabled: .yes
            )
        ])
        try ColoXD.dump(config: dumpConfig, settings: .default, fileSystem: fst, logger: SilentLogger())

        // The op nests a per-ATX project folder: manifest + one PNG per frame.
        let projectFolder = Folder("/project/ATX/atx_sample")
        let manifest = projectFolder.file("atx_sample.atx.json")
        let manifestData = try XCTUnwrap(fst.readFile(at: manifest))
        struct ManifestPeek: Codable { let framePaths: [String]? }
        let peek = try JSONDecoder().decode(ManifestPeek.self, from: manifestData.data)
        XCTAssertEqual(peek.framePaths, ["atx_sample_frame_000.png", "atx_sample_frame_001.png"])
        for frame in peek.framePaths ?? [] {
            XCTAssertNotNil(fst.readFile(at: projectFolder.file(frame)), "Expected dumped frame \(frame)")
        }

        let rebuiltFolder = Folder("/project/rebuilt")
        let rebuiltFile = rebuiltFolder.file("atx_sample.atx")
        let buildConfig = ColoXD.BuildConfig(operations: [
            OperationConfig(
                operation: .buildAssets(
                    format: .texture,
                    input: .file(manifest),
                    outputFolder: rebuiltFolder,
                    overwrite: true
                ),
                enabled: .yes
            )
        ])
        try ColoXD.build(config: buildConfig, settings: .default, fileSystem: fst, logger: SilentLogger())

        let rebuilt = try XCTUnwrap(fst.readFile(at: rebuiltFile))
        assertBytesEqual(rebuilt, atxBytes, "rebuilt ATX")
    }
}
