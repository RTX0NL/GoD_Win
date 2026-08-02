//
//  WiiOperationTests.swift
//  GODOpsTests
//
//  Runs the real WiiOps dump/build operations against an InMemoryFST.
//  Wii's fillISO uses the passed FileSystemTree (unlike Gamecube's), so it
//  is tested fully in memory, and so is a whole decrypt → rebuild → decrypt
//  pass over a synthetic disc from WiiDiscFixtures. WiiISORoundTripTests
//  covers the format itself; this covers the operation seam — key loading,
//  engines loaded from the tree, and the exported/re-imported project files.
//

import XCTest
import Foundation
import GoDFoundation
import Dolphin
import Wii
import FixtureCatalog
@testable import GODOps

final class WiiOperationTests: XCTestCase {

    private func decryptConfig(
        isoPath: File = File("/project/game.iso"),
        wiiEngine: Folder = Folder("/project/Engines/Wii"),
        dolphinEngine: Folder = Folder("/project/Engines/Dolphin")
    ) -> WiiOps.DumpConfig {
        WiiOps.DumpConfig(operations: [
            OperationConfig(
                operation: .decryptISO(
                    isoPath: isoPath,
                    outputFolder: Folder("/project/Unpacked"),
                    overwrite: true,
                    wiiEngine: wiiEngine,
                    dolphinEngine: dolphinEngine
                ),
                enabled: .yes
            )
        ])
    }

    private func encryptConfig(
        wiiEngine: Folder = Folder("/project/Engines/Wii"),
        dolphinEngine: Folder = Folder("/project/Engines/Dolphin")
    ) -> WiiOps.BuildConfig {
        WiiOps.BuildConfig(operations: [
            OperationConfig(
                operation: .encryptISO(
                    fstPath: Folder("/project/Unpacked"),
                    isoPath: File("/project/rebuilt.iso"),
                    overwrite: true,
                    wiiEngine: wiiEngine,
                    dolphinEngine: dolphinEngine
                ),
                enabled: .yes
            )
        ])
    }

    // MARK: - Decrypt → rebuild → decrypt through the operations

    func testWiiDumpThenBuildRoundTripsASyntheticDisc() throws {
        let fst = InMemoryFST()
        let wiiEngine = try WiiEngine.defaults()
        let dolphinEngine = try DolphinEngine.defaults()
        let wiiFolder = installEngine(wiiEngine, under: Folder("/project/Engines"), in: fst)
        let dolphinFolder = installEngine(dolphinEngine, under: Folder("/project/Engines"), in: fst)
        writeText(WiiDiscFixtures.commonKeyHex, at: File("/project/key.txt"), in: fst)
        let settings = GoddessSettings(verbose: false, wiiCommonKeyFile: File("/project/key.txt"))

        let (isoData, expected) = WiiDiscFixtures.disc(dolphinEngine: dolphinEngine)
        try fst.writeFile(isoData, at: File("/project/game.iso"), overwrite: true)

        try WiiOps.dump(
            config: decryptConfig(wiiEngine: wiiFolder, dolphinEngine: dolphinFolder),
            settings: settings,
            fileSystem: fst,
            logger: SilentLogger()
        )

        let unpacked = Folder("/project/Unpacked/DATA")
        XCTAssertEqual(fst.readFile(at: unpacked.file("sys/boot.bin"))?.allData?.rawBytes, expected.boot)
        XCTAssertEqual(fst.readFile(at: unpacked.file("sys/main.dol"))?.allData?.rawBytes, expected.dol)
        XCTAssertEqual(fst.readFile(at: unpacked.file("ticket.bin"))?.allData?.rawBytes, expected.ticket)
        for (path, bytes) in expected.files {
            XCTAssertEqual(
                fst.readFile(at: File(unpacked.path + path))?.allData?.rawBytes, bytes,
                "dump should export user file \(path) into the project"
            )
        }

        try WiiOps.build(
            config: encryptConfig(wiiEngine: wiiFolder, dolphinEngine: dolphinFolder),
            settings: settings,
            fileSystem: fst,
            logger: SilentLogger()
        )

        let rebuilt = try XCTUnwrap(fst.readFile(at: File("/project/rebuilt.iso"))?.allData)
        let reparsed = try WiiISO(
            data: rebuilt,
            commonKey: WiiDiscFixtures.commonKey,
            wiiEngine: wiiEngine,
            dolphinEngine: dolphinEngine
        )
        XCTAssertEqual(reparsed.readFile(at: File("/DATA/sys/main.dol"))?.allData?.rawBytes, expected.dol)
        for (path, bytes) in expected.files {
            XCTAssertEqual(
                reparsed.readFile(at: File("/DATA" + path))?.allData?.rawBytes, bytes,
                "user file \(path) should survive the dump/build operations"
            )
        }
    }

    // MARK: - fillISO

