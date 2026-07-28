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

    /// Runs setup for a game ID and returns the tree plus the project folder.
    private func runSetup(
        gameID: String,
        wii: Bool = false,
        fileName: String = "game.iso"
    ) throws -> (fst: InMemoryFST, project: Folder) {
        let fst = InMemoryFST()
        let input = File("/input/\(fileName)")
        try fst.writeFile(discImage(gameID: gameID, wii: wii), at: input, overwrite: true)
        try Project.setup(iso: input, fileSystem: fst)
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
        let copied = fst.readFile(at: project.folder("Build").folder("ISO").file("game.iso"))
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

    func testXDBuildConfigEndsWithTheGamecubeBuild() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        let build = try decodeConfig(project.folder("Config").file("Build-Config.json"), in: fst)
        let names = operationNames(build)
        XCTAssertEqual(names.last, "gamecubeBuild", "the ISO must be assembled after every asset step; got \(names)")
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

    /// XD's map filters come from `XDEngine.Data.unusedColosseumMapPrefixes`;
    /// the prefixes used to be repeated as a literal in the generated config.
    func testXDMapPlansUseTheEnginesUnusedPrefixList() {
        let expected = XDEngine.Data().unusedColosseumMapPrefixes
        let filters = GameProfile.galeOfDarkness.mapPlans.map(\.filter)
        XCTAssertEqual(filters, [.excludePrefixes(expected), .onlyPrefixes(expected)])
    }

    /// The Wii fill size is engine data, not a literal in the generator.
    func testWiiFillUsesTheEngineDiscCapacity() throws {
        let (fst, project) = try runSetup(gameID: "RPBE", wii: true)
        let build = try decodeConfig(project.folder("Config").file("Build-Config.json"), in: fst)
        let json = try XCTUnwrap(fst.readFile(at: project.folder("Config").file("Build-Config.json")))
            .string(format: .utf8)
        let capacity = try WiiEngine.defaults().data.disc.maxDiscCapacity
        XCTAssertTrue(json.contains("\(capacity)"), "expected the engine's disc capacity in the generated config")
        XCTAssertFalse(build.operations.isEmpty)
    }

    // MARK: - Generated launcher scripts

    func testLauncherScriptsAreWrittenForBothConfigs() throws {
        let (fst, project) = try runSetup(gameID: PokemonXD.gameIDUS)
        XCTAssertNotNil(fst.inspectFile(at: project.folder("Scripts").file("Dump.sh")))
        XCTAssertNotNil(fst.inspectFile(at: project.folder("Scripts").file("Build.sh")))
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
        XCTAssertTrue(body.contains("'../Config/Dump-Config.json'"), body)
    }

    // MARK: - Failure modes

    func testSetupThrowsWhenTheInputIsMissing() {
        let fst = InMemoryFST()
        XCTAssertThrowsError(try Project.setup(iso: File("/nope/missing.iso"), fileSystem: fst))
    }

    /// A `.wia`/`.rvz` image is recognised but not decodable yet; setup must
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
                try Project.setup(iso: input, fileSystem: fst),
                "\(magic) should be recognised as an undecodable compressed image"
            )
        }
    }
}
