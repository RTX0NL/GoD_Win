//
//  GamecubeOperationTests.swift
//  GODOpsTests
//
//  Runs the real Gamecube dump/build operations against an InMemoryFST with a
//  synthetic ISO and validates the resulting tree contents — no disk, no real
//  ROM. fillISO is the exception: it goes through the on-disk
//  FileSystem.shared by design, so it gets a temp-directory test.
//

import XCTest
import Foundation
import GoDFoundation
import GameCube
import Dolphin
@testable import GODOps

final class GamecubeOperationTests: XCTestCase {

    private func makeProject() throws -> (fst: InMemoryFST, dolphin: Folder, gamecube: Folder, dolphinEngine: DolphinEngine, gamecubeEngine: GamecubeEngine) {
        let fst = InMemoryFST()
        let dolphinEngine = try DolphinEngine.defaults()
        let gamecubeEngine = try GamecubeEngine.defaults()
        let engines = Folder("/project/Engines")
        let dolphin = installEngine(dolphinEngine, under: engines, in: fst)
        let gamecube = installEngine(gamecubeEngine, under: engines, in: fst)
        return (fst, dolphin, gamecube, dolphinEngine, gamecubeEngine)
    }

    func testGamecubeDumpUnpacksISOIntoFST() throws {
        let (fst, dolphin, gamecube, dolphinEngine, _) = try makeProject()
        let iso = try buildMinimalGamecubeISO(dolphinEngine: dolphinEngine)
        try fst.writeFile(iso, at: File("/project/game.iso"), overwrite: true)

        let config = Gamecube.DumpConfig(operations: [
            OperationConfig(
                operation: .unpackISO(
                    isoPath: File("/project/game.iso"),
                    fstFolder: Folder("/project/Unpacked"),
                    overwrite: true,
                    dolphinEngine: dolphin,
                    gamecubeEngine: gamecube
                ),
                enabled: .yes
            )
        ])
        try Gamecube.dump(config: config, settings: .default, fileSystem: StreamedFileSystem(materializing: fst), logger: SilentLogger())

        // System files land under sys/
        for sysFile in ["boot.bin", "bi2.bin", "apploader.img", "main.dol", "fst.bin"] {
            XCTAssertNotNil(
                fst.readFile(at: File("/project/Unpacked/sys/\(sysFile)")),
                "Expected \(sysFile) in unpacked sys folder"
            )
        }

        // The user file survives with exact contents
        let testFile = try XCTUnwrap(fst.readFile(at: File("/project/Unpacked/files/test.bin"))?.allData)
        XCTAssertEqual(testFile.rawBytes, (0..<64).map { UInt8($0) })

        // boot.bin is the re-serialized boot struct, sized by the engine's
        // struct definition (rebuild-from-scratch, not a raw byte copy).
        let boot = try XCTUnwrap(fst.readFile(at: File("/project/Unpacked/sys/boot.bin"))?.allData)
        XCTAssertEqual(boot.length, dolphinEngine.bootDataStruct.length)
    }

    func testGamecubeDumpMissingISOThrows() throws {
        let (fst, dolphin, gamecube, _, _) = try makeProject()
        let config = Gamecube.DumpConfig(operations: [
            OperationConfig(
                operation: .unpackISO(
                    isoPath: File("/project/missing.iso"),
                    fstFolder: Folder("/project/Unpacked"),
                    overwrite: true,
                    dolphinEngine: dolphin,
                    gamecubeEngine: gamecube
                ),
                enabled: .yes
            )
        ])
        XCTAssertThrowsError(
            try Gamecube.dump(config: config, settings: .default, fileSystem: StreamedFileSystem(materializing: fst), logger: SilentLogger())
        )
    }