    func testWiiBuildFillISOPadsFileInPassedFileSystem() throws {
        let fst = InMemoryFST()
        let original: [UInt8] = [1, 2, 3, 4]
        try fst.writeFile(GoDData(byteStream: original, byteOrder: .big), at: File("/project/wii.iso"), overwrite: true)

        let targetSize = 4096
        let config = WiiOps.BuildConfig(operations: [
            OperationConfig(operation: .fillISO(isoPath: File("/project/wii.iso"), size: targetSize), enabled: .yes)
        ])
        try WiiOps.build(config: config, settings: .default, fileSystem: fst, logger: SilentLogger())

        let filled = try XCTUnwrap(fst.readFile(at: File("/project/wii.iso"))?.allData)
        XCTAssertEqual(filled.length, targetSize)
        XCTAssertEqual(Array(filled.rawBytes.prefix(4)), original, "original content must be preserved at the start")
        XCTAssertTrue(filled.rawBytes.dropFirst(4).allSatisfy { $0 == 0 }, "padding must be zeros")
    }

    func testWiiBuildFillISOMissingFileThrows() {
        let config = WiiOps.BuildConfig(operations: [
            OperationConfig(operation: .fillISO(isoPath: File("/project/missing.iso"), size: 4096), enabled: .yes)
        ])
        XCTAssertThrowsError(
            try WiiOps.build(config: config, settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger())
        ) { error in
            guard case FSTErrors.fileNotFound = error else {
                return XCTFail("Expected FSTErrors.fileNotFound, got \(error)")
            }
        }
    }

    // MARK: - Common key gating

    func testWiiDumpDecryptISOWithoutCommonKeyThrows() {
        XCTAssertThrowsError(
            try WiiOps.dump(config: decryptConfig(), settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger())
        ) { error in
            guard case WiiErrors.missingCommonKey = error else {
                return XCTFail("Expected WiiErrors.missingCommonKey, got \(error)")
            }
        }
    }

    func testWiiBuildEncryptISOWithoutCommonKeyThrows() {
        XCTAssertThrowsError(
            try WiiOps.build(config: encryptConfig(), settings: .default, fileSystem: InMemoryFST(), logger: SilentLogger())
        ) { error in
            guard case WiiErrors.missingCommonKey = error else {
                return XCTFail("Expected WiiErrors.missingCommonKey, got \(error)")
            }
        }
    }

    // MARK: - Common key loading

    func testWiiDumpWithValidKeyFileGetsPastKeyLoading() throws {
        // 32 hex chars load fine; the op then fails on the missing ISO —
        // the error must be the FST one, not a key error.
        let fst = InMemoryFST()
        let wiiFolder = installEngine(try WiiEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        let dolphinFolder = installEngine(try DolphinEngine.defaults(), under: Folder("/project/Engines"), in: fst)
        writeText("00112233445566778899aabbccddeeff", at: File("/project/key.txt"), in: fst)
        let settings = GoddessSettings(verbose: false, wiiCommonKeyFile: File("/project/key.txt"))

        let config = decryptConfig(
            isoPath: File("/project/missing.iso"),
            wiiEngine: wiiFolder,
            dolphinEngine: dolphinFolder
        )
        XCTAssertThrowsError(
            try WiiOps.dump(config: config, settings: settings, fileSystem: fst, logger: SilentLogger())
        ) { error in
            XCTAssertFalse(error is WiiErrors, "key loading must succeed for a 32-hex-char key file, got \(error)")
            guard case FSTErrors.fileNotFound = error else {
                return XCTFail("Expected FSTErrors.fileNotFound for the missing ISO, got \(error)")
            }
        }
    }

    func testWiiDumpWithWrongLengthKeyFileThrowsInvalidKey() {
        let fst = InMemoryFST()
        writeText("deadbeef", at: File("/project/key.txt"), in: fst)
        let settings = GoddessSettings(verbose: false, wiiCommonKeyFile: File("/project/key.txt"))

        XCTAssertThrowsError(
            try WiiOps.dump(config: decryptConfig(), settings: settings, fileSystem: fst, logger: SilentLogger())
        ) { error in
            guard case WiiErrors.invalidCommonKey = error else {
                return XCTFail("Expected WiiErrors.invalidCommonKey, got \(error)")
            }
        }
    }

    func testWiiDumpWithMissingKeyFileThrowsKeyNotFound() {
        let settings = GoddessSettings(verbose: false, wiiCommonKeyFile: File("/project/missing-key.txt"))
        XCTAssertThrowsError(
            try WiiOps.dump(config: decryptConfig(), settings: settings, fileSystem: InMemoryFST(), logger: SilentLogger())
        ) { error in
            guard case WiiErrors.commonKeyNotFound = error else {
                return XCTFail("Expected WiiErrors.commonKeyNotFound, got \(error)")
            }
        }
    }

    func testWiiBuildEncryptISOWithNonHexKeyFileThrowsInvalidKey() {
        let fst = InMemoryFST()
        // Right length, not hex.
        writeText("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", at: File("/project/key.txt"), in: fst)
        let settings = GoddessSettings(verbose: false, wiiCommonKeyFile: File("/project/key.txt"))

        XCTAssertThrowsError(
            try WiiOps.build(config: encryptConfig(), settings: settings, fileSystem: fst, logger: SilentLogger())
        ) { error in
            guard case WiiErrors.invalidCommonKey = error else {
                return XCTFail("Expected WiiErrors.invalidCommonKey, got \(error)")
            }
        }
    }
}
