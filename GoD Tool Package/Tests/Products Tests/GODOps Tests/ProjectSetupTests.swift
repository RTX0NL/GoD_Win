//
//  ProjectSetupTests.swift
//  GODOpsTests
//
//  Coverage for `Project.setup(iso:)`, which generates a whole editing
//  project — folder layout, exported engine definitions, and the Dump/Build
//  config files every later operation is driven by. It had no tests at all,
//  so a change to the generated config shape (or to which engines a game
//  pulls in) could only be caught by running the tool by hand on a real ROM.
//
//  Everything runs against an `InMemoryFST`, so paths are absolute and no
//  disk is touched. The ISO is synthesized: only the first four bytes (the
//  game ID) and the Wii magic actually steer setup, so a small buffer with
//  the right header is enough to exercise per-game branching.
//

import Foundation
import XCTest
import GoDFoundation
import GoDEngine
import GameCube
import Dolphin
import GeniusSonority
import XD
import Colosseum
import Wii
import Disassembler
@testable import GODOps

final class ProjectSetupTests: XCTestCase {

    // MARK: - Fixtures

    /// A disc image whose header carries `gameID`. Setup reads the game ID at
    /// offset 0 and the Wii magic at 0x18; everything else can be zero.
    private func discImage(gameID: String, wii: Bool = false) -> GoDData {
        let data = GoDData(length: 0x50000, byteOrder: .big)
        data.write(gameID.data(format: .utf8), atAddress: 0)
        if wii {
            data.write(UInt32(0x5D1C9EA3).rawData(byteOrder: .big), atAddress: 0x18)
        }
        return data
    }

    /// The version every setup in this file claims to be, so the stamp test
    /// can tell a passed-through value from anything the library might invent.
    private let testToolVersion = "9.8.7"

    /// Runs setup for a game ID and returns the tree plus the project folder.
    private func runSetup(
        gameID: String,
        wii: Bool = false,
        fileName: String = "game.iso"
    ) throws -> (fst: InMemoryFST, project: Folder) {
        let fst = InMemoryFST()
        let input = File("/input/\(fileName)")
        try fst.writeFile(discImage(gameID: gameID, wii: wii), at: input, overwrite: true)
        try Project.setup(iso: input, toolVersion: testToolVersion, fileSystem: fst)
        return (fst, Folder("/input/\(fileName.withoutExtensions) project"))
    }

    private func decodeConfig(_ file: File, in fst: FileSystemTree) throws -> GoddessConfig {
        try fst.decodeJSON(from: file)
    }

    // MARK: - Project shape

