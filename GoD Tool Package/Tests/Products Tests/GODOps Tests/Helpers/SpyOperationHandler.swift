//
//  SpyOperationHandler.swift
//  GODOpsTests
//
//  Records every operation the dispatcher routes to it, so tests can assert
//  that a config file produced the right operations, in order, with the right
//  decoded parameters. Each call is stored as the `GoddessConfig.Operations`
//  case it arrived through, alongside the settings it was given.
//

import Foundation
import GoDFoundation
@testable import GODOps

final class SpyOperationHandler: OperationHandler {
    struct Call {
        let operation: GoddessConfig.Operations
        let settings: GoddessSettings
    }

    private(set) var calls: [Call] = []

    /// When set, every handled operation throws this error after recording.
    var errorToThrow: Error?

    /// When set, runs after recording with the tree the operation was given,
    /// standing in for the operation's own work, writes included.
    var work: ((FileSystemTree) throws -> Void)?

    private func record(_ operation: GoddessConfig.Operations, _ settings: GoddessSettings, _ fileSystem: FileSystemTree) throws {
        calls.append(Call(operation: operation, settings: settings))
        if let error = errorToThrow { throw error }
        try work?(fileSystem)
    }

    func gamecubeDump(config: Gamecube.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.gamecubeDump(config: config), settings, fileSystem)
    }

    func gamecubeBuild(config: Gamecube.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.gamecubeBuild(config: config), settings, fileSystem)
    }

    func wiiDump(config: WiiOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.wiiDump(config: config), settings, fileSystem)
    }

    func wiiBuild(config: WiiOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.wiiBuild(config: config), settings, fileSystem)
    }

    func coloXDDump(config: ColoXD.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.coloXDDump(config: config), settings, fileSystem)
    }

    func coloXDBuild(config: ColoXD.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.coloXDBuild(config: config), settings, fileSystem)
    }

    func pbrDump(config: PBROps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.pbrDump(config: config), settings, fileSystem)
    }

    func pbrBuild(config: PBROps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.pbrBuild(config: config), settings, fileSystem)
    }

    func dolDisassembly(config: DolDisassembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.dolDisassembly(config: config), settings, fileSystem)
    }

    func dolAssembly(config: DolAssembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.dolAssembly(config: config), settings, fileSystem)
    }

    func relDisassembly(config: RelDisassembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.relDisassembly(config: config), settings, fileSystem)
    }

    func relAssembly(config: RelAssembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.relAssembly(config: config), settings, fileSystem)
    }

    func commonRelDump(config: CommonRelDump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.commonRelDump(config: config), settings, fileSystem)
    }

    func commonRelBuild(config: CommonRelBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.commonRelBuild(config: config), settings, fileSystem)
    }

    func relsDump(config: RelsDump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.relsDump(config: config), settings, fileSystem)
    }

    func relsBuild(config: RelsBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.relsBuild(config: config), settings, fileSystem)
    }

    func cisoDump(config: CISODump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.cisoDump(config: config), settings, fileSystem)
    }

    func cisoBuild(config: CISOBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.cisoBuild(config: config), settings, fileSystem)
    }

    func rvzDump(config: RVZDump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.rvzDump(config: config), settings, fileSystem)
    }

    func nkitDump(config: NKitDump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.nkitDump(config: config), settings, fileSystem)
    }

    func nkitBuild(config: NKitBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.nkitBuild(config: config), settings, fileSystem)
    }

    func gciDump(config: GCIOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.gciDump(config: config), settings, fileSystem)
    }

    func gciBuild(config: GCIOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.gciBuild(config: config), settings, fileSystem)
    }

    func xdSaveDump(config: XDSaveOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.xdSaveDump(config: config), settings, fileSystem)
    }

    func saveSectionsDump(config: SaveSectionsOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.saveSectionsDump(config: config), settings, fileSystem)
    }

    func saveSectionsBuild(config: SaveSectionsOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.saveSectionsBuild(config: config), settings, fileSystem)
    }

    func xdSaveBuild(config: XDSaveOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.xdSaveBuild(config: config), settings, fileSystem)
    }

    func coloSaveDump(config: ColoSaveOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.coloSaveDump(config: config), settings, fileSystem)
    }

    func coloSaveBuild(config: ColoSaveOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.coloSaveBuild(config: config), settings, fileSystem)
    }

    func nintendoArchiveDump(config: NintendoArchiveDump.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.nintendoArchiveDump(config: config), settings, fileSystem)
    }

    func nintendoArchiveBuild(config: NintendoArchiveBuild.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.nintendoArchiveBuild(config: config), settings, fileSystem)
    }

    func nintendoArchivesDump(config: NintendoArchiveDump.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.nintendoArchivesDump(config: config), settings, fileSystem)
    }

    func nintendoArchivesBuild(config: NintendoArchiveBuild.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.nintendoArchivesBuild(config: config), settings, fileSystem)
    }


    func pbrFontDump(config: PBRFontDump.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.pbrFontDump(config: config), settings, fileSystem)
    }

    func pbrFontsDump(config: PBRFontDump.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.pbrFontsDump(config: config), settings, fileSystem)
    }

    func pbrFontBuild(config: PBRFontBuild.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.pbrFontBuild(config: config), settings, fileSystem)
    }

    func pbrFontsBuild(config: PBRFontBuild.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.pbrFontsBuild(config: config), settings, fileSystem)
    }

    func pbrStringsDump(config: PBRStringsDump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.pbrStringsDump(config: config), settings, fileSystem)
    }

    func pbrStringsBuild(config: PBRStringsBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.pbrStringsBuild(config: config), settings, fileSystem)
    }

    func convert(config: Convert.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.convert(config: config), settings, fileSystem)
    }

    func compress(config: Compress.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.compress(config: config), settings, fileSystem)
    }

    func decompress(config: Decompress.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.decompress(config: config), settings, fileSystem)
    }

    func compressFiles(config: Compress.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.compressFiles(config: config), settings, fileSystem)
    }

    func decompressFiles(config: Decompress.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.decompressFiles(config: config), settings, fileSystem)
    }

    func runExecutable(config: RunExecutable.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.runExecutable(config: config), settings, fileSystem)
    }

    func createPatch(config: CreatePatch.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.createPatch(config: config), settings, fileSystem)
    }

    func applyPatch(config: ApplyPatch.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.applyPatch(config: config), settings, fileSystem)
    }
}

/// Logger that swallows everything — keeps test output clean.
final class SilentLogger: Logger {
    func log(_ category: Log) {}
}

/// Logger that records every entry for assertions on warnings/errors.
final class RecordingLogger: Logger {
    private(set) var entries: [Log] = []
    func log(_ category: Log) { entries.append(category) }

    var warnings: [String] {
        entries.compactMap { if case .warning(let message) = $0 { return message } else { return nil } }
    }

    var errors: [String] {
        entries.compactMap { if case .error(let message) = $0 { return message } else { return nil } }
    }
}
