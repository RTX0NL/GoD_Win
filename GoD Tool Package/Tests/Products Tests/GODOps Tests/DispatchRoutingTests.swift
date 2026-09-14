//
//  DispatchRoutingTests.swift
//  GODOpsTests
//
//  Verifies that GODOps routes JSON config files to the right operation with
//  the right decoded parameters. A SpyOperationHandler replaces the engine
//  handler, so no engine code runs — these tests cover config decoding, the
//  enabled/disabled toggle, operation ordering, settings loading, and the
//  dispatch switch itself, one test per `GoddessConfig.Operations` case.
//

import XCTest
import GoDFoundation
@testable import GODOps

final class DispatchRoutingTests: XCTestCase {

    // MARK: - Harness

    /// Write a GoddessConfig JSON containing the given operation entries into
    /// an InMemoryFST, run it through GODOps with a spy handler, and return
    /// the spy for assertions. Each entry is a raw `Operations` JSON object.
    @discardableResult
    private func route(
        entries: [(operation: String, enabled: String)],
        settingsJSON: String? = nil,
        handler: SpyOperationHandler = SpyOperationHandler()
    ) throws -> SpyOperationHandler {
        let fst = InMemoryFST()
        var fields = [
            "\"name\": \"routing-test\"",
            "\"rootFolder\": \".\"",
        ]
        if let settingsJSON {
            writeText(settingsJSON, at: File("/project/settings.json"), in: fst)
            fields.append("\"settingsFile\": \"/project/settings.json\"")
        }
        let operationEntries = entries.map {
            "{ \"operation\": \($0.operation), \"enabled\": \"\($0.enabled)\" }"
        }
        fields.append("\"operations\": [ \(operationEntries.joined(separator: ", ")) ]")
        writeText("{ \(fields.joined(separator: ", ")) }", at: File("/project/config.json"), in: fst)

        try GODOps.runConfig(at: File("/project/config.json"), fileSystem: StreamedFileSystem(materializing: fst), logger: SilentLogger(), handler: handler)
        return handler
    }

    @discardableResult
    private func route(_ operationJSON: String, settingsJSON: String? = nil) throws -> SpyOperationHandler {
        try route(entries: [(operationJSON, "YES")], settingsJSON: settingsJSON)
    }

