//
//  FixtureFile.swift
//
//  The catalog of generated golden fixtures. Each format contributes a
//  deterministic model builder plus the frozen files derived from it; the
//  `FixtureGen` executable (`swift run FixtureGen`) writes them into the
//  test targets' `Fixtures/` folders, and `--check` verifies the committed
//  files still match the catalog (CI drift guard).
//
//  Hand-authored goldens (e.g. `msg_minimal.*`) are deliberately NOT in
//  the catalog: they are independent ground truth and must never be
//  overwritten by the tool's own writers.
//

import Foundation

/// One generated fixture: where it lives (relative to the package root)
/// and the exact bytes it must contain.
public struct FixtureFile {
    public let relativePath: String
    public let bytes: [UInt8]

    public init(relativePath: String, bytes: [UInt8]) {
        self.relativePath = relativePath
        self.bytes = bytes
    }
}

/// Fixture folder for each test target, relative to the package root.
public enum FixtureDir {
    public static let colosseum = "Tests/Shared Tests/Engine Tests/Colosseum Tests/Fixtures"
    public static let dolphin = "Tests/Shared Tests/Engine Tests/Dolphin Tests/Fixtures"
    public static let gamecube = "Tests/Shared Tests/Engine Tests/GameCube Tests/Fixtures"
    public static let foundation = "Tests/Shared Tests/Dependency Tests/GoD Foundation Tests/Fixtures"
    public static let disassembler = "Tests/Shared Tests/Dependency Tests/Disassembler Tests/Fixtures"
}

public enum FixtureCatalog {
    /// Every generated fixture, across all formats.
    public static func allFixtures() throws -> [FixtureFile] {
        var files: [FixtureFile] = []
        files += try RELFixtures.files()
        files += try GTXFixtures.files()
        files += try GCIFixtures.files()
        files += try THPFixtures.files()
        files += try GSWFixtures.files()
        files += try GSFontFixtures.files()
        files += try ISFFixtures.files()
        files += try ATXFixtures.files()
        files += try FSYSFixtures.files()
        files += try FsysTOCFixtures.files()
        files += LZSSFixtures.files()
        files += NintendoCompressionFixtures.files()
        files += SectionLayoutFixtures.files()
        return files
    }
}
