//
//  Dispatch.swift
//  GODOps
//
//  The single dispatch surface shared by the GODDESS CLI and the MCP server.
//  Both drive the tool through these entry points rather than re-implementing
//  the file-type switch. Everything here is a thin wrapper over the engine
//  operations, mirroring the tool's philosophy: operations map config values
//  to engine calls and nothing more.
//
//  Keeping the facade path/Data-based lets `GoddessConfig`, the `Operations`
//  enum, and every per-operation config type stay internal to this module —
//  the executable and the MCP layer only touch the small surface below.
//

import Foundation
import GoDFoundation
import GameCube
import Dolphin
import Wii
import GeniusSonority

public enum GODOps {

    public enum DispatchError: Error, CustomStringConvertible {
        case unsupportedFileType(String, File)

        public var description: String {
            switch self {
            case let .unsupportedFileType(ext, file):
                return "Unsupported file type '\(ext)' for file \(file.path)"
            }
        }
    }

    /// Process one input file the way the CLI does, dispatching on its
    /// extension: disc images and GCIs create projects, `.fsys` unpacks in
    /// place, `.json` runs a config's enabled operations in order.
    public static func process(inputFile: File, logger: Logger? = nil) throws {
        guard let fileType = inputFile.fileType else { return }
        switch fileType {
        case "iso", "gcm", "ciso", "wbfs", "wia", "rvz":
            try setupProject(discImage: inputFile)
        case "gci":
            try setupSaveProject(gci: inputFile)
        case "fsys":
            try unpackFSYS(inputFile)
        case "json":
            try runConfig(at: inputFile, logger: logger)
        default:
            throw DispatchError.unsupportedFileType(fileType, inputFile)
        }
    }

    // MARK: - Project setup

    /// Set up an editing project from a GameCube/Wii disc image (raw or
    /// CISO/NKit; `.wia`/`.rvz` recognized but not yet decodable).
    public static func setupProject(discImage: File) throws {
        try Project.setup(iso: discImage)
    }

    /// Set up a save-editing project from a `.gci` memory-card save.
    public static func setupSaveProject(gci: File) throws {
        try Project.setup(gci: gci)
    }

    /// Unpack a standalone `.fsys` archive next to the input file.
    public static func unpackFSYS(_ file: File) throws {
        try Project.unpack(fsys: file)
    }

    // MARK: - Config execution

    /// Decode a `.json` config and run its enabled operations in order.
    public static func runConfig(
        at file: File,
        fileSystem: FileSystem = FileSystem.shared,
        logger: Logger? = nil
    ) throws {
        try runConfig(
            at: file,
            fileSystem: StreamedFileSystem(fileSystem),
            logger: logger,
            handler: EngineOperationHandler()
        )
    }

    /// Testable seam: same as `runConfig` but over an injected tree and
    /// operation handler.
    ///
    /// The tree is a `StreamedFileSystem` because operations that open a disc
    /// image need one and dispatch is where that choice belongs — deciding it
    /// here means no operation has to probe at runtime for what it was handed.
    /// Wrapping an in-memory tree (`StreamedFileSystem(materializing:)`) is how
    /// tests opt out; reads then materialize, which is all they can do anyway.
    static func runConfig(
        at file: File,
        fileSystem: StreamedFileSystem,
        logger: Logger?,
        handler: OperationHandler
    ) throws {
        let config = try GoddessConfig.decodeFromFile(file, fileSystem: fileSystem)
        try run(config, fileSystem: fileSystem, logger: logger, handler: handler)
    }

    /// Run a single operation supplied as JSON — either an `OperationConfig`
    /// wrapper or a bare operation object — using default or supplied
    /// settings. The MCP "run one step" escape hatch.
    public static func runOperation(
        json: Data,
        settingsJSON: Data? = nil,
        fileSystem: FileSystem = FileSystem.shared,
        logger: Logger? = nil
    ) throws {
        try runOperation(
            json: json,
            settingsJSON: settingsJSON,
            fileSystem: StreamedFileSystem(fileSystem),
            logger: logger,
            handler: EngineOperationHandler()
        )
    }

    /// Testable seam for `runOperation` with an injectable handler.
    static func runOperation(
        json: Data,
        settingsJSON: Data?,
        fileSystem: StreamedFileSystem,
        logger: Logger?,
        handler: OperationHandler
    ) throws {
        let operation = try decodeOperation(json: json)
        let settings = try settingsJSON.map {
            try JSONDecoder().decode(GoddessSettings.self, from: $0)
        } ?? GoddessSettings.default
        let log = logger ?? PrintLogger(verbose: settings.verbose)
        try run(operation: operation, settings: settings, fileSystem: fileSystem, logger: log, handler: handler)
    }

    // MARK: - Internals