    /// Assert exactly one call was routed and return its operation.
    private func singleOperation(
        _ spy: SpyOperationHandler,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> GoddessConfig.Operations {
        XCTAssertEqual(spy.calls.count, 1, "Expected exactly one routed operation", file: file, line: line)
        let call = try XCTUnwrap(spy.calls.first, file: file, line: line)
        return call.operation
    }

    // MARK: - Gamecube

    func testGamecubeDumpRouting() throws {
        let spy = try route("""
        { "gamecubeDump": { "config": { "operations": [ { "operation": { "unpackISO": {
            "isoPath": "/project/game.iso",
            "fstFolder": "/project/Unpacked",
            "overwrite": true,
            "dolphinEngine": "/project/Engines/Dolphin Engine",
            "gamecubeEngine": "/project/Engines/Gamecube Engine"
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .gamecubeDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected gamecubeDump")
        }
        let inner = config.operations.enabledEntries
        XCTAssertEqual(inner.count, 1)
        guard case let .unpackISO(isoPath, fstFolder, overwrite, dolphinEngine, gamecubeEngine) = inner.first else {
            return XCTFail("Expected unpackISO")
        }
        XCTAssertEqual(isoPath, File("/project/game.iso"))
        XCTAssertEqual(fstFolder, Folder("/project/Unpacked"))
        XCTAssertTrue(overwrite)
        XCTAssertEqual(dolphinEngine, Folder("/project/Engines/Dolphin Engine"))
        XCTAssertEqual(gamecubeEngine, Folder("/project/Engines/Gamecube Engine"))
    }

    func testGamecubeBuildRouting() throws {
        let spy = try route("""
        { "gamecubeBuild": { "config": { "operations": [
            { "operation": { "buildISO": {
                "fstPath": "/project/Unpacked",
                "isoPath": "/project/out.iso",
                "overwrite": false,
                "dolphinEngine": "/project/Engines/Dolphin Engine",
                "gamecubeEngine": "/project/Engines/Gamecube Engine"
            } }, "enabled": "YES" },
            { "operation": { "fillISO": { "isoPath": "/project/out.iso", "size": 1459978240 } }, "enabled": "YES" }
        ] } } }
        """)
        guard case let .gamecubeBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected gamecubeBuild")
        }
        let inner = config.operations.enabledEntries
        XCTAssertEqual(inner.count, 2)
        guard case let .buildISO(fstPath, isoPath, overwrite, _, _) = inner.first else {
            return XCTFail("Expected buildISO first")
        }
        XCTAssertEqual(fstPath, Folder("/project/Unpacked"))
        XCTAssertEqual(isoPath, File("/project/out.iso"))
        XCTAssertFalse(overwrite)
        guard case let .fillISO(fillPath, size) = inner.last else {
            return XCTFail("Expected fillISO second")
        }
        XCTAssertEqual(fillPath, File("/project/out.iso"))
        XCTAssertEqual(size, 1459978240)
    }

    // MARK: - Wii

    func testWiiDumpRouting() throws {
        let spy = try route("""
        { "wiiDump": { "config": { "operations": [ { "operation": { "decryptISO": {
            "isoPath": "/project/game.iso",
            "outputFolder": "/project/Decrypted",
            "overwrite": true,
            "wiiEngine": "/project/Engines/Wii Engine",
            "dolphinEngine": "/project/Engines/Dolphin Engine"
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .wiiDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected wiiDump")
        }
        guard case let .decryptISO(isoPath, outputFolder, overwrite, wiiEngine, dolphinEngine) = config.operations.enabledEntries.first else {
            return XCTFail("Expected decryptISO")
        }
        XCTAssertEqual(isoPath, File("/project/game.iso"))
        XCTAssertEqual(outputFolder, Folder("/project/Decrypted"))
        XCTAssertTrue(overwrite)
        XCTAssertEqual(wiiEngine, Folder("/project/Engines/Wii Engine"))
        XCTAssertEqual(dolphinEngine, Folder("/project/Engines/Dolphin Engine"))
    }

    func testWiiBuildRouting() throws {
        let spy = try route("""
        { "wiiBuild": { "config": { "operations": [ { "operation": { "encryptISO": {
            "fstPath": "/project/Decrypted",
            "isoPath": "/project/out.iso",
            "overwrite": true,
            "wiiEngine": "/project/Engines/Wii Engine",
            "dolphinEngine": "/project/Engines/Dolphin Engine"
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .wiiBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected wiiBuild")
        }
        guard case let .encryptISO(fstPath, isoPath, _, _, _) = config.operations.enabledEntries.first else {
            return XCTFail("Expected encryptISO")
        }
        XCTAssertEqual(fstPath, Folder("/project/Decrypted"))
        XCTAssertEqual(isoPath, File("/project/out.iso"))
    }

    // MARK: - ColoXD

    func testColoXDDumpRouting() throws {
        let spy = try route("""
        { "coloXDDump": { "config": { "operations": [ { "operation": { "unpackFSYS": {
            "fsysFile": "/project/files/common.fsys",
            "outputFolder": "/project/Assets",
            "overwrite": true,
            "geniusSonorityEngine": "/project/Engines/GeniusSonority Engine"
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .coloXDDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected coloXDDump")
        }
        guard case let .unpackFSYS(fsysFile, outputFolder, overwrite, engine) = config.operations.enabledEntries.first else {
            return XCTFail("Expected unpackFSYS")
        }
        XCTAssertEqual(fsysFile, File("/project/files/common.fsys"))
        XCTAssertEqual(outputFolder, Folder("/project/Assets"))
        XCTAssertTrue(overwrite)
        XCTAssertEqual(engine, Folder("/project/Engines/GeniusSonority Engine"))
    }

    func testColoXDBuildRouting() throws {
        let spy = try route("""
        { "coloXDBuild": { "config": { "operations": [ { "operation": { "packFSYS": {
            "registryFile": "/project/Assets/common.json",
            "outputFile": "/project/files/common.fsys",
            "sourceFolder": "/project/Assets/common",
            "overwrite": true,
            "geniusSonorityEngine": "/project/Engines/GeniusSonority Engine"
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .coloXDBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected coloXDBuild")
        }
        guard case let .packFSYS(registryFile, outputFile, sourceFolder, overwrite, _) = config.operations.enabledEntries.first else {
            return XCTFail("Expected packFSYS")
        }
        XCTAssertEqual(registryFile, File("/project/Assets/common.json"))
        XCTAssertEqual(outputFile, File("/project/files/common.fsys"))
        XCTAssertEqual(sourceFolder, Folder("/project/Assets/common"))
        XCTAssertTrue(overwrite)
    }

    // MARK: - PBR

    func testPBRDumpRouting() throws {
        let spy = try route("""
        { "pbrDump": { "config": { "operations": [ { "operation": { "dumpPBR": {
            "fstFolder": "/project/Unpacked",
            "outputFolder": "/project/Assets",
            "overwrite": false,
            "dolphinEngine": "/project/Engines/Dolphin Engine",
            "geniusSonorityEngine": "/project/Engines/GeniusSonority Engine"
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .pbrDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected pbrDump")
        }
        guard case let .dumpPBR(fstFolder, outputFolder, overwrite, _, _) = config.operations.enabledEntries.first else {
            return XCTFail("Expected dumpPBR")
        }
        XCTAssertEqual(fstFolder, Folder("/project/Unpacked"))
        XCTAssertEqual(outputFolder, Folder("/project/Assets"))
        XCTAssertFalse(overwrite)
    }

    func testPBRBuildRouting() throws {
        let spy = try route("""
        { "pbrBuild": { "config": { "operations": [ { "operation": { "packPBR": {
            "unpackedFolder": "/project/Unpacked",
            "fstFolder": "/project/Build/Contents/DATA",
            "overwrite": true,
            "geniusSonorityEngine": "/project/Engines/GeniusSonority Engine",
            "pbrEngine": "/project/Engines/PBR Engine",
            "engines": [ "/project/Engines/Pokemon Engine" ]
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .pbrBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected pbrBuild")
        }
        guard case let .packPBR(unpackedFolder, fstFolder, overwrite, genius, pbr, engines) = config.operations.enabledEntries.first else {
            return XCTFail("Expected packPBR")
        }
        XCTAssertEqual(unpackedFolder, Folder("/project/Unpacked"))
        XCTAssertEqual(fstFolder, Folder("/project/Build/Contents/DATA"))
        XCTAssertTrue(overwrite)
        XCTAssertEqual(genius, Folder("/project/Engines/GeniusSonority Engine"))
        XCTAssertEqual(pbr, Folder("/project/Engines/PBR Engine"))
        XCTAssertEqual(engines, [Folder("/project/Engines/Pokemon Engine")])
    }

    // MARK: - DOL

    func testDolDisassemblyRouting() throws {
        let spy = try route("""
        { "dolDisassembly": { "config": {
            "dolPath": "/project/Unpacked/sys/main.dol",
            "outputFolder": "/project/Source",
            "symbolMapPath": "/project/maps/main.map",
            "dolphinEngine": "/project/Engines/Dolphin Engine",
            "typeMapPath": "/project/maps/types.json"
        } } }
        """)
        guard case let .dolDisassembly(config) = try singleOperation(spy) else {
            return XCTFail("Expected dolDisassembly")
        }
        XCTAssertEqual(config.dolPath, File("/project/Unpacked/sys/main.dol"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Source"))
        XCTAssertEqual(config.symbolMapPath, File("/project/maps/main.map"))
        XCTAssertEqual(config.dolphinEngine, Folder("/project/Engines/Dolphin Engine"))
        XCTAssertEqual(config.typeMapPath, File("/project/maps/types.json"))
    }

    func testDolDisassemblyOptionalFieldsCanBeOmitted() throws {
        let spy = try route("""
        { "dolDisassembly": { "config": {
            "dolPath": "/project/main.dol",
            "outputFolder": "/project/Source",
            "dolphinEngine": "/project/Engines/Dolphin Engine"
        } } }
        """)
        guard case let .dolDisassembly(config) = try singleOperation(spy) else {
            return XCTFail("Expected dolDisassembly")
        }
        XCTAssertNil(config.symbolMapPath)
        XCTAssertNil(config.typeMapPath)
    }

    func testDolAssemblyRouting() throws {
        let spy = try route("""
        { "dolAssembly": { "config": {
            "codeFolder": "/project/Source/main",
            "outputDolPath": "/project/Built/main.dol",
            "dolphinEngine": "/project/Engines/Dolphin Engine"
        } } }
        """)
        guard case let .dolAssembly(config) = try singleOperation(spy) else {
            return XCTFail("Expected dolAssembly")
        }
        XCTAssertEqual(config.codeFolder, Folder("/project/Source/main"))
        XCTAssertEqual(config.outputDolPath, File("/project/Built/main.dol"))
        XCTAssertEqual(config.dolphinEngine, Folder("/project/Engines/Dolphin Engine"))
        XCTAssertNil(config.symbolMapPath)
        XCTAssertNil(config.typeMapPath)
        XCTAssertNil(config.bssEntryListPath)
    }

    // MARK: - REL

    func testRelDisassemblyRouting() throws {
        let spy = try route("""
        { "relDisassembly": { "config": {
            "relPath": "/project/files/common.rel",
            "outputFolder": "/project/Source",
            "dolphinEngine": "/project/Engines/Dolphin Engine"
        } } }
        """)
        guard case let .relDisassembly(config) = try singleOperation(spy) else {
            return XCTFail("Expected relDisassembly")
        }
        XCTAssertEqual(config.relPath, File("/project/files/common.rel"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Source"))
        XCTAssertEqual(config.dolphinEngine, Folder("/project/Engines/Dolphin Engine"))
    }

    func testRelAssemblyRouting() throws {
        let spy = try route("""
        { "relAssembly": { "config": {
            "inputFolder": "/project/Source/common",
            "relName": "common",
            "outputPath": "/project/Built/common.rel",
            "overwrite": true
        } } }
        """)
        guard case let .relAssembly(config) = try singleOperation(spy) else {
            return XCTFail("Expected relAssembly")
        }
        XCTAssertEqual(config.inputFolder, Folder("/project/Source/common"))
        XCTAssertEqual(config.relName, "common")
        XCTAssertEqual(config.outputPath, File("/project/Built/common.rel"))
        XCTAssertTrue(config.overwrite)
    }

    func testCommonRelDumpRouting() throws {
        let spy = try route("""
        { "commonRelDump": { "config": {
            "relPath": "/project/files/common.rel",
            "outputFolder": "/project/Source",
            "overwrite": true,
            "dolphinEngine": "/project/Engines/Dolphin Engine",
            "gameEngine": "/project/Engines/XD Engine"
        } } }
        """)
        guard case let .commonRelDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected commonRelDump")
        }
        XCTAssertEqual(config.relPath, File("/project/files/common.rel"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Source"))
        XCTAssertTrue(config.overwrite)
        XCTAssertEqual(config.gameEngine, Folder("/project/Engines/XD Engine"))
    }

    func testCommonRelBuildRouting() throws {
        let spy = try route("""
        { "commonRelBuild": { "config": {
            "inputFolder": "/project/Source/common",
            "relName": "common",
            "outputPath": "/project/Built/common.rel",
            "overwrite": false
        } } }
        """)
        guard case let .commonRelBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected commonRelBuild")
        }
        XCTAssertEqual(config.inputFolder, Folder("/project/Source/common"))
        XCTAssertEqual(config.relName, "common")
        XCTAssertEqual(config.outputPath, File("/project/Built/common.rel"))
        XCTAssertFalse(config.overwrite)
    }

    func testMapRelDumpRouting() throws {
        let spy = try route("""
        { "mapRelDump": { "config": {
            "relPath": "/project/files/M1_out.rel",
            "outputFolder": "/project/Source",
            "overwrite": true,
            "typeMapPath": "/project/maps/map-types.json",
            "dolphinEngine": "/project/Engines/Dolphin Engine",
            "gameEngine": "/project/Engines/Colosseum Engine"
        } } }
        """)
        guard case let .mapRelDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected mapRelDump")
        }
        XCTAssertEqual(config.relPath, File("/project/files/M1_out.rel"))
        XCTAssertEqual(config.typeMapPath, File("/project/maps/map-types.json"))
        XCTAssertEqual(config.gameEngine, Folder("/project/Engines/Colosseum Engine"))
    }

    func testMapRelBuildRouting() throws {
        let spy = try route("""
        { "mapRelBuild": { "config": {
            "inputFolder": "/project/Source/M1_out",
            "relName": "M1_out",
            "outputPath": "/project/Built/M1_out.rel",
            "overwrite": true
        } } }
        """)
        guard case let .mapRelBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected mapRelBuild")
        }
        XCTAssertEqual(config.relName, "M1_out")
        XCTAssertEqual(config.outputPath, File("/project/Built/M1_out.rel"))
    }

    func testMapRelsDumpRoutingWithFilter() throws {
        let spy = try route("""
        { "mapRelsDump": { "config": {
            "relsFolder": "/project/files",
            "outputFolder": "/project/Source",
            "overwrite": true,
            "typeMapPath": "/project/maps/map-types.json",
            "dolphinEngine": "/project/Engines/Dolphin Engine",
            "gameEngine": "/project/Engines/Colosseum Engine",
            "filter": { "onlyPrefixes": { "_0": ["M1_", "B2_"] } }
        } } }
        """)
        guard case let .mapRelsDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected mapRelsDump")
        }
        XCTAssertEqual(config.relsFolder, Folder("/project/files"))
        XCTAssertEqual(config.filter, .onlyPrefixes(["M1_", "B2_"]))
    }

    func testMapRelsBuildRouting() throws {
        let spy = try route("""
        { "mapRelsBuild": { "config": {
            "inputFolder": "/project/Source/maps",
            "outputFolder": "/project/Built/maps",
            "overwrite": true
        } } }
        """)
        guard case let .mapRelsBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected mapRelsBuild")
        }
        XCTAssertEqual(config.inputFolder, Folder("/project/Source/maps"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Built/maps"))
        XCTAssertTrue(config.overwrite)
    }

    // MARK: - CISO

    func testCISODumpRouting() throws {
        let spy = try route("""
        { "cisoDump": { "config": {
            "cisoPath": "/project/game.ciso",
            "isoPath": "/project/game.iso",
            "targetDiscSize": 1459978240,
            "overwrite": true
        } } }
        """)
        guard case let .cisoDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected cisoDump")
        }
        XCTAssertEqual(config.cisoPath, File("/project/game.ciso"))
        XCTAssertEqual(config.isoPath, File("/project/game.iso"))
        XCTAssertEqual(config.targetDiscSize, 1459978240)
        XCTAssertTrue(config.overwrite)
    }

    func testCISOBuildRouting() throws {
        let spy = try route("""
        { "cisoBuild": { "config": {
            "isoPath": "/project/game.iso",
            "cisoPath": "/project/game.ciso",
            "blockSize": 2097152,
            "overwrite": false
        } } }
        """)
        guard case let .cisoBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected cisoBuild")
        }
        XCTAssertEqual(config.isoPath, File("/project/game.iso"))
        XCTAssertEqual(config.cisoPath, File("/project/game.ciso"))
        XCTAssertEqual(config.blockSize, 2097152)
        XCTAssertFalse(config.overwrite)
    }

    // MARK: - GCI

    func testGCIDumpRouting() throws {
        let spy = try route("""
        { "gciDump": { "config": { "operations": [ { "operation": { "dumpGCI": {
            "gciFile": "/project/save.gci",
            "outputFolder": "/project/Save",
            "overwrite": true
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .gciDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected gciDump")
        }
        guard case let .dumpGCI(gciFile, outputFolder, overwrite) = config.operations.enabledEntries.first else {
            return XCTFail("Expected dumpGCI")
        }
        XCTAssertEqual(gciFile, File("/project/save.gci"))
        XCTAssertEqual(outputFolder, Folder("/project/Save"))
        XCTAssertTrue(overwrite)
    }

    func testGCIBuildRouting() throws {
        let spy = try route("""
        { "gciBuild": { "config": { "operations": [ { "operation": { "buildGCI": {
            "inputFolder": "/project/Save",
            "gciFile": "/project/rebuilt.gci",
            "overwrite": true
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .gciBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected gciBuild")
        }
        guard case let .buildGCI(inputFolder, gciFile, overwrite) = config.operations.enabledEntries.first else {
            return XCTFail("Expected buildGCI")
        }
        XCTAssertEqual(inputFolder, Folder("/project/Save"))
        XCTAssertEqual(gciFile, File("/project/rebuilt.gci"))
        XCTAssertTrue(overwrite)
    }

    // MARK: - XD save

    func testXDSaveDumpRouting() throws {
        let spy = try route("""
        { "xdSaveDump": { "config": { "operations": [ { "operation": { "dumpXDSave": {
            "unpackedFolder": "/project/Save",
            "outputFolder": "/project/Save/Dumped",
            "overwrite": true,
            "decrypted": false,
            "xdEngine": "/project/Engines/XD Engine"
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .xdSaveDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected xdSaveDump")
        }
        guard case let .dumpXDSave(unpackedFolder, outputFolder, overwrite, decrypted, xdEngine) = config.operations.enabledEntries.first else {
            return XCTFail("Expected dumpXDSave")
        }
        XCTAssertEqual(unpackedFolder, Folder("/project/Save"))
        XCTAssertEqual(outputFolder, Folder("/project/Save/Dumped"))
        XCTAssertTrue(overwrite)
        XCTAssertFalse(decrypted)
        XCTAssertEqual(xdEngine, Folder("/project/Engines/XD Engine"))
    }

    func testXDSaveBuildRouting() throws {
        let spy = try route("""
        { "xdSaveBuild": { "config": { "operations": [ { "operation": { "buildXDSave": {
            "inputFolder": "/project/Save/Dumped",
            "unpackedFolder": "/project/Save",
            "overwrite": true,
            "decrypted": true,
            "xdEngine": "/project/Engines/XD Engine"
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .xdSaveBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected xdSaveBuild")
        }
        guard case let .buildXDSave(inputFolder, unpackedFolder, _, decrypted, _) = config.operations.enabledEntries.first else {
            return XCTFail("Expected buildXDSave")
        }
        XCTAssertEqual(inputFolder, Folder("/project/Save/Dumped"))
        XCTAssertEqual(unpackedFolder, Folder("/project/Save"))
        XCTAssertTrue(decrypted)
    }

    // MARK: - Colosseum save

    func testColoSaveDumpRouting() throws {
        let spy = try route("""
        { "coloSaveDump": { "config": { "operations": [ { "operation": { "dumpColosseumSave": {
            "unpackedFolder": "/project/Save",
            "outputFolder": "/project/Save/Dumped",
            "overwrite": true,
            "decrypted": false,
            "colosseumEngine": "/project/Engines/Colosseum Engine"
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .coloSaveDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected coloSaveDump")
        }
        guard case let .dumpColosseumSave(unpackedFolder, outputFolder, _, decrypted, engine) = config.operations.enabledEntries.first else {
            return XCTFail("Expected dumpColosseumSave")
        }
        XCTAssertEqual(unpackedFolder, Folder("/project/Save"))
        XCTAssertEqual(outputFolder, Folder("/project/Save/Dumped"))
        XCTAssertFalse(decrypted)
        XCTAssertEqual(engine, Folder("/project/Engines/Colosseum Engine"))
    }

    func testColoSaveBuildRouting() throws {
        let spy = try route("""
        { "coloSaveBuild": { "config": { "operations": [ { "operation": { "buildColosseumSave": {
            "inputFolder": "/project/Save/Dumped",
            "unpackedFolder": "/project/Save",
            "overwrite": true,
            "decrypted": false,
            "colosseumEngine": "/project/Engines/Colosseum Engine"
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .coloSaveBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected coloSaveBuild")
        }
        guard case let .buildColosseumSave(inputFolder, unpackedFolder, overwrite, decrypted, _) = config.operations.enabledEntries.first else {
            return XCTFail("Expected buildColosseumSave")
        }
        XCTAssertEqual(inputFolder, Folder("/project/Save/Dumped"))
        XCTAssertEqual(unpackedFolder, Folder("/project/Save"))
        XCTAssertTrue(overwrite)
        XCTAssertFalse(decrypted)
    }

    // MARK: - Toggle, ordering, settings, errors

    private let cisoDumpJSON = """
    { "cisoDump": { "config": { "cisoPath": "/project/a.ciso", "isoPath": "/project/a.iso", "overwrite": true } } }
    """
    private let cisoBuildJSON = """
    { "cisoBuild": { "config": { "isoPath": "/project/a.iso", "cisoPath": "/project/a.ciso", "blockSize": 32768, "overwrite": true } } }
    """
    private let gciDumpJSON = """
    { "gciDump": { "config": { "operations": [ { "operation": { "dumpGCI": {
        "gciFile": "/project/save.gci", "outputFolder": "/project/Save", "overwrite": true
    } }, "enabled": "YES" } ] } } }
    """

    func testDisabledOperationsAreSkipped() throws {
        let spy = try route(entries: [
            (cisoDumpJSON, "NO"),
            (cisoBuildJSON, "YES"),
            (gciDumpJSON, "NO"),
        ])
        XCTAssertEqual(spy.calls.count, 1)
        guard case .cisoBuild = spy.calls[0].operation else {
            return XCTFail("Only the enabled cisoBuild should have routed")
        }
    }

    func testToggleAcceptsTrueSpelling() throws {
        let spy = try route(entries: [(cisoDumpJSON, "true")])
        XCTAssertEqual(spy.calls.count, 1)
    }

    func testUnknownToggleValueDisables() throws {
        let spy = try route(entries: [(cisoDumpJSON, "MAYBE")])
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testOperationsRunInConfigOrder() throws {
        let spy = try route(entries: [
            (gciDumpJSON, "YES"),
            (cisoDumpJSON, "YES"),
            (cisoBuildJSON, "YES"),
        ])
        XCTAssertEqual(spy.calls.count, 3)
        guard case .gciDump = spy.calls[0].operation,
              case .cisoDump = spy.calls[1].operation,
              case .cisoBuild = spy.calls[2].operation else {
            return XCTFail("Operations should route in config order")
        }
    }

    func testSettingsFileIsLoadedAndPassedToOperations() throws {
        let spy = try route(
            entries: [(cisoDumpJSON, "YES")],
            settingsJSON: """
            { "verbose": true, "wiiCommonKeyFile": "/project/keys/common-key.txt" }
            """
        )
        let call = try XCTUnwrap(spy.calls.first)
        XCTAssertTrue(call.settings.verbose)
        XCTAssertEqual(call.settings.wiiCommonKeyFile, File("/project/keys/common-key.txt"))
    }

    func testMissingSettingsFileFallsBackToDefaults() throws {
        // settingsFile points at a file that doesn't exist in the tree.
        let fst = InMemoryFST()
        writeText("""
        { "name": "t", "rootFolder": ".", "settingsFile": "/project/nope.json",
          "operations": [ { "operation": \(cisoDumpJSON), "enabled": "YES" } ] }
        """, at: File("/project/config.json"), in: fst)
        let spy = SpyOperationHandler()
        try GODOps.runConfig(at: File("/project/config.json"), fileSystem: StreamedFileSystem(materializing: fst), logger: SilentLogger(), handler: spy)
        let call = try XCTUnwrap(spy.calls.first)
        XCTAssertFalse(call.settings.verbose)
        XCTAssertNil(call.settings.wiiCommonKeyFile)
    }

    func testHandlerErrorStopsExecutionAndPropagates() throws {
        struct TestError: Error {}
        let failing = SpyOperationHandler()
        failing.errorToThrow = TestError()
        XCTAssertThrowsError(
            try route(entries: [(cisoDumpJSON, "YES"), (cisoBuildJSON, "YES")], handler: failing)
        ) { error in
            XCTAssertTrue(error is TestError)
        }
        XCTAssertEqual(failing.calls.count, 1, "Second operation must not run after the first throws")
    }

    func testMalformedConfigThrows() {
        let fst = InMemoryFST()
        writeText("{ \"name\": \"broken\" }", at: File("/project/config.json"), in: fst)
        XCTAssertThrowsError(
            try GODOps.runConfig(at: File("/project/config.json"), fileSystem: StreamedFileSystem(materializing: fst), logger: SilentLogger(), handler: SpyOperationHandler())
        )
    }

    func testUnknownOperationKeyThrows() {
        let fst = InMemoryFST()
        writeText("""
        { "name": "t", "rootFolder": ".",
          "operations": [ { "operation": { "notARealOperation": { "config": {} } }, "enabled": "YES" } ] }
        """, at: File("/project/config.json"), in: fst)
        XCTAssertThrowsError(
            try GODOps.runConfig(at: File("/project/config.json"), fileSystem: StreamedFileSystem(materializing: fst), logger: SilentLogger(), handler: SpyOperationHandler())
        )
    }

    // MARK: - runOperation (single-operation JSON escape hatch)

    func testRunOperationDecodesBareOperation() throws {
        let spy = SpyOperationHandler()
        try GODOps.runOperation(
            json: Data(cisoDumpJSON.utf8),
            settingsJSON: nil,
            fileSystem: StreamedFileSystem(materializing: InMemoryFST()),
            logger: SilentLogger(),
            handler: spy
        )
        XCTAssertEqual(spy.calls.count, 1)
        guard case .cisoDump = spy.calls[0].operation else {
            return XCTFail("Expected cisoDump")
        }
    }

    func testRunOperationDecodesWrappedOperation() throws {
        let spy = SpyOperationHandler()
        let wrapped = "{ \"operation\": \(cisoDumpJSON), \"enabled\": \"YES\" }"
        try GODOps.runOperation(
            json: Data(wrapped.utf8),
            settingsJSON: Data("{ \"verbose\": true }".utf8),
            fileSystem: StreamedFileSystem(materializing: InMemoryFST()),
            logger: SilentLogger(),
            handler: spy
        )
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertTrue(try XCTUnwrap(spy.calls.first).settings.verbose)
    }

    // MARK: - Convert

    func testConvertDecodeFileRouting() throws {
        let spy = try route("""
        { "convert": { "config": { "operations": [ { "operation": { "decodeFile": {
            "inputFile": "/project/in/common.msg",
            "outputFolder": "/project/out",
            "overwrite": true,
            "format": "msgColo"
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .convert(config) = try singleOperation(spy) else {
            return XCTFail("Expected convert")
        }
        let inner = config.operations.enabledEntries
        XCTAssertEqual(inner.count, 1)
        guard case let .decodeFile(inputFile, outputFolder, overwrite, format) = inner.first else {
            return XCTFail("Expected decodeFile")
        }
        XCTAssertEqual(inputFile, File("/project/in/common.msg"))
        XCTAssertEqual(outputFolder, Folder("/project/out"))
        XCTAssertTrue(overwrite)
        XCTAssertEqual(format, .msgColo)
        XCTAssertEqual(format.fileExtension, "msg")
    }

    func testConvertDecodeStructTableRouting() throws {
        let spy = try route("""
        { "convert": { "config": { "operations": [ { "operation": { "decodeStructTable": {
            "inputFile": "/project/in/table.bin",
            "outputFolder": "/project/out",
            "overwrite": false,
            "structName": "TestRecord",
            "engines": ["/project/Engines/Some Engine", "/project/Engines/Other Engine"]
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .convert(config) = try singleOperation(spy) else {
            return XCTFail("Expected convert")
        }
        guard case let .decodeStructTable(inputFile, outputFolder, overwrite, structName, engines) = config.operations.enabledEntries.first else {
            return XCTFail("Expected decodeStructTable")
        }
        XCTAssertEqual(inputFile, File("/project/in/table.bin"))
        XCTAssertEqual(outputFolder, Folder("/project/out"))
        XCTAssertFalse(overwrite)
        XCTAssertEqual(structName, "TestRecord")
        XCTAssertEqual(engines, [Folder("/project/Engines/Some Engine"), Folder("/project/Engines/Other Engine")])
    }

    // MARK: - Nintendo archives (U8 / NARC)

    func testNintendoArchiveDumpRouting() throws {
        let spy = try route("""
        { "nintendoArchiveDump": { "config": {
            "archivePath": "/project/files/homeBtn.arc",
            "outputFolder": "/project/Source/Archives",
            "overwrite": true
        } } }
        """)
        guard case let .nintendoArchiveDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected nintendoArchiveDump")
        }
        XCTAssertEqual(config.archivePath, File("/project/files/homeBtn.arc"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Source/Archives"))
        XCTAssertTrue(config.overwrite)
        // Absent engine folder means the built-in defaults.
        XCTAssertNil(config.nintendoEngine)
    }

    func testNintendoArchiveBuildRouting() throws {
        let spy = try route("""
        { "nintendoArchiveBuild": { "config": {
            "manifestPath": "/project/Source/Archives/homeBtn.arc.json",
            "outputPath": "/project/Built/files/homeBtn.arc",
            "overwrite": false
        } } }
        """)
        guard case let .nintendoArchiveBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected nintendoArchiveBuild")
        }
        XCTAssertEqual(config.manifestPath, File("/project/Source/Archives/homeBtn.arc.json"))
        XCTAssertEqual(config.outputPath, File("/project/Built/files/homeBtn.arc"))
        XCTAssertFalse(config.overwrite)
    }

    func testNintendoArchivesDumpRoutingWithFilter() throws {
        let spy = try route("""
        { "nintendoArchivesDump": { "config": {
            "archivesFolder": "/project/files",
            "outputFolder": "/project/Source/Archives",
            "overwrite": true,
            "filter": { "onlyFormats": { "_0": ["narc"] } },
            "recursive": true,
            "nintendoEngine": "/project/Engines/Nintendo Engine"
        } } }
        """)
        guard case let .nintendoArchivesDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected nintendoArchivesDump")
        }
        XCTAssertEqual(config.archivesFolder, Folder("/project/files"))
        XCTAssertEqual(config.filter, .onlyFormats(["narc"]))
        XCTAssertTrue(config.recursive)
        XCTAssertEqual(config.nintendoEngine, Folder("/project/Engines/Nintendo Engine"))
    }

    func testNintendoArchivesDumpRoutingWithExtensionFilter() throws {
        let spy = try route("""
        { "nintendoArchivesDump": { "config": {
            "archivesFolder": "/project/files",
            "outputFolder": "/project/Source/Archives",
            "overwrite": true,
            "filter": { "onlyExtensions": { "_0": ["arc"] } },
            "recursive": false
        } } }
        """)
        guard case let .nintendoArchivesDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected nintendoArchivesDump")
        }
        XCTAssertEqual(config.filter, .onlyExtensions(["arc"]))
        XCTAssertFalse(config.recursive)
    }

    func testNintendoArchivesBuildRouting() throws {
        let spy = try route("""
        { "nintendoArchivesBuild": { "config": {
            "inputFolder": "/project/Source/Archives",
            "outputFolder": "/project/Built/files",
            "overwrite": true,
            "recursive": true
        } } }
        """)
        guard case let .nintendoArchivesBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected nintendoArchivesBuild")
        }
        XCTAssertEqual(config.inputFolder, Folder("/project/Source/Archives"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Built/files"))
    }

    // MARK: - process(inputFile:) extension dispatch

    func testProcessRejectsUnsupportedFileType() {
        XCTAssertThrowsError(try GODOps.process(inputFile: File("/tmp/file.xyz"), toolVersion: "0.0.0")) { error in
            guard case GODOps.DispatchError.unsupportedFileType(let ext, _) = error else {
                return XCTFail("Expected unsupportedFileType, got \(error)")
            }
            XCTAssertEqual(ext, "xyz")
        }
    }

    func testProcessIgnoresFilesWithoutExtension() throws {
        // No file type → silently skipped, never dispatched.
        try GODOps.process(inputFile: File("/tmp/no-extension"), toolVersion: "0.0.0")
    }

    // MARK: - PBR fonts

    func testPBRFontDumpRouting() throws {
        let spy = try route("""
        { "pbrFontDump": { "config": {
            "fontPath": "/project/Unpacked/Data/Text/Fonts/common_0033.FNT",
            "outputFolder": "/project/Source/Fonts",
            "overwrite": true
        } } }
        """)
        guard case let .pbrFontDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected pbrFontDump")
        }
        XCTAssertEqual(config.fontPath, File("/project/Unpacked/Data/Text/Fonts/common_0033.FNT"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Source/Fonts"))
        XCTAssertTrue(config.overwrite)
    }

    func testPBRFontsDumpRouting() throws {
        let spy = try route("""
        { "pbrFontsDump": { "config": {
            "fontsFolder": "/project/Unpacked/Data/Text/Fonts",
            "outputFolder": "/project/Source/Fonts",
            "overwrite": false
        } } }
        """)
        guard case let .pbrFontsDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected pbrFontsDump")
        }
        XCTAssertEqual(config.fontsFolder, Folder("/project/Unpacked/Data/Text/Fonts"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Source/Fonts"))
        XCTAssertFalse(config.overwrite)
    }

    func testPBRFontBuildRouting() throws {
        let spy = try route("""
        { "pbrFontBuild": { "config": {
            "fontFolder": "/project/Source/Fonts/common_0033",
            "outputFolder": "/project/Unpacked/Data/Text/Fonts",
            "overwrite": true
        } } }
        """)
        guard case let .pbrFontBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected pbrFontBuild")
        }
        XCTAssertEqual(config.fontFolder, Folder("/project/Source/Fonts/common_0033"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Unpacked/Data/Text/Fonts"))
        XCTAssertTrue(config.overwrite)
    }

    func testPBRFontsBuildRouting() throws {
        let spy = try route("""
        { "pbrFontsBuild": { "config": {
            "fontsFolder": "/project/Source/Fonts",
            "outputFolder": "/project/Unpacked/Data/Text/Fonts",
            "overwrite": true
        } } }
        """)
        guard case let .pbrFontsBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected pbrFontsBuild")
        }
        XCTAssertEqual(config.fontsFolder, Folder("/project/Source/Fonts"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Unpacked/Data/Text/Fonts"))
    }
}
