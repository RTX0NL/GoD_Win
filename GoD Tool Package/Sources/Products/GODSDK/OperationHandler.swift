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
    func pbrBuild(config: PBROps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func dolDisassembly(config: DolDisassembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func dolAssembly(config: DolAssembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func relDisassembly(config: RelDisassembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func relAssembly(config: RelAssembly.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func commonRelDump(config: CommonRelDump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func commonRelBuild(config: CommonRelBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func relsDump(config: RelsDump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func relsBuild(config: RelsBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func cisoDump(config: CISODump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func cisoBuild(config: CISOBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func gciDump(config: GCIOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func gciBuild(config: GCIOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func xdSaveDump(config: XDSaveOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func xdSaveBuild(config: XDSaveOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func saveSectionsDump(config: SaveSectionsOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func saveSectionsBuild(config: SaveSectionsOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func coloSaveDump(config: ColoSaveOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func coloSaveBuild(config: ColoSaveOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func convert(config: Convert.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func nintendoArchiveDump(config: NintendoArchiveDump.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func nintendoArchiveBuild(config: NintendoArchiveBuild.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func nintendoArchivesDump(config: NintendoArchiveDump.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func nintendoArchivesBuild(config: NintendoArchiveBuild.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func pbrFontDump(config: PBRFontDump.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func pbrFontsDump(config: PBRFontDump.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func pbrFontBuild(config: PBRFontBuild.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func pbrFontsBuild(config: PBRFontBuild.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func pbrStringsDump(config: PBRStringsDump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func pbrStringsBuild(config: PBRStringsBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func compress(config: Compress.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func decompress(config: Decompress.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func compressFiles(config: Compress.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func decompressFiles(config: Decompress.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func runExecutable(config: RunExecutable.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func createPatch(config: CreatePatch.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
    func applyPatch(config: ApplyPatch.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws
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

    func pbrBuild(config: PBROps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try PBROps.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
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

    func relsDump(config: RelsDump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try RelsDump.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func relsBuild(config: RelsBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try RelsBuild.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
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

    func saveSectionsDump(config: SaveSectionsOps.DumpConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try SaveSectionsOps.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func saveSectionsBuild(config: SaveSectionsOps.BuildConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try SaveSectionsOps.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
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

    func nintendoArchiveDump(config: NintendoArchiveDump.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try NintendoArchiveDump.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func nintendoArchiveBuild(config: NintendoArchiveBuild.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try NintendoArchiveBuild.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func nintendoArchivesDump(config: NintendoArchiveDump.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try NintendoArchiveDump.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func nintendoArchivesBuild(config: NintendoArchiveBuild.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try NintendoArchiveBuild.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func pbrFontDump(config: PBRFontDump.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try PBRFontDump.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func pbrFontsDump(config: PBRFontDump.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try PBRFontDump.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func pbrFontBuild(config: PBRFontBuild.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try PBRFontBuild.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func pbrFontsBuild(config: PBRFontBuild.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try PBRFontBuild.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func pbrStringsDump(config: PBRStringsDump.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try PBRStringsDump.dump(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func pbrStringsBuild(config: PBRStringsBuild.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try PBRStringsBuild.build(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func compress(config: Compress.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try Compress.run(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func decompress(config: Decompress.SingleConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try Decompress.run(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func compressFiles(config: Compress.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try Compress.run(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func decompressFiles(config: Decompress.BatchConfig, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try Decompress.run(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func runExecutable(config: RunExecutable.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try RunExecutable.run(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func createPatch(config: CreatePatch.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try CreatePatch.run(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }

    func applyPatch(config: ApplyPatch.Config, settings: GoddessSettings, fileSystem: FileSystemTree, logger: Logger) throws {
        try ApplyPatch.run(config: config, settings: settings, fileSystem: fileSystem, logger: logger)
    }
}