    static func run(
        _ config: GoddessConfig,
        fileSystem: StreamedFileSystem,
        logger: Logger?,
        handler: OperationHandler
    ) throws {
        fileSystem.changeDirectory(config.rootFolder)
        let settings: GoddessSettings = (try? config.settingsFile.flatMap { file in
            try fileSystem.decodeJSON(from: file)
        }) ?? GoddessSettings.default

        let log = logger ?? PrintLogger(verbose: settings.verbose)

        let enabledOps = config.operations.enabledEntries
        for (index, operation) in enabledOps.enumerated() {
            fileSystem.changeDirectory(config.rootFolder)
            try run(operation: operation, settings: settings, fileSystem: fileSystem, logger: log, handler: handler)
            log.log(.info("Operation \(index + 1)/\(enabledOps.count) completed"))
        }
    }

    static func run(
        operation: GoddessConfig.Operations,
        settings: GoddessSettings,
        fileSystem: StreamedFileSystem,
        logger: Logger,
        handler: OperationHandler
    ) throws {
        switch operation {
        case .gamecubeDump(let dumpConfig):
            // The only operation that starts by opening a disc image, and so
            // the only one that takes the streamed tree rather than any tree.
            try handler.gamecubeDump(config: dumpConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .gamecubeBuild(let buildConfig):
            try handler.gamecubeBuild(config: buildConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .wiiDump(let dumpConfig):
            try handler.wiiDump(config: dumpConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .wiiBuild(let buildConfig):
            try handler.wiiBuild(config: buildConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .coloXDDump(let dumpConfig):
            try handler.coloXDDump(config: dumpConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .coloXDBuild(let buildConfig):
            try handler.coloXDBuild(config: buildConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .pbrDump(let dumpConfig):
            try handler.pbrDump(config: dumpConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .pbrBuild(let buildConfig):
            try handler.pbrBuild(config: buildConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .dolDisassembly(let disasmConfig):
            try handler.dolDisassembly(config: disasmConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .dolAssembly(let asmConfig):
            try handler.dolAssembly(config: asmConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .relDisassembly(let relConfig):
            try handler.relDisassembly(config: relConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .relAssembly(let relConfig):
            try handler.relAssembly(config: relConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .commonRelDump(let cfg):
            try handler.commonRelDump(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
        case .commonRelBuild(let cfg):
            try handler.commonRelBuild(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
        case .mapRelDump(let cfg):
            try handler.mapRelDump(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
        case .mapRelBuild(let cfg):
            try handler.mapRelBuild(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
        case .mapRelsDump(let cfg):
            try handler.mapRelsDump(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
        case .mapRelsBuild(let cfg):
            try handler.mapRelsBuild(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
        case .cisoDump(let cisoConfig):
            try handler.cisoDump(config: cisoConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .cisoBuild(let cisoConfig):
            try handler.cisoBuild(config: cisoConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .gciDump(let gciConfig):
            try handler.gciDump(config: gciConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .gciBuild(let gciConfig):
            try handler.gciBuild(config: gciConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .xdSaveDump(let xdConfig):
            try handler.xdSaveDump(config: xdConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .xdSaveBuild(let xdConfig):
            try handler.xdSaveBuild(config: xdConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .coloSaveDump(let coloConfig):
            try handler.coloSaveDump(config: coloConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .coloSaveBuild(let coloConfig):
            try handler.coloSaveBuild(config: coloConfig, settings: settings, fileSystem: fileSystem, logger: logger)
        case .convert(let convertConfig):
            try handler.convert(config: convertConfig, settings: settings, fileSystem: fileSystem, logger: logger)

        case .nintendoArchiveDump(let cfg):
            try handler.nintendoArchiveDump(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)

        case .nintendoArchiveBuild(let cfg):
            try handler.nintendoArchiveBuild(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)

        case .nintendoArchivesDump(let cfg):
            try handler.nintendoArchivesDump(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)

        case .nintendoArchivesBuild(let cfg):
            try handler.nintendoArchivesBuild(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
        case .pbrFontDump(let cfg):
            try handler.pbrFontDump(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
        case .pbrFontsDump(let cfg):
            try handler.pbrFontsDump(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
        case .pbrFontBuild(let cfg):
            try handler.pbrFontBuild(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
        case .pbrFontsBuild(let cfg):
            try handler.pbrFontsBuild(config: cfg, settings: settings, fileSystem: fileSystem, logger: logger)
        }
    }

    /// Decode either an `OperationConfig<Operations>` wrapper or a bare
    /// `Operations` object into a runnable operation.
    private static func decodeOperation(json: Data) throws -> GoddessConfig.Operations {
        let decoder = JSONDecoder()
        if let wrapped = try? decoder.decode(OperationConfig<GoddessConfig.Operations>.self, from: json) {
            return wrapped.operation
        }
        return try decoder.decode(GoddessConfig.Operations.self, from: json)
    }
}
