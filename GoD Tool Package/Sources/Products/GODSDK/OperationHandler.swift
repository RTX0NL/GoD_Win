//
//  OperationHandler.swift
//  GODOps
//
//  The routing seam between the dispatch switch and the engine operations.
//  `GODOps.run` decodes configs and switches on the operation case, but every
//  case lands on a handler method rather than an engine call directly. The
//  production handler (`EngineOperationHandler`) forwards to the engine
//  operation wrappers; tests inject a recording handler to verify that config
//  files route to the right operation with the right parameters.
//

import Foundation
import GoDFoundation

protocol OperationHandler {
    func gamecubeDump(config: Gamecube.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func gamecubeBuild(config: Gamecube.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func wiiDump(config: WiiOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func wiiBuild(config: WiiOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func coloXDDump(config: ColoXD.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func coloXDBuild(config: ColoXD.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func pbrDump(config: PBROps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func dolDisassembly(config: DolDisassembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func dolAssembly(config: DolAssembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func relDisassembly(config: RelDisassembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func relAssembly(config: RelAssembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func commonRelDump(config: CommonRelDump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func commonRelBuild(config: CommonRelBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func mapRelDump(config: MapRelDump.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func mapRelBuild(config: MapRelBuild.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func mapRelsDump(config: MapRelDump.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func mapRelsBuild(config: MapRelBuild.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func cisoDump(config: CISODump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func cisoBuild(config: CISOBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func gciDump(config: GCIOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func gciBuild(config: GCIOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func xdSaveDump(config: XDSaveOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func xdSaveBuild(config: XDSaveOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func coloSaveDump(config: ColoSaveOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func coloSaveBuild(config: ColoSaveOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func convert(config: Convert.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
}

/// Production handler: forwards each operation to its engine wrapper.
struct EngineOperationHandler: OperationHandler {
    func gamecubeDump(config: Gamecube.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try Gamecube.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func gamecubeBuild(config: Gamecube.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try Gamecube.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func wiiDump(config: WiiOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try WiiOps.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func wiiBuild(config: WiiOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try WiiOps.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func coloXDDump(config: ColoXD.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try ColoXD.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func coloXDBuild(config: ColoXD.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try ColoXD.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func pbrDump(config: PBROps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try PBROps.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func dolDisassembly(config: DolDisassembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try DolDisassembly.disassemble(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func dolAssembly(config: DolAssembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try DolAssembly.assemble(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func relDisassembly(config: RelDisassembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try RelDisassembly.disassemble(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func relAssembly(config: RelAssembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try RelAssembly.assemble(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func commonRelDump(config: CommonRelDump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try CommonRelDump.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func commonRelBuild(config: CommonRelBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try CommonRelBuild.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func mapRelDump(config: MapRelDump.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try MapRelDump.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func mapRelBuild(config: MapRelBuild.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try MapRelBuild.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func mapRelsDump(config: MapRelDump.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try MapRelDump.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func mapRelsBuild(config: MapRelBuild.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try MapRelBuild.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func cisoDump(config: CISODump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try CISODump.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func cisoBuild(config: CISOBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try CISOBuild.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func gciDump(config: GCIOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try GCIOps.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func gciBuild(config: GCIOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try GCIOps.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func xdSaveDump(config: XDSaveOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try XDSaveOps.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func xdSaveBuild(config: XDSaveOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try XDSaveOps.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func coloSaveDump(config: ColoSaveOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try ColoSaveOps.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func coloSaveBuild(config: ColoSaveOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try ColoSaveOps.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func convert(config: Convert.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try Convert.run(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }
}
