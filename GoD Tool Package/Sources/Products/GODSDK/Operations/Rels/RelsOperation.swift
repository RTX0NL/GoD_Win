import Foundation
import GoDFoundation
import Disassembler

/// Batch REL ops — fan a `RelRouteTable` out into `relDisassembly` /
/// `relAssembly`. Every REL is attempted and the failures are reported
/// together at the end, so one bad module costs its own file rather than the
/// rest of the run.

extension RelsDump {
    static func dump(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let table = try loadRelRouteTable(at: config.routesPath, fileSystem: fileSystem)
        let routes = try table.resolvedRoutes()

        var failures = [String]()
        var dumped = 0
        var absent = [String]()
        var kept = 0

        for route in routes {
            let relPath = config.inputFolder.file(route.path)
            guard fileSystem.inspectFile(at: relPath) != nil else {
                absent.append(route.path)
                continue
            }
            let outputFolder = config.outputFolder.folder(route.sourcePath)
            if !config.overwrite,
               fileSystem.inspectFile(at: outputFolder.file("\(route.stem).rel.json")) != nil {
                kept += 1
                continue
            }
            do {
                // A matcher naming a file that isn't there is a broken
                // table, not an untyped REL — dumping it untyped would hand
                // the user raw chunks with no sign anything was missing.
                let typeMapPath = try route.matcher.typeMap.map {
                    try requireMatcherFile(config.routesEngine.file($0.path), route: route, fileSystem: fileSystem)
                }
                let symbolIndexPath = try route.matcher.symbolIndex.map {
                    try requireMatcherFile(config.routesEngine.file($0.path), route: route, fileSystem: fileSystem)
                }
                try RelDisassembly.disassemble(
                    config: .init(
                        relPath: relPath,
                        outputFolder: outputFolder,
                        dolphinEngine: config.dolphinEngine,
                        symbolIndexPath: symbolIndexPath,
                        dolSymbolMapPath: config.dolSymbolMapPath,
                        typeMapPath: typeMapPath,
                        engines: config.engines ?? [config.routesEngine]
                    ),
                    settings: settings,
                    fileSystem: fileSystem,
                    logger: logger
                )
                dumped += 1
            } catch {
                logger?.log(.error("REL \(route.path) (matcher '\(route.matcherName)'): \(error)"))
                failures.append(route.path)
            }
        }

        // Region differences are expected — JP ships no tableres2.rel — so a
        // route to an absent file isn't fatal. It is still a warning: a route
        // whose path is wrong looks exactly like this, and the generated
        // settings hide anything quieter.
        if !absent.isEmpty {
            logger?.log(.warning("\(absent.count) routed REL(s) aren't in this project: \(absent.joined(separator: ", "))"))
        }
        if kept > 0 {
            logger?.log(.info("\(kept) REL(s) already dumped and left alone (overwrite is off)"))
        }
        let unrouted = unroutedRels(table: table, root: config.inputFolder, fileSystem: fileSystem)
        if !unrouted.isEmpty {
            logger?.log(.warning(
                "\(unrouted.count) REL(s) have no route and weren't dumped: "
                + unrouted.joined(separator: ", ")
            ))
        }
        logger?.log(.info("Dumped \(dumped) of \(routes.count) routed REL(s)"))

        if !failures.isEmpty {
            throw RelsBatchError.failures(verb: "dumped", names: failures, total: routes.count, .init())
        }
    }

    private static func requireMatcherFile(
        _ file: File,
        route: RelRouteTable.Route,
        fileSystem: FileSystemTree
    ) throws -> File {
        guard fileSystem.inspectFile(at: file) != nil else {
            throw RelsBatchError.missingMatcherFile(matcher: route.matcherName, file: file, .init())
        }
        return file
    }

    /// Every `.rel` under the unpacked root that neither a route nor the
    /// table's `ignored` list names. The whole tree is scanned because the
    /// unpack doesn't put every REL in one folder — a map archive's REL lands
    /// in that archive's own folder — and a REL no route names would otherwise
    /// silently drop out of the source tree.
    private static func unroutedRels(
        table: RelRouteTable,
        root: Folder,
        fileSystem: FileSystemTree
    ) -> [String] {
        let known = Set(table.routes.keys).union(table.ignored)
        return fileSystem.scan(root, withExtension: "rel").compactMap { scanned in
            let path = "/" + scanned.relativeFolder.file(scanned.file.fileName).path
                .replacingOccurrences(of: "./", with: "", options: .anchored)
            return known.contains(path) ? nil : path
        }
    }
}

extension RelsBuild {
    static func build(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let table = try loadRelRouteTable(at: config.routesPath, fileSystem: fileSystem)
        let routes = try table.resolvedRoutes()

        var failures = [String]()
        var built = 0

        for route in routes {
            let sourceFolder = config.inputFolder.folder(route.sourcePath)
            // A REL the dump never wrote (absent on this disc, or dumped by
            // a different op) has nothing to rebuild from.
            guard fileSystem.inspectFile(at: sourceFolder.file("\(route.stem).rel.json")) != nil else {
                continue
            }
            do {
                try RelAssembly.assemble(
                    config: .init(
                        inputFolder: sourceFolder,
                        relName: route.stem,
                        outputPath: config.outputFolder.file(route.path),
                        overwrite: config.overwrite,
                        engines: config.engines
                    ),
                    settings: settings,
                    fileSystem: fileSystem,
                    logger: logger
                )
                built += 1
            } catch {
                logger?.log(.error("REL \(route.path): \(error)"))
                failures.append(route.path)
            }
        }

        logger?.log(.info("Built \(built) REL(s) from \(config.inputFolder.path)"))
        if !failures.isEmpty {
            throw RelsBatchError.failures(verb: "built", names: failures, total: built + failures.count, .init())
        }
    }
}

private func loadRelRouteTable(at path: File, fileSystem: FileSystemTree) throws -> RelRouteTable {
    guard let data = fileSystem.readFile(at: path)?.allData else {
        throw RelsBatchError.routesNotFound(file: path, .init())
    }
    do {
        return try JSONDecoder().decode(RelRouteTable.self, from: data.data)
    } catch {
        throw RelsBatchError.invalidRoutes(file: path, underlying: error, .init())
    }
}

enum RelsBatchError: Error, CustomStringConvertible {
    case routesNotFound(file: File, ErrorTrace)
    case invalidRoutes(file: File, underlying: Error, ErrorTrace)
    case missingMatcherFile(matcher: String, file: File, ErrorTrace)
    case failures(verb: String, names: [String], total: Int, ErrorTrace)

    var description: String {
        switch self {
        case let .routesNotFound(file, trace):
            return "REL route table not found: \(file.path)\n\(trace)"
        case let .invalidRoutes(file, underlying, trace):
            return "REL route table at \(file.path) couldn't be read: \(underlying)\n\(trace)"
        case let .missingMatcherFile(matcher, file, trace):
            return "REL matcher '\(matcher)' names \(file.path), which doesn't exist\n\(trace)"
        case let .failures(verb, names, total, trace):
            let listed = names.prefix(8).joined(separator: ", ")
            let rest = names.count > 8 ? ", … (\(names.count - 8) more)" : ""
            return "\(names.count) of \(total) REL(s) couldn't be \(verb): \(listed)\(rest)\n\(trace)"
        }
    }
}
