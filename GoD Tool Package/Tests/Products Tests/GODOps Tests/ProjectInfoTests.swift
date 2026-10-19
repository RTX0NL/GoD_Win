//
//  ProjectInfoTests.swift
//  GODOpsTests
//
//  `project_info` tells an MCP client what a project folder is before it
//  touches it: which GODDESS version dumped it, which game, which configs
//  it has and what they would run, and how much is in each folder.
//

import XCTest
import GoDFoundation
@testable import GODOps

final class ProjectInfoTests: XCTestCase {

    private let root = Folder("/games/Colo project")

    private let compress = """
    { "compress": { "config": {
      "inputFile": "./in.bin", "format": "yaz0", "outputFile": "./out.szs", "overwrite": true
    } } }
    """

    private func bytes(_ count: Int, _ text: String = "") -> GoDData {
        let data = GoDData(byteStream: [UInt8](repeating: 0, count: count), byteOrder: .big)
        data.write(text.data(format: .utf8), atAddress: 0)
        return data
    }

    /// A disc project as setup lays it out, small.
    private func discProject(version: String? = "0.1.0") -> InMemoryFST {
        let tree = InMemoryFST()
        if let version {
            writeText(version + "\n", at: root.folder("Engines").file("Version.txt"), in: tree)
        } else {
            writeText("{}", at: root.folder("Engines/XD Engine").file("engine.json"), in: tree)
        }
        try? tree.writeFile(bytes(0x440, "GC6E01"), at: root.file("Build/Contents/sys/boot.bin"), overwrite: true)
        try? tree.writeFile(bytes(2048), at: root.file("Build/ISO/game.iso"), overwrite: true)
        writeText("""
        { "name": "Dump", "rootFolder": "..", "operations": [
          { "operation": \(compress), "enabled": "YES" },
          { "operation": \(compress), "enabled": "NO" },
          { "operation": \(compress), "enabled": "NO" } ] }
        """, at: root.file("Config/Dump-Config.json"), in: tree)
        writeText("""
        { "name": "Off", "rootFolder": "..", "operations": [ { "operation": \(compress), "enabled": "NO" } ] }
        """, at: root.file("Config/Off.json"), in: tree)
        writeText("{ not json", at: root.file("Config/broken.json"), in: tree)
        try? tree.writeFile(bytes(10), at: root.file("dump.log"), overwrite: true)
        return tree
    }

    private func info(_ path: String, in tree: InMemoryFST, toolVersion: String = "0.1.0") throws -> [String] {
        try GODOps.projectInfo(at: File(path), toolVersion: toolVersion, fileSystem: tree)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    func testDescribesADiscProject() throws {
        let lines = try info(root.path, in: discProject())

        XCTAssertEqual(lines.first, "Project: \(root.nativePath)")
        XCTAssertTrue(lines.contains("Kind: disc project, game GC6E01"), "\(lines)")
        XCTAssertTrue(lines.contains("Version: 0.1.0, the same as this server."), "\(lines)")
        XCTAssertTrue(lines.contains("Configs (Config/):"), "\(lines)")
        XCTAssertTrue(lines.contains("  Dump-Config.json: compress (2 disabled)"), "\(lines)")
        XCTAssertTrue(lines.contains("  Off.json: no enabled operations (1 disabled)"), "\(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("  broken.json: does not decode: ") }, "\(lines)")
        XCTAssertTrue(lines.contains("Folders:"), "\(lines)")
        XCTAssertTrue(lines.contains("  (top level): 1 file, 10 B"), "\(lines)")
        XCTAssertTrue(lines.contains("  Build: 2 files, 3.1 KB"), "\(lines)")
        XCTAssertTrue(lines.contains("  Engines: 1 file, 6 B"), "\(lines)")
    }

    func testConfigsAreListedInNameOrder() throws {
        let lines = try info(root.path, in: discProject())
        let configs = lines.filter { $0.hasPrefix("  ") && $0.contains(".json:") }.map { $0.prefix(while: { $0 != ":" }) }
        XCTAssertEqual(configs, ["  Dump-Config.json", "  Off.json", "  broken.json"])
    }

    func testFindsTheProjectFromAPathInsideIt() throws {
        let tree = discProject()
        let fromFile = try info(root.file("Config/Dump-Config.json").path, in: tree)
        let fromFolder = try info(root.folder("Build/Contents").path, in: tree)
        XCTAssertEqual(fromFile.first, "Project: \(root.nativePath)")
        XCTAssertEqual(fromFolder.first, "Project: \(root.nativePath)")
    }

    func testWarnsWhenAnotherVersionDumpedTheProject() throws {
        let lines = try info(root.path, in: discProject(), toolVersion: "0.2.0")
        XCTAssertTrue(lines.contains(
            "Version: 0.1.0, but this server is 0.2.0. Don't run this server's operations on it; "
            + "move it to this version as the server instructions describe."
        ), "\(lines)")
    }

    func testProjectWithoutAVersionStamp() throws {
        let lines = try info(root.path, in: discProject(version: nil))
        XCTAssertTrue(lines.contains(
            "Version: unknown (no Engines/Version.txt). Treat it as dumped by a different GODDESS version."
        ), "\(lines)")
    }

    func testDescribesASaveProject() throws {
        let tree = InMemoryFST()
        let saveRoot = Folder("/saves/own save project")
        writeText("0.1.0", at: saveRoot.file("Engines/Version.txt"), in: tree)
        try tree.writeFile(bytes(0x40, "GXXE01"), at: saveRoot.file("Build/Save/own.gci"), overwrite: true)
        writeText("{}", at: saveRoot.file("Config/Save-Dump-Config.json"), in: tree)

        let lines = try info(saveRoot.path, in: tree)
        XCTAssertTrue(lines.contains("Kind: save project, game GXXE01 (Build/Save/own.gci)"), "\(lines)")
    }

    func testAFolderThatIsNotAProjectIsAnError() {
        let tree = InMemoryFST()
        writeText("hello", at: File("/somewhere/else/file.txt"), in: tree)

        XCTAssertThrowsError(try info("/somewhere/else", in: tree)) { error in
            XCTAssertTrue("\(error)".contains("not inside a GODDESS project"), "\(error)")
        }
    }
}