    func testGamecubeBuildRebuildsISOFromFST() throws {
        let (fst, dolphin, gamecube, dolphinEngine, gamecubeEngine) = try makeProject()
        let iso = try buildMinimalGamecubeISO(dolphinEngine: dolphinEngine)
        try fst.writeFile(iso, at: File("/project/game.iso"), overwrite: true)

        // Unpack first so the build has a real FST folder to work from.
        let dumpConfig = Gamecube.DumpConfig(operations: [
            OperationConfig(
                operation: .unpackISO(
                    isoPath: File("/project/game.iso"),
                    fstFolder: Folder("/project/Unpacked"),
                    overwrite: true,
                    dolphinEngine: dolphin,
                    gamecubeEngine: gamecube
                ),
                enabled: .yes
            )
        ])
        try Gamecube.dump(config: dumpConfig, settings: .default, fileSystem: StreamedFileSystem(materializing: fst), logger: SilentLogger())

        let buildConfig = Gamecube.BuildConfig(operations: [
            OperationConfig(
                operation: .buildISO(
                    fstPath: Folder("/project/Unpacked"),
                    isoPath: File("/project/rebuilt.iso"),
                    overwrite: true,
                    dolphinEngine: dolphin,
                    gamecubeEngine: gamecube
                ),
                enabled: .yes
            )
        ])
        try Gamecube.build(config: buildConfig, settings: .default, fileSystem: fst)

        // The rebuilt image must parse and contain the same user file.
        let rebuiltData = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.iso"))?.allData)
        let rebuilt = try GamecubeISO(data: rebuiltData, dolphinEngine: dolphinEngine, gamecubeEngine: gamecubeEngine)
        let rebuiltFile = try XCTUnwrap(rebuilt.readFile(at: File("/files/test.bin"))?.allData)
        XCTAssertEqual(rebuiltFile.rawBytes, (0..<64).map { UInt8($0) })
        XCTAssertNotNil(rebuilt.readFile(at: File("/sys/boot.bin"))?.allData)
        XCTAssertNotNil(rebuilt.readFile(at: File("/sys/main.dol"))?.allData)
    }

    func testGamecubeBuildRespectsOverwriteFlag() throws {
        let (fst, dolphin, gamecube, dolphinEngine, _) = try makeProject()
        let iso = try buildMinimalGamecubeISO(dolphinEngine: dolphinEngine)
        try fst.writeFile(iso, at: File("/project/game.iso"), overwrite: true)

        let dumpConfig = Gamecube.DumpConfig(operations: [
            OperationConfig(
                operation: .unpackISO(
                    isoPath: File("/project/game.iso"),
                    fstFolder: Folder("/project/Unpacked"),
                    overwrite: true,
                    dolphinEngine: dolphin,
                    gamecubeEngine: gamecube
                ),
                enabled: .yes
            )
        ])
        try Gamecube.dump(config: dumpConfig, settings: .default, fileSystem: StreamedFileSystem(materializing: fst), logger: SilentLogger())

        // Pre-existing output with overwrite=false must survive untouched.
        let sentinel = GoDData(byteStream: [0xDE, 0xAD], byteOrder: .big)
        try fst.writeFile(sentinel, at: File("/project/rebuilt.iso"), overwrite: true)

        let buildConfig = Gamecube.BuildConfig(operations: [
            OperationConfig(
                operation: .buildISO(
                    fstPath: Folder("/project/Unpacked"),
                    isoPath: File("/project/rebuilt.iso"),
                    overwrite: false,
                    dolphinEngine: dolphin,
                    gamecubeEngine: gamecube
                ),
                enabled: .yes
            )
        ])
        try? Gamecube.build(config: buildConfig, settings: .default, fileSystem: fst)

        let after = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.iso"))?.allData)
        XCTAssertEqual(after.rawBytes, [0xDE, 0xAD], "overwrite=false must not replace an existing ISO")
    }

    func testGamecubeBuildFillISOPadsFileOnDisk() throws {
        // fillISO intentionally uses the on-disk FileSystem.shared, so this
        // test works in a real temp directory.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("goddess-fill-iso-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let isoURL = tempDir.appendingPathComponent("small.iso")
        let originalBytes: [UInt8] = [1, 2, 3, 4]
        try Data(originalBytes).write(to: isoURL)

        let targetSize = 4096
        let config = Gamecube.BuildConfig(operations: [
            OperationConfig(
                operation: .fillISO(isoPath: File(isoURL.path), size: targetSize),
                enabled: .yes
            )
        ])
        try Gamecube.build(config: config, settings: .default, fileSystem: FileSystem.shared)

        let filled = try Data(contentsOf: isoURL)
        XCTAssertEqual(filled.count, targetSize)
        XCTAssertEqual(Array(filled.prefix(4)), originalBytes, "Original content must be preserved at the start")
        XCTAssertTrue(filled.dropFirst(4).allSatisfy { $0 == 0 }, "Padding must be zeros")
    }
}
