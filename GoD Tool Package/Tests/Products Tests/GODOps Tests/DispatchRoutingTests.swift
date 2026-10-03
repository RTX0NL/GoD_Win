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
        XCTAssertNil(config.outputSymbolMapPath)
        XCTAssertNil(config.typeMapPath)
        XCTAssertNil(config.bssEntryListPath)
    }

    func testDolAssemblyRoutingCarriesTheSymbolMapPaths() throws {
        let spy = try route("""
        { "dolAssembly": { "config": {
            "codeFolder": "/project/Source/main",
            "outputDolPath": "/project/Built/main.dol",
            "symbolMapPath": "/project/Engines/XD Engine/Resources/dol.map",
            "outputSymbolMapPath": "/project/Engines/XD Engine/Resources/dol.map",
            "dolphinEngine": "/project/Engines/Dolphin Engine"
        } } }
        """)
        guard case let .dolAssembly(config) = try singleOperation(spy) else {
            return XCTFail("Expected dolAssembly")
        }
        XCTAssertEqual(config.symbolMapPath, File("/project/Engines/XD Engine/Resources/dol.map"))
        XCTAssertEqual(config.outputSymbolMapPath, File("/project/Engines/XD Engine/Resources/dol.map"))
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

    func testRelsDumpRouting() throws {
        let spy = try route("""
        { "relsDump": { "config": {
            "routesPath": "/project/Engines/XD Engine/Resources/rel_routes.json",
            "routesEngine": "/project/Engines/XD Engine",
            "inputFolder": "/project/Build/Unpacked",
            "outputFolder": "/project/Source/Code/Relocatable Modules",
            "overwrite": false,
            "dolphinEngine": "/project/Engines/Dolphin Engine",
            "dolSymbolMapPath": "/project/Engines/XD Engine/Resources/dol.map"
        } } }
        """)
        guard case let .relsDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected relsDump")
        }
        XCTAssertEqual(config.routesPath, File("/project/Engines/XD Engine/Resources/rel_routes.json"))
        XCTAssertEqual(config.routesEngine, Folder("/project/Engines/XD Engine"))
        XCTAssertEqual(config.inputFolder, Folder("/project/Build/Unpacked"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Source/Code/Relocatable Modules"))
        XCTAssertFalse(config.overwrite)
        XCTAssertEqual(config.dolSymbolMapPath, File("/project/Engines/XD Engine/Resources/dol.map"))
        XCTAssertNil(config.engines)
    }

    func testRelsBuildRouting() throws {
        let spy = try route("""
        { "relsBuild": { "config": {
            "routesPath": "/project/Engines/XD Engine/Resources/rel_routes.json",
            "inputFolder": "/project/Source/Code/Relocatable Modules",
            "outputFolder": "/project/Build/Unpacked",
            "overwrite": true,
            "engines": ["/project/Engines/XD Engine"]
        } } }
        """)
        guard case let .relsBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected relsBuild")
        }
        XCTAssertEqual(config.inputFolder, Folder("/project/Source/Code/Relocatable Modules"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Build/Unpacked"))
        XCTAssertTrue(config.overwrite)
        XCTAssertEqual(config.engines, [Folder("/project/Engines/XD Engine")])
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
        guard case let .dumpGCI(gciFile, outputFolder, overwrite, saveEngine)
                = config.operations.enabledEntries.first else {
            return XCTFail("Expected dumpGCI")
        }
        XCTAssertEqual(gciFile, File("/project/save.gci"))
        XCTAssertEqual(outputFolder, Folder("/project/Save"))
        XCTAssertTrue(overwrite)
        // Optional; absent means look the save-card shape up from the
        // gamecode rather than a project engine folder.
        XCTAssertNil(saveEngine)
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

    // MARK: - Save sections

    func testSaveSectionsDumpRouting() throws {
        let spy = try route("""
        { "saveSectionsDump": { "config": { "operations": [ { "operation": { "dumpSaveSections": {
            "slotFolder": "/project/Source/Save/Latest Slot",
            "overwrite": true,
            "layout": "/project/Engines/XD Engine/Resources/save_section_layout.json",
            "engines": [ "/project/Engines/XD Engine" ],
            "flagsTable": "/project/Engines/XD Engine/Resources/general_flags.csv"
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .saveSectionsDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected saveSectionsDump")
        }
        guard case let .dumpSaveSections(slotFolder, overwrite, layout, engines, flagsTable) = config.operations.enabledEntries.first else {
            return XCTFail("Expected dumpSaveSections")
        }
        XCTAssertEqual(slotFolder, Folder("/project/Source/Save/Latest Slot"))
        XCTAssertTrue(overwrite)
        XCTAssertEqual(layout, File("/project/Engines/XD Engine/Resources/save_section_layout.json"))
        XCTAssertEqual(engines, [Folder("/project/Engines/XD Engine")])
        XCTAssertEqual(flagsTable, File("/project/Engines/XD Engine/Resources/general_flags.csv"))
    }

    /// `flagsTable` is optional — a layout of plain structs needs no table.
    func testSaveSectionsBuildRoutingWithoutAFlagTable() throws {
        let spy = try route("""
        { "saveSectionsBuild": { "config": { "operations": [ { "operation": { "buildSaveSections": {
            "slotFolder": "/project/Source/Save/Latest Slot",
            "overwrite": true,
            "layout": "/project/layout.json",
            "engines": [ ]
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .saveSectionsBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected saveSectionsBuild")
        }
        guard case let .buildSaveSections(slotFolder, _, layout, engines, flagsTable) = config.operations.enabledEntries.first else {
            return XCTFail("Expected buildSaveSections")
        }
        XCTAssertEqual(slotFolder, Folder("/project/Source/Save/Latest Slot"))
        XCTAssertEqual(layout, File("/project/layout.json"))
        XCTAssertTrue(engines.isEmpty)
        XCTAssertNil(flagsTable)
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

    /// The MCP server's `run_operation` tool is this entry point with a bare
    /// operation object, so every operation family has to decode through
    /// it — the compression ops are the newest and have no config-file
    /// precedent to fall back on.
    func testRunOperationDecodesCompressionOperations() throws {
        let spy = SpyOperationHandler()
        let compress = """
        { "compress": { "config": {
            "inputFile": "/project/in/model.dat", "format": "yaz0", "overwrite": true,
            "options": { "alignment": 16 }
        } } }
        """
        let decompressFiles = """
        { "decompressFiles": { "config": {
            "inputFolder": "/project/packed", "outputFolder": "/project/out",
            "overwrite": true, "recursive": true, "range": { "offset": 32 }
        } } }
        """
        for json in [compress, decompressFiles] {
            try GODOps.runOperation(
                json: Data(json.utf8),
                settingsJSON: nil,
                fileSystem: StreamedFileSystem(materializing: InMemoryFST()),
                logger: SilentLogger(),
                handler: spy
            )
        }
        XCTAssertEqual(spy.calls.count, 2)
        guard case let .compress(config) = spy.calls[0].operation else {
            return XCTFail("Expected compress")
        }
        XCTAssertEqual(config.format, .yaz0)
        XCTAssertEqual(config.options?.alignment, 16)
        guard case let .decompressFiles(batch) = spy.calls[1].operation else {
            return XCTFail("Expected decompressFiles")
        }
        XCTAssertEqual(batch.range?.offset, 32)
        XCTAssertNil(batch.format)
    }

    // MARK: - Convert

    func testConvertDecodeFileRouting() throws {
        let spy = try route("""
        { "convert": { "config": { "operations": [ { "operation": { "decodeFile": {
            "inputFile": "/project/in/common.msg",
            "outputFolder": "/project/out",
            "overwrite": true,
            "format": "msg-colo"
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
            "engines": ["/project/Engines/Some Engine", "/project/Engines/Other Engine"],
            "fileOffset": 16,
            "count": 3
        } }, "enabled": "YES" } ] } } }
        """)
        guard case let .convert(config) = try singleOperation(spy) else {
            return XCTFail("Expected convert")
        }
        guard case let .decodeStructTable(inputFile, outputFolder, overwrite, structName, engines, fileOffset, count) = config.operations.enabledEntries.first else {
            return XCTFail("Expected decodeStructTable")
        }
        XCTAssertEqual(inputFile, File("/project/in/table.bin"))
        XCTAssertEqual(outputFolder, Folder("/project/out"))
        XCTAssertFalse(overwrite)
        XCTAssertEqual(structName, "TestRecord")
        XCTAssertEqual(engines, [Folder("/project/Engines/Some Engine"), Folder("/project/Engines/Other Engine")])
        XCTAssertEqual(fileOffset, 16)
        XCTAssertEqual(count, 3)
    }

    func testConvertStructOffsetsAreOptionalInJSON() throws {
        // Older configs carry none of fileOffset / count / insertOffset.
        let spy = try route("""
        { "convert": { "config": { "operations": [
          { "operation": { "decodeStruct": {
              "inputFile": "/project/in/one.bin", "outputFolder": "/project/out", "overwrite": true,
              "structName": "TestRecord", "engines": ["/project/Engines/Some Engine"]
          } }, "enabled": "YES" },
          { "operation": { "encodeStructTable": {
              "inputFile": "/project/json/table.json", "outputFolder": "/project/bin", "overwrite": true,
              "structName": "TestRecord", "engines": ["/project/Engines/Some Engine"], "insertOffset": 32
          } }, "enabled": "YES" }
        ] } } }
        """)
        guard case let .convert(config) = try singleOperation(spy) else {
            return XCTFail("Expected convert")
        }
        let entries = config.operations.enabledEntries
        XCTAssertEqual(entries.count, 2)
        guard case let .decodeStruct(_, _, _, _, _, fileOffset) = entries[0] else {
            return XCTFail("Expected decodeStruct")
        }
        XCTAssertNil(fileOffset)
        guard case let .encodeStructTable(_, _, _, _, _, insertOffset) = entries[1] else {
            return XCTFail("Expected encodeStructTable")
        }
        XCTAssertEqual(insertOffset, 32)
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

    func testProcessRejectsFilesWithoutExtension() throws {
        // An extensionless input used to be skipped silently, so pointing the
        // tool at something it can't open (a Wii NAND `PbrSaveData`, say)
        // printed nothing and exited 0. It now says what it couldn't open.
        XCTAssertThrowsError(
            try GODOps.process(inputFile: File("/tmp/no-extension"), toolVersion: "0.0.0")
        ) { error in
            guard case GODOps.DispatchError.noFileExtension = error else {
                return XCTFail("expected noFileExtension, got \(error)")
            }
            XCTAssertTrue("\(error)".contains("no file extension"))
        }
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

    func testPBRStringsDumpRouting() throws {
        let spy = try route("""
        { "pbrStringsDump": { "config": {
            "unpackedFolder": "/project/Build/Unpacked",
            "messagesFolder": "/project/Build/Unpacked/Data/Text/Messages",
            "directoryFile": "/project/Build/Unpacked/Data/Common/common_091.bin",
            "outputFile": "/project/Source/Text/Strings.json",
            "overwrite": true
        } } }
        """)
        guard case let .pbrStringsDump(config) = try singleOperation(spy) else {
            return XCTFail("Expected pbrStringsDump")
        }
        XCTAssertEqual(config.unpackedFolder, Folder("/project/Build/Unpacked"))
        XCTAssertEqual(config.messagesFolder, Folder("/project/Build/Unpacked/Data/Text/Messages"))
        XCTAssertEqual(config.directoryFile, File("/project/Build/Unpacked/Data/Common/common_091.bin"))
        XCTAssertEqual(config.outputFile, File("/project/Source/Text/Strings.json"))
        XCTAssertTrue(config.overwrite)
    }

    func testPBRStringsBuildRouting() throws {
        let spy = try route("""
        { "pbrStringsBuild": { "config": {
            "stringsFile": "/project/Source/Text/Strings.json",
            "unpackedFolder": "/project/Build/Unpacked",
            "overwrite": true
        } } }
        """)
        guard case let .pbrStringsBuild(config) = try singleOperation(spy) else {
            return XCTFail("Expected pbrStringsBuild")
        }
        XCTAssertEqual(config.stringsFile, File("/project/Source/Text/Strings.json"))
        XCTAssertEqual(config.unpackedFolder, Folder("/project/Build/Unpacked"))
        XCTAssertTrue(config.overwrite)
    }

    // MARK: - Compression

    func testCompressRouting() throws {
        let spy = try route("""
        { "compress": { "config": {
            "inputFile": "/project/Source/Models/absol.dat",
            "format": "yaz0",
            "outputFile": "/project/Build/absol.dat.szs",
            "overwrite": true,
            "options": { "alignment": 32, "deferredMatching": false, "maxChainLength": 64 }
        } } }
        """)
        guard case let .compress(config) = try singleOperation(spy) else {
            return XCTFail("Expected compress")
        }
        XCTAssertEqual(config.inputFile, File("/project/Source/Models/absol.dat"))
        XCTAssertEqual(config.format, .yaz0)
        XCTAssertEqual(config.outputFile, File("/project/Build/absol.dat.szs"))
        XCTAssertTrue(config.overwrite)
        XCTAssertEqual(config.options?.alignment, 32)
        XCTAssertEqual(config.options?.deferredMatching, false)
        XCTAssertEqual(config.options?.maxChainLength, 64)
        XCTAssertNil(config.options?.windowBits)
    }

    func testCompressRoutingRejectsAnUnknownFormat() {
        XCTAssertThrowsError(try route("""
        { "compress": { "config": {
            "inputFile": "/project/in.bin", "format": "zstd", "overwrite": true
        } } }
        """))
    }

    func testDecompressRoutingWithRangeAndNoFormat() throws {
        let spy = try route("""
        { "decompress": { "config": {
            "inputFile": "/project/Build/Contents/files/common.fsys",
            "range": { "offset": 1440 },
            "outputFile": "/project/Source/common_entry0.bin",
            "overwrite": false
        } } }
        """)
        guard case let .decompress(config) = try singleOperation(spy) else {
            return XCTFail("Expected decompress")
        }
        XCTAssertEqual(config.inputFile, File("/project/Build/Contents/files/common.fsys"))
        XCTAssertNil(config.format)
        XCTAssertEqual(config.range?.offset, 1440)
        XCTAssertNil(config.range?.length)
        XCTAssertEqual(config.outputFile, File("/project/Source/common_entry0.bin"))
        XCTAssertFalse(config.overwrite)
        XCTAssertNil(config.options)
    }

    func testDecompressRoutingWithNamedRawLZSS() throws {
        let spy = try route("""
        { "decompress": { "config": {
            "inputFile": "/project/in/stream.lzss",
            "format": "lzss-raw",
            "overwrite": true,
            "options": { "windowBits": 12, "lengthBits": 4, "threshold": 2 }
        } } }
        """)
        guard case let .decompress(config) = try singleOperation(spy) else {
            return XCTFail("Expected decompress")
        }
        XCTAssertEqual(config.format, .lzssRaw)
        XCTAssertNil(config.range)
        XCTAssertNil(config.outputFile)
        XCTAssertEqual(config.options, .init(windowBits: 12, lengthBits: 4, threshold: 2))
    }

    func testCompressFilesRouting() throws {
        let spy = try route("""
        { "compressFiles": { "config": {
            "inputFolder": "/project/Source/Raw",
            "outputFolder": "/project/Build/Compressed",
            "format": "lzss",
            "overwrite": true,
            "recursive": true,
            "extensions": ["dat", ".gtx"],
            "outputExtension": "lzss"
        } } }
        """)
        guard case let .compressFiles(config) = try singleOperation(spy) else {
            return XCTFail("Expected compressFiles")
        }
        XCTAssertEqual(config.inputFolder, Folder("/project/Source/Raw"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Build/Compressed"))
        XCTAssertEqual(config.format, .lzss)
        XCTAssertTrue(config.recursive)
        XCTAssertEqual(config.extensions, ["dat", ".gtx"])
        XCTAssertEqual(config.outputExtension, "lzss")
        XCTAssertNil(config.options)
    }

    func testDecompressFilesRouting() throws {
        let spy = try route("""
        { "decompressFiles": { "config": {
            "inputFolder": "/project/Build/Compressed",
            "outputFolder": "/project/Source/Raw",
            "overwrite": true,
            "recursive": false
        } } }
        """)
        guard case let .decompressFiles(config) = try singleOperation(spy) else {
            return XCTFail("Expected decompressFiles")
        }
        XCTAssertEqual(config.inputFolder, Folder("/project/Build/Compressed"))
        XCTAssertEqual(config.outputFolder, Folder("/project/Source/Raw"))
        XCTAssertNil(config.format)
        XCTAssertNil(config.range)
        XCTAssertFalse(config.recursive)
        XCTAssertNil(config.extensions)
    }

    // MARK: - External programs

    func testRunExecutableRouting() throws {
        let spy = try route("""
        { "runExecutable": { "config": {
            "executablePath": "/usr/local/bin/vgmstream-cli",
            "arguments": ["-o", "./Build/bgm.wav", "./Source/bgm.ish"],
            "standardInput": ["yes", "2"],
            "workingDirectory": "/project",
            "outputFile": "/project/Build/vgmstream.log",
            "overwrite": false,
            "failOnNonZeroExit": false
        } } }
        """)
        guard case let .runExecutable(config) = try singleOperation(spy) else {
            return XCTFail("Expected runExecutable")
        }
        XCTAssertEqual(config.executablePath, File("/usr/local/bin/vgmstream-cli"))
        XCTAssertEqual(config.arguments, ["-o", "./Build/bgm.wav", "./Source/bgm.ish"])
        XCTAssertEqual(config.standardInput, ["yes", "2"])
        XCTAssertEqual(config.workingDirectory, Folder("/project"))
        XCTAssertEqual(config.outputFile, File("/project/Build/vgmstream.log"))
        XCTAssertEqual(config.overwrite, false)
        XCTAssertEqual(config.failOnNonZeroExit, false)
    }

    /// Everything but the program itself is optional, and an absent field
    /// stays absent rather than decoding as an empty list — the operation
    /// reads nil as "no arguments" / "no input", so the two must not be
    /// confused with an explicit empty one.
    func testRunExecutableRoutingWithOnlyThePath() throws {
        let spy = try route("""
        { "runExecutable": { "config": { "executablePath": "./tools/patch.sh" } } }
        """)
        guard case let .runExecutable(config) = try singleOperation(spy) else {
            return XCTFail("Expected runExecutable")
        }
        XCTAssertEqual(config.executablePath, File("./tools/patch.sh"))
        XCTAssertNil(config.arguments)
        XCTAssertNil(config.standardInput)
        XCTAssertNil(config.workingDirectory)
        XCTAssertNil(config.outputFile)
        XCTAssertNil(config.overwrite)
        XCTAssertNil(config.failOnNonZeroExit)
    }

    func testRunExecutableRoutingRequiresAPath() {
        XCTAssertThrowsError(try route("""
        { "runExecutable": { "config": { "arguments": ["--help"] } } }
        """))
    }

    // MARK: - Binary patches

    func testCreatePatchRouting() throws {
        let spy = try route("""
        { "createPatch": { "config": {
            "sourceFile": "/project/Original/XD.iso",
            "targetFile": "/project/Build/ISO/XD.iso",
            "patchFile": "/project/Build/XD-hack.ups",
            "format": "ups",
            "overwrite": false
        } } }
        """)
        guard case let .createPatch(config) = try singleOperation(spy) else {
            return XCTFail("Expected createPatch")
        }
        XCTAssertEqual(config.sourceFile, File("/project/Original/XD.iso"))
        XCTAssertEqual(config.targetFile, File("/project/Build/ISO/XD.iso"))
        XCTAssertEqual(config.patchFile, File("/project/Build/XD-hack.ups"))
        XCTAssertEqual(config.format, .ups)
        XCTAssertEqual(config.overwrite, false)
    }

    func testCreatePatchRoutingRequiresAFormat() {
        XCTAssertThrowsError(try route("""
        { "createPatch": { "config": {
            "sourceFile": "/project/a.bin", "targetFile": "/project/b.bin", "patchFile": "/project/p.ups"
        } } }
        """))
    }

    func testCreatePatchRoutingRejectsAnUnknownFormat() {
        // `aps` is a real patch format and not one of the four implemented, so
        // naming it has to fail at decode rather than pick something.
        XCTAssertThrowsError(try route("""
        { "createPatch": { "config": {
            "sourceFile": "/project/a.bin", "targetFile": "/project/b.bin",
            "patchFile": "/project/p.aps", "format": "aps"
        } } }
        """))
    }

    func testApplyPatchRouting() throws {
        let spy = try route("""
        { "applyPatch": { "config": {
            "inputFile": "/project/Original/XD.iso",
            "patchFile": "/project/Patches/XD-hack.ups",
            "outputFile": "/project/Build/ISO/XD.iso",
            "format": "ups",
            "direction": "reverse",
            "ignoreChecksums": true,
            "overwrite": true
        } } }
        """)
        guard case let .applyPatch(config) = try singleOperation(spy) else {
            return XCTFail("Expected applyPatch")
        }
        XCTAssertEqual(config.inputFile, File("/project/Original/XD.iso"))
        XCTAssertEqual(config.patchFile, File("/project/Patches/XD-hack.ups"))
        XCTAssertEqual(config.outputFile, File("/project/Build/ISO/XD.iso"))
        XCTAssertEqual(config.format, .ups)
        XCTAssertEqual(config.direction, .reverse)
        XCTAssertEqual(config.ignoreChecksums, true)
        XCTAssertEqual(config.overwrite, true)
    }

    /// Everything but the three paths is optional, and an absent field stays
    /// absent: the format comes from the patch's magic and the direction from
    /// its checksums, neither of which has a default to decode into.
    func testApplyPatchRoutingWithOnlyThePaths() throws {
        let spy = try route("""
        { "applyPatch": { "config": {
            "inputFile": "/project/in.iso",
            "patchFile": "/project/p.ups",
            "outputFile": "/project/out.iso"
        } } }
        """)
        guard case let .applyPatch(config) = try singleOperation(spy) else {
            return XCTFail("Expected applyPatch")
        }
        XCTAssertNil(config.format)
        XCTAssertNil(config.direction)
        XCTAssertNil(config.ignoreChecksums)
        XCTAssertNil(config.overwrite)
    }

    func testApplyPatchRoutingRejectsAnUnknownDirection() {
        XCTAssertThrowsError(try route("""
        { "applyPatch": { "config": {
            "inputFile": "/project/in.iso", "patchFile": "/project/p.ups",
            "outputFile": "/project/out.iso", "direction": "sideways"
        } } }
        """))
    }
}
