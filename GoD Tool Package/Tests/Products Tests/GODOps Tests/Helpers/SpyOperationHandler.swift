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

    private func record(_ operation: GoddessConfig.Operations, _ settings: GoddessSettings) throws {
        calls.append(Call(operation: operation, settings: settings))
        if let error = errorToThrow { throw error }
    }

    func gamecubeDump(config: Gamecube.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.gamecubeDump(config: config), settings)
    }

    func gamecubeBuild(config: Gamecube.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.gamecubeBuild(config: config), settings)
    }

    func wiiDump(config: WiiOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.wiiDump(config: config), settings)
    }

    func wiiBuild(config: WiiOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.wiiBuild(config: config), settings)
    }

    func coloXDDump(config: ColoXD.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.coloXDDump(config: config), settings)
    }

    func coloXDBuild(config: ColoXD.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.coloXDBuild(config: config), settings)
    }

    func pbrDump(config: PBROps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.pbrDump(config: config), settings)
    }

    func dolDisassembly(config: DolDisassembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.dolDisassembly(config: config), settings)
    }

    func dolAssembly(config: DolAssembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.dolAssembly(config: config), settings)
    }

    func relDisassembly(config: RelDisassembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.relDisassembly(config: config), settings)
    }

    func relAssembly(config: RelAssembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.relAssembly(config: config), settings)
    }

    func commonRelDump(config: CommonRelDump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.commonRelDump(config: config), settings)
    }

    func commonRelBuild(config: CommonRelBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.commonRelBuild(config: config), settings)
    }

    func mapRelDump(config: MapRelDump.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.mapRelDump(config: config), settings)
    }

    func mapRelBuild(config: MapRelBuild.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.mapRelBuild(config: config), settings)
    }

    func mapRelsDump(config: MapRelDump.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.mapRelsDump(config: config), settings)
    }

    func mapRelsBuild(config: MapRelBuild.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.mapRelsBuild(config: config), settings)
    }

    func cisoDump(config: CISODump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.cisoDump(config: config), settings)
    }

    func cisoBuild(config: CISOBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.cisoBuild(config: config), settings)
    }

    func gciDump(config: GCIOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.gciDump(config: config), settings)
    }

    func gciBuild(config: GCIOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.gciBuild(config: config), settings)
    }

    func xdSaveDump(config: XDSaveOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.xdSaveDump(config: config), settings)
    }

    func xdSaveBuild(config: XDSaveOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.xdSaveBuild(config: config), settings)
    }

    func coloSaveDump(config: ColoSaveOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.coloSaveDump(config: config), settings)
    }

    func coloSaveBuild(config: ColoSaveOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.coloSaveBuild(config: config), settings)
    }

    func nintendoArchiveDump(config: NintendoArchiveDump.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.nintendoArchiveDump(config: config), settings)
    }

    func nintendoArchiveBuild(config: NintendoArchiveBuild.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.nintendoArchiveBuild(config: config), settings)
    }

    func nintendoArchivesDump(config: NintendoArchiveDump.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.nintendoArchivesDump(config: config), settings)
    }

    func nintendoArchivesBuild(config: NintendoArchiveBuild.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.nintendoArchivesBuild(config: config), settings)
    }

    func convert(config: Convert.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try record(.convert(config: config), settings)
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
}