    func testSetupCreatesProjectFolderNextToInput() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        XCTAssertEqual(project.path, "/input/game project")
        XCTAssertNotNil(fst.inspectFolder(at: project))
    }

    func testSetupWritesTheStandardTopLevelLayout() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        for folder in ["Build", "Config", "Engines", "Settings", "Scripts"] {
            XCTAssertNotNil(
                fst.inspectFolder(at: project.folder(folder)),
                "expected a \(folder)/ folder in the generated project"
            )
        }
    }

    func testSetupCopiesTheDiscImageIntoBuildISO() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        let copied = fst.readFile(at: project.folder("Build").folder("ISO").file("game.iso"))?.allData
        XCTAssertEqual(copied?.length, 0x50000)
        XCTAssertEqual(copied?.readString(atAddress: 0, format: .utf8, maxCharacters: 4), PokemonXD.gameIDUS)
    }

    func testSetupWritesSettingsAndBothConfigs() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        XCTAssertNotNil(fst.inspectFile(at: project.folder("Settings").file("Settings.json")))
        XCTAssertNotNil(fst.inspectFile(at: project.folder("Config").file("Dump-Config.json")))
        XCTAssertNotNil(fst.inspectFile(at: project.folder("Config").file("Build-Config.json")))
    }

    func testGeneratedConfigsDecodeBackIntoGoddessConfig() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        let dump = try decodeConfig(project.folder("Config").file("Dump-Config.json"), in: fst)
        let build = try decodeConfig(project.folder("Config").file("Build-Config.json"), in: fst)

        XCTAssertEqual(dump.name, "Dump ISO")
        XCTAssertEqual(build.name, "Build ISO")
        XCTAssertFalse(dump.operations.isEmpty)
        XCTAssertFalse(build.operations.isEmpty)
        // Both resolve their root relative to the config file's own folder.
        XCTAssertEqual(dump.rootFolder.path, "..")
        XCTAssertEqual(build.rootFolder.path, "..")
    }

    // MARK: - Per-game engine selection

    private func engineNames(in fst: FileSystemTree, project: Folder) -> Set<String> {
        Set((fst.inspectFolder(at: project.folder("Engines"))?.subFolders ?? []).map(\.folderName))
    }

    func testXDProjectExportsXDAndPokemonEngines() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        let names = engineNames(in: fst, project: project)
        XCTAssertTrue(names.contains("XD Engine"), "got \(names)")
        XCTAssertTrue(names.contains("Pokemon Engine"), "got \(names)")
        XCTAssertTrue(names.contains("GeniusSonority Engine"), "got \(names)")
        XCTAssertTrue(names.contains("Dolphin Engine"), "got \(names)")
        XCTAssertFalse(names.contains("Colosseum Engine"), "got \(names)")
    }

    func testColosseumProjectExportsColosseumEngineNotXD() throws {
        let (fst, project) = try runSetup(gameID: PokemonColosseum.gameIDUS)
        let names = engineNames(in: fst, project: project)
        XCTAssertTrue(names.contains("Colosseum Engine"), "got \(names)")
        XCTAssertFalse(names.contains("XD Engine"), "got \(names)")
    }

    func testNonPokemonGamecubeProjectExportsOnlyBaseEngines() throws {
        let (fst, project) = try runSetup(gameID: "GZZE")
        let names = engineNames(in: fst, project: project)
        XCTAssertTrue(names.contains("Dolphin Engine"), "got \(names)")
        XCTAssertTrue(names.contains("Gamecube Engine"), "got \(names)")
        XCTAssertFalse(names.contains("XD Engine"), "got \(names)")
        XCTAssertFalse(names.contains("Colosseum Engine"), "got \(names)")
        XCTAssertFalse(names.contains("Pokemon Engine"), "got \(names)")
    }

    /// The exported engine folders must be loadable again — that's the whole
    /// point of writing them, and it's what every generated config assumes.
    func testExportedEnginesReloadFromTheProject() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        let engines = project.folder("Engines")
        XCTAssertNoThrow(try DolphinEngine(from: engines.folder("Dolphin Engine"), in: fst))
        XCTAssertNoThrow(try GamecubeEngine(from: engines.folder("Gamecube Engine"), in: fst))
        XCTAssertNoThrow(try XDEngine(from: engines.folder("XD Engine"), in: fst))
        XCTAssertNoThrow(try GeniusSonorityEngine(from: engines.folder("GeniusSonority Engine"), in: fst))
    }

    func testXDProjectShipsItsBundledResources() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        let resources = project.folder("Engines").folder("XD Engine").folder("Resources")
        // Region-neutral bundled defaults plus the region-matched DOL map.
        XCTAssertNotNil(fst.inspectFile(at: resources.file("common_rel_typemap.json")))
        XCTAssertNotNil(fst.inspectFile(at: resources.file("dol_typemap.json")))
        XCTAssertNotNil(fst.inspectFile(at: resources.file("dol.map")),
                        "the region-matched DOL symbol map should be written for a known game ID")
    }

    // MARK: - Generated operation chains

    /// Names the operation cases a config contains, in order.
    private func operationNames(_ config: GoddessConfig) -> [String] {
        config.operations.map { entry in
            let mirror = Mirror(reflecting: entry.operation)
            return mirror.children.first?.label ?? "\(entry.operation)"
        }
    }

    func testXDDumpConfigLeadsWithUnpackAndIncludesTheColoXDDump() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        let dump = try decodeConfig(project.folder("Config").file("Dump-Config.json"), in: fst)
        let names = operationNames(dump)
        XCTAssertEqual(names.first, "gamecubeDump", "got \(names)")
        XCTAssertTrue(names.contains("coloXDDump"), "got \(names)")
        XCTAssertTrue(names.contains("dolDisassembly"), "got \(names)")
    }

    /// Every REL but `common.rel` is dumped and rebuilt by one pair of ops
    /// driven by the game engine's route table, and the table plus every
    /// file its matchers name is installed into the engine folder.
    func testRelStepsFollowTheEnginesRouteTable() throws {
        for gameID in [PokemonXD.gameIDUS, PokemonColosseum.gameIDUS] {
            let (fst, project) = try runSetup(gameID: gameID)
            let dump = try decodeConfig(project.folder("Config").file("Dump-Config.json"), in: fst)
            let build = try decodeConfig(project.folder("Config").file("Build-Config.json"), in: fst)

            let dumps = dump.operations.compactMap { step -> RelsDump.Config? in
                if case .relsDump(let config) = step.operation { return config }
                return nil
            }
            let builds = build.operations.compactMap { step -> RelsBuild.Config? in
                if case .relsBuild(let config) = step.operation { return config }
                return nil
            }
            XCTAssertEqual(dumps.count, 1, gameID)
            XCTAssertEqual(builds.count, 1, gameID)
            XCTAssertFalse(operationNames(dump).contains("relDisassembly"), gameID)

            let dumpConfig = try XCTUnwrap(dumps.first)
            XCTAssertEqual(builds.first?.routesPath, dumpConfig.routesPath)
            XCTAssertEqual(builds.first?.inputFolder, dumpConfig.outputFolder,
                           "the build reads what the dump writes")

            let routesFile = project.file(String(dumpConfig.routesPath.path.dropFirst(2)))
            let table: RelRouteTable = try fst.decodeJSON(from: routesFile)
            XCTAssertNoThrow(try table.resolvedRoutes(), gameID)
            let engineFolder = project.folder(String(dumpConfig.routesEngine.path.dropFirst(2)))
            for file in table.matcherFiles {
                XCTAssertNotNil(fst.inspectFile(at: engineFolder.file(file.path)),
                                "\(gameID): matcher file \(file.path) should be installed")
            }
        }
    }

    /// The route table is per region: each names only what that disc ships,
    /// and the same path can need a different matcher on another build.
    func testEachRegionGetsItsOwnRouteTable() throws {
        func routes(_ gameID: String) throws -> RelRouteTable {
            let (fst, project) = try runSetup(gameID: gameID)
            let file = project.folder("Engines").folder(XDEngine.defaultName).file("Resources/rel_routes.json")
            return try fst.decodeJSON(from: file)
        }
        let us = try routes(PokemonXD.gameIDUS)
        let eu = try routes(PokemonXD.gameIDEU)
        let jp = try routes(PokemonXD.gameIDJP)

        let tableres2 = "/Data/Relocatable Modules/tableres2.rel"
        XCTAssertNotNil(us.routes[tableres2])
        XCTAssertNil(jp.routes[tableres2], "the JP disc has no tableres2.rel")

        // A module is named by the code that reads its tables, not by the
        // symbol maps — US and PAL put `tutorialdata` on a table the code
        // reads as trainer faces — so the same module is named the same way
        // on every disc.
        let toolbattle = "/Data/Relocatable Modules/toolbattle_menu.rel"
        for table in [us, eu, jp] {
            XCTAssertEqual(table.routes[toolbattle], "module_trainer_face_data")
        }

        // Each PAL language copy is routed on its own analysis.
        for language in ["French", "German", "Italian", "Spanish"] {
            XCTAssertEqual(eu.routes["/Data/Relocatable Modules/\(language)/pocket_menu.rel"], "module_shopData", language)
        }
        for table in [us, eu, jp] {
            XCTAssertNoThrow(try table.resolvedRoutes())
        }
    }

    func testXDBuildConfigEndsWithTheGamecubeBuild() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        let build = try decodeConfig(project.folder("Config").file("Build-Config.json"), in: fst)
        let names = operationNames(build)
        XCTAssertEqual(names.last, "gamecubeBuild", "the ISO must be assembled after every asset step; got \(names)")
    }

    /// The DOL rebuild is part of the generated chain on both platforms —
    /// disabled, like the REL rebuilds, and ahead of the disc build that
    /// packs its output. Before this the dump disassembled the DOL but the
    /// build never reassembled it, so an edited `.s` changed nothing.
    func testBuildConfigsCarryADisabledDolAssemblyAheadOfTheDiscBuild() throws {
        let cases: [(gameID: String, wii: Bool, discBuild: String)] = [
            (PokemonXD.gameIDUS, false, "gamecubeBuild"),
            ("RPBE", true, "wiiBuild"),
        ]
        for c in cases {
            let (fst, project) = try runSetup(gameID: c.gameID, wii: c.wii)
            let build = try decodeConfig(project.folder("Config").file("Build-Config.json"), in: fst)
            let names = operationNames(build)
            let dol = try XCTUnwrap(names.firstIndex(of: "dolAssembly"), "\(c.gameID): got \(names)")
            let disc = try XCTUnwrap(names.firstIndex(of: c.discBuild), "\(c.gameID): got \(names)")
            XCTAssertLessThan(dol, disc, "\(c.gameID): the DOL must be rebuilt before the disc is packed")
            XCTAssertEqual(build.operations[dol].enabled, .no, "\(c.gameID): ships disabled until the user opts in")
        }
    }

    func testNonPokemonProjectHasNoGameSpecificOperations() throws {
        let (fst, project) = try runSetup(gameID: "GZZE")
        let dump = try decodeConfig(project.folder("Config").file("Dump-Config.json"), in: fst)
        let names = operationNames(dump)
        XCTAssertFalse(names.contains("coloXDDump"), "got \(names)")
        XCTAssertFalse(names.contains("commonRelDump"), "got \(names)")
    }

    func testWiiProjectUsesTheWiiOperationsAndRequestsACommonKey() throws {
        let (fst, project) = try runSetup(gameID: "RPBE", wii: true)
        let dump = try decodeConfig(project.folder("Config").file("Dump-Config.json"), in: fst)
        let build = try decodeConfig(project.folder("Config").file("Build-Config.json"), in: fst)
        XCTAssertTrue(operationNames(dump).contains("wiiDump"))
        XCTAssertTrue(operationNames(build).contains("wiiBuild"))

        let settings: GoddessSettings = try fst.decodeJSON(from: project.folder("Settings").file("Settings.json"))
        XCTAssertNotNil(settings.wiiCommonKeyFile, "a Wii project needs the common key path filled in")
    }

    func testGamecubeProjectDoesNotRequestAWiiCommonKey() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        let settings: GoddessSettings = try fst.decodeJSON(from: project.folder("Settings").file("Settings.json"))
        XCTAssertNil(settings.wiiCommonKeyFile)
    }

    // MARK: - Game profiles

    /// The profile is the only thing that varies per game, so its engine name
    /// has to be the engine's own — a literal here was how the generated
    /// config and the serialized engine folder drifted apart before.
    func testProfileEngineNamesMatchTheEngines() throws {
        XCTAssertEqual(GameProfile.galeOfDarkness.engineName, try XDEngine.defaults().name)
        XCTAssertEqual(GameProfile.colosseum.engineName, try ColosseumEngine.defaults().name)
    }

    func testProfileLookupCoversEveryRegionOfBothGames() {
        for id in PokemonXD.gameIDs {
            XCTAssertEqual(GameProfile.profile(forGameID: id)?.family, .galeOfDarkness, id)
        }
        for id in PokemonColosseum.gameIDs {
            XCTAssertEqual(GameProfile.profile(forGameID: id)?.family, .colosseum, id)
        }
        XCTAssertNil(GameProfile.profile(forGameID: "GZZE"))
    }

    /// The Wii fill size is engine data, not a literal in the generator.
    func testWiiFillUsesTheEngineDiscCapacity() throws {
        let (fst, project) = try runSetup(gameID: "RPBE", wii: true)
        let build = try decodeConfig(project.folder("Config").file("Build-Config.json"), in: fst)
        let json = try XCTUnwrap(fst.readFile(at: project.folder("Config").file("Build-Config.json"))?.allData)
            .string(format: .utf8)
        let capacity = try WiiEngine.defaults().data.disc.maxDiscCapacity
        XCTAssertTrue(json.contains("\(capacity)"), "expected the engine's disc capacity in the generated config")
        XCTAssertFalse(build.operations.isEmpty)
    }

    // MARK: - Generated launcher scripts

    /// The stamp is how a later GODDESS (or an agent driving it) learns which
    /// version dumped the project, so it has to be the caller's value verbatim
    /// and sit at the top of `/Engines`, not inside any one engine's folder.
    func testSetupStampsTheToolVersionAtTheTopOfEngines() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        let stamp = project.folder("Engines").file(Project.versionStampFileName)
        let contents = try XCTUnwrap(fst.readFile(at: stamp)?.allData)
        XCTAssertEqual(contents.string(format: .utf8), testToolVersion + "\n")
        XCTAssertEqual(Project.versionStampFileName, "Version.txt")
    }

    // MARK: - Colosseum scripts

    /// The chained step ships disabled like every other asset step, but it has
    /// to *be there*: before this, the generated config knew nothing about
    /// scripts, and the only thing that ran them was the audit driver
    /// injecting the operation itself.
    func testColosseumDumpConfigCarriesADisabledScriptStep() throws {
        let (fst, project) = try runSetup(gameID: PokemonColosseum.gameIDUS)
        let dump = try decodeConfig(project.folder("Config").file("Dump-Config.json"), in: fst)
        let steps = dump.operations.compactMap { entry -> ColoXD.DumpConfig.Operations? in
            guard case let .coloXDDump(config) = entry.operation else { return nil }
            return config.operations.first(where: {
                if case .dumpColoScripts = $0.operation { return true }
                return false
            })?.operation
        }
        guard case let .dumpColoScripts(scriptsFolder, outputFolder, _, language, _, _) = steps.first else {
            return XCTFail("Expected a dumpColoScripts step, got \(dump.operations.count) operations")
        }
        XCTAssertEqual(scriptsFolder, Folder("./Build/Unpacked/Assets/Scripts"))
        XCTAssertEqual(outputFolder, Folder("./Source/Scripts"))
        XCTAssertEqual(language, .python)
    }

    func testColosseumBuildConfigCarriesADisabledScriptStep() throws {
        let (fst, project) = try runSetup(gameID: PokemonColosseum.gameIDUS)
        let build = try decodeConfig(project.folder("Config").file("Build-Config.json"), in: fst)
        let steps = build.operations.compactMap { entry -> ColoXD.BuildConfig.Operations? in
            guard case let .coloXDBuild(config) = entry.operation else { return nil }
            return config.operations.first(where: {
                if case .buildColoScripts = $0.operation { return true }
                return false
            })?.operation
        }
        guard case let .buildColoScripts(sourceFolder, outputFolder, _, _, _) = steps.first else {
            return XCTFail("Expected a buildColoScripts step")
        }
        XCTAssertEqual(sourceFolder, Folder("./Source/Scripts"))
        // Back over the unpacked `.scd` files, which is where the FSYS packer
        // reads them from — writing anywhere else rebuilds nothing.
        XCTAssertEqual(outputFolder, Folder("./Build/Unpacked/Assets/Scripts"))
    }

    /// XD's dialect has a parser and an opcode table but no compiler, so an XD
    /// project gets no script step rather than one that throws on every file.
    func testXDProjectHasNoScriptSteps() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        let dump = try decodeConfig(project.folder("Config").file("Dump-Config.json"), in: fst)
        for entry in dump.operations {
            guard case let .coloXDDump(config) = entry.operation else { continue }
            for step in config.operations {
                if case .dumpColoScripts = step.operation {
                    XCTFail("XD project should not carry a Colosseum script step")
                }
            }
        }
        XCTAssertNil(fst.inspectFile(at: project.folder("Config").file("Dump-Scripts-Config.json")))
    }

    /// XD trainer decks get a dump and a build step, disabled like the other
    /// asset steps, reading and writing where the FSYS unpack puts them.
    func testXDConfigsCarryDisabledDeckSteps() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        let dump = try decodeConfig(project.folder("Config").file("Dump-Config.json"), in: fst)
        let dumpSteps = dump.operations.flatMap { entry -> [OperationConfig<ColoXD.DumpConfig.Operations>] in
            guard case let .coloXDDump(config) = entry.operation else { return [] }
            return config.operations.filter { if case .dumpXDDecks = $0.operation { return true }; return false }
        }
        guard case let .dumpXDDecks(decksFolder, outputFolder, _, engines)? = dumpSteps.first?.operation else {
            return XCTFail("Expected a dumpXDDecks step")
        }
        XCTAssertEqual(dumpSteps.first?.enabled, .no)
        XCTAssertEqual(decksFolder, Folder("./Build/Unpacked/Data/Decks"))
        XCTAssertEqual(outputFolder, Folder("./Source/Data/Decks"))
        XCTAssertEqual(engines.first, Folder("./Engines/XD Engine"), "the XD engine's structs come first")

        let build = try decodeConfig(project.folder("Config").file("Build-Config.json"), in: fst)
        let buildSteps = build.operations.flatMap { entry -> [OperationConfig<ColoXD.BuildConfig.Operations>] in
            guard case let .coloXDBuild(config) = entry.operation else { return [] }
            return config.operations.filter { if case .buildXDDecks = $0.operation { return true }; return false }
        }
        guard case let .buildXDDecks(sourceFolder, buildOutput, _, _)? = buildSteps.first?.operation else {
            return XCTFail("Expected a buildXDDecks step")
        }
        XCTAssertEqual(sourceFolder, Folder("./Source/Data/Decks"))
        XCTAssertEqual(buildOutput, Folder("./Build/Unpacked/Data/Decks"))
    }

    /// XD scripts decompile but don't compile, so the dump config carries a
    /// disabled decompile step and the build config nothing for scripts.
    func testXDDumpConfigCarriesADisabledDecompileStep() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        let dump = try decodeConfig(project.folder("Config").file("Dump-Config.json"), in: fst)
        let steps = dump.operations.flatMap { entry -> [OperationConfig<ColoXD.DumpConfig.Operations>] in
            guard case let .coloXDDump(config) = entry.operation else { return [] }
            return config.operations.filter { if case .dumpXDScripts = $0.operation { return true }; return false }
        }
        guard case let .dumpXDScripts(scriptsFolder, outputFolder, _)? = steps.first?.operation else {
            return XCTFail("Expected a dumpXDScripts step")
        }
        XCTAssertEqual(steps.first?.enabled, .no)
        XCTAssertEqual(scriptsFolder, Folder("./Build/Unpacked/Assets/Scripts"))
        XCTAssertEqual(outputFolder, Folder("./Source/Scripts"))
    }

    /// Both games keep MusyX banks: the directories come out of the FSYS
    /// unpack, the `.samp` banks sit loose in the disc's `sound/` folder.
    func testDumpConfigsCarryADisabledMusyXStep() throws {
        for gameID in [PokemonColosseum.gameIDUS, PokemonXD.gameIDUS] {
            let (fst, project) = try runSetup(gameID: gameID)
            let dump = try decodeConfig(project.folder("Config").file("Dump-Config.json"), in: fst)
            let steps = dump.operations.flatMap { entry -> [OperationConfig<ColoXD.DumpConfig.Operations>] in
                guard case let .coloXDDump(config) = entry.operation else { return [] }
                return config.operations.filter { if case .dumpMusyXSamples = $0.operation { return true }; return false }
            }
            guard case let .dumpMusyXSamples(sdirFolder, sampFolder, outputFolder, _)? = steps.first?.operation else {
                return XCTFail("\(gameID): expected a dumpMusyXSamples step")
            }
            XCTAssertEqual(steps.first?.enabled, .no)
            XCTAssertEqual(sdirFolder, Folder("./Build/Unpacked/Assets/Sounds/Sequenced"))
            XCTAssertEqual(sampFolder, Folder("./Build/Contents/files/sound"))
            XCTAssertEqual(outputFolder, Folder("./Source/Audio/MusyX"))
        }
    }

    func testColosseumConfigsCarryNoDeckSteps() throws {
        let (fst, project) = try runSetup(gameID: PokemonColosseum.gameIDUS)
        let dump = try decodeConfig(project.folder("Config").file("Dump-Config.json"), in: fst)
        for entry in dump.operations {
            guard case let .coloXDDump(config) = entry.operation else { continue }
            XCTAssertFalse(config.operations.contains { if case .dumpXDDecks = $0.operation { return true }; return false })
        }
    }

    /// The standalone configs are the runnable half: enabled, overwriting, and
    /// each with a launcher of its own.
    func testColosseumProjectShipsStandaloneScriptConfigs() throws {
        let (fst, project) = try runSetup(gameID: PokemonColosseum.gameIDUS)

        let dump = try decodeConfig(project.folder("Config").file("Dump-Scripts-Config.json"), in: fst)
        guard case let .coloXDDump(dumpInner) = dump.operations.first?.operation,
              case let .dumpColoScripts(_, _, overwrite, language, _, _)
                = dumpInner.operations.enabledEntries.first else {
            return XCTFail("Expected an enabled dumpColoScripts")
        }
        XCTAssertTrue(overwrite, "re-running the dump alone is the point of this config")
        XCTAssertEqual(language, .python)

        let build = try decodeConfig(project.folder("Config").file("Build-Scripts-Config.json"), in: fst)
        guard case let .coloXDBuild(buildInner) = build.operations.first?.operation,
              case .buildColoScripts = buildInner.operations.enabledEntries.first else {
            return XCTFail("Expected an enabled buildColoScripts")
        }

        XCTAssertNotNil(fst.inspectFile(at: project.folder("Scripts").file(launcherName("Dump-Scripts"))))
        XCTAssertNotNil(fst.inspectFile(at: project.folder("Scripts").file(launcherName("Build-Scripts"))))
    }

    func testLauncherScriptsAreWrittenForBothConfigs() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        XCTAssertNotNil(fst.inspectFile(at: project.folder("Scripts").file(launcherName("Dump"))))
        XCTAssertNotNil(fst.inspectFile(at: project.folder("Scripts").file(launcherName("Build"))))
    }

    /// Setup writes `.cmd` launchers on Windows and `.sh` everywhere else.
    private func launcherName(_ stem: String) -> String {
        #if os(Windows)
        return stem + ".cmd"
        #else
        return stem + ".sh"
        #endif
    }

    /// `%` is the one character double quotes don't protect in a batch file.
    func testBatchQuotingSurvivesMetacharacters() {
        let nasty = #"C:\Games\Pokemon XD (USA) & 100%\GODDESS.exe"#
        XCTAssertEqual(
            LauncherScript.batchQuoted(nasty),
            #""C:\Games\Pokemon XD (USA) & 100%%\GODDESS.exe""#
        )
    }

    func testBatchLauncherRunsFromItsOwnDirectory() {
        let body = LauncherScript.batchBody(
            executablePath: #"C:\tools\GODDESS.exe"#,
            configFile: File("/Config/Dump-Config.json")
        )
        XCTAssertTrue(body.hasPrefix("@echo off\r\n"), body)
        XCTAssertTrue(body.contains("cd /d \"%~dp0\" || exit /b 1\r\n"), body)
        XCTAssertTrue(body.contains("Dump-Config.json\"\r\n"), body)
        XCTAssertFalse(body.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "CRLF only")
    }

    /// A launcher has to survive the characters real ROM filenames carry.
    /// Escaping only spaces left `(`, `&` and `'` for the shell to interpret,
    /// so a project made from `Pokemon XD (USA).iso` produced a script that
    /// died on the parentheses.
    func testLauncherQuotingSurvivesShellMetacharacters() {
        let nasty = "/Users/me/Games/Pokemon XD (USA) & 'friends'/GODDESS"
        let quoted = LauncherScript.shellQuoted(nasty)
        XCTAssertEqual(quoted, "'/Users/me/Games/Pokemon XD (USA) & '\\''friends'\\''/GODDESS'")
        // Single quotes are what neutralise the metacharacters, and the only
        // unquoted content is the escape for an embedded quote.
        XCTAssertTrue(quoted.hasPrefix("'"))
        XCTAssertTrue(quoted.hasSuffix("'"))
    }

    /// The config path is relative to `Scripts/`, so the script must move
    /// there first — otherwise `./Scripts/Dump.sh` from the project root
    /// looked for the config one level above the project.
    func testLauncherRunsFromItsOwnDirectory() {
        let body = LauncherScript.body(
            executablePath: "/usr/local/bin/GODDESS",
            configFile: File("/Config/Dump-Config.json")
        )
        XCTAssertTrue(body.contains("cd \"$(dirname \"$0\")\""), body)
        // The config path is written in the host's native spelling.
        #if os(Windows)
        XCTAssertTrue(body.contains(#"'..\Config\Dump-Config.json'"#), body)
        #else
        XCTAssertTrue(body.contains("'../Config/Dump-Config.json'"), body)
        #endif
    }

    // MARK: - Failure modes

    func testSetupThrowsWhenTheInputIsMissing() {
        let fst = InMemoryFST()
        XCTAssertThrowsError(try Project.setup(iso: File("/nope/missing.iso"), toolVersion: testToolVersion, fileSystem: fst))
    }

    /// A `.wia`/`.rvz` image is recognized but not decodable yet; setup must
    /// say so rather than parsing compressed bytes as a raw disc. Both magics
    /// are covered — Dolphin writes "RVZ\u{01}" for the newer variant, and
    /// missing that spelling silently produced a garbage project.
    func testSetupThrowsOnRecognisedButUndecodableImage() throws {
        for magic in ["WIA\u{01}", "RVZ\u{01}"] {
            let fst = InMemoryFST()
            let input = File("/input/game.rvz")
            // `DiscImageFormat.detect` only inspects buffers of at least
            // 0x400 bytes, so the fixture has to clear that bar.
            let data = GoDData(length: 0x400, byteOrder: .big)
            data.write(GoDData(byteStream: Array(magic.utf8), byteOrder: .big), atAddress: 0)
            try fst.writeFile(data, at: input, overwrite: true)
            XCTAssertThrowsError(
                try Project.setup(iso: input, toolVersion: testToolVersion, fileSystem: fst),
                "\(magic) should be recognized as an undecodable compressed image"
            )
        }
    }
}
