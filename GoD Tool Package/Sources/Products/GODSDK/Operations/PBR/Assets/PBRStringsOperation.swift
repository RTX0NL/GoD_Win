//
//  PBRStringsOperation.swift
//  GODOps
//
//  Battle Revolution's strings <-> one editable document.
//
//  The dump reads the `.msg` binaries the FSYS unpack already wrote and the
//  `common.fsys` member holding the string directory, and writes a single
//  `PBRStringCatalog`. The build reverses it, rewriting those same loose
//  binaries. Neither touches an archive: `packPBR` remains the only thing
//  that writes `.fsys` files, so a strings build slots in ahead of it the
//  same way the font build does.
//
//  The directory is never edited directly and never dumped as data — it is
//  re-derived from the catalogue's row order every build. That is what lets
//  a string be inserted anywhere without shifting what an id means.
//

import Foundation
import GoDFoundation
import PBR

enum PBRStringsErrors: Error, CustomStringConvertible {
    case pathOutsideUnpackedFolder(File, Folder)
    case noStringTables(Folder)
    case missingTarget(String)
    case targetIsNotAStringTable(String)
    case targetMismatch(path: String, expectedTable: Int, expectedLanguage: String,
                        foundTable: Int, foundLanguage: String)

    var description: String {
        switch self {
        case let .pathOutsideUnpackedFolder(file, folder):
            return "Error: \(file.path) is not inside the unpacked folder \(folder.path), so it "
                + "can't be referenced from the strings document."
        case let .noStringTables(folder):
            return "Error: no PBR string tables (MESG) found under \(folder.path)."
        case let .missingTarget(path):
            return "Error: the strings document names \(path), which isn't in the unpacked folder."
        case let .targetIsNotAStringTable(path):
            return "Error: \(path) is not a PBR string table (no 'MESG' magic)."
        case let .targetMismatch(path, expectedTable, expectedLanguage, foundTable, foundLanguage):
            return "Error: \(path) holds table \(foundTable) (\(foundLanguage)), but the strings "
                + "document lists it under table \(expectedTable) (\(expectedLanguage))."
        }
    }
}

/// A path inside the unpack root, as the document stores it.
private func relativePath(of file: File, in root: Folder) throws -> String {
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard file.path.hasPrefix(rootPath) else {
        throw PBRStringsErrors.pathOutsideUnpackedFolder(file, root)
    }
    return String(file.path.dropFirst(rootPath.count))
}

extension PBRStringsDump {

    static func dump(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let taskName = "Dump PBR strings"
        logger?.log(.taskStatus(taskName: taskName, status: .started))

        // Parse every MESG binary under the messages folder. Anything else
        // that wandered in is skipped rather than fatal — the folder is a
        // dump target, not a curated input.
        var sources = [(path: String, table: PBRStringTable)]()
        for scanned in fileSystem.scan(config.messagesFolder, matches: { _ in true }) {
            guard let data = fileSystem.readFile(at: scanned.file),
                  PBRStringTable.isStringTable(data)
            else { continue }
            do {
                let table = try PBRStringTable(binary: data)
                sources.append((try relativePath(of: scanned.file, in: config.unpackedFolder), table))
            } catch {
                logger?.log(.warning("\(scanned.file.path): \(error)"))
            }
        }
        guard !sources.isEmpty else {
            throw PBRStringsErrors.noStringTables(config.messagesFolder)
        }

        guard let directoryData = fileSystem.readFile(at: config.directoryFile) else {
            throw FSTErrors.fileNotFound(config.directoryFile, .init())
        }
        let directory = try PBRStringDirectory(binary: directoryData)

        let catalogue = try PBRStringCatalog.make(
            directory: directory,
            directoryPath: try relativePath(of: config.directoryFile, in: config.unpackedFolder),
            tables: tableSources(from: sources, logger: logger)
        )
        try fileSystem.writeJSON(catalogue, at: config.outputFile, overwrite: config.overwrite)

        let strings = catalogue.tables.reduce(0) { $0 + $1.strings.count }
        logger?.log(.info("Wrote \(strings) string(s) across \(catalogue.tables.count) table(s) "
                          + "and \(sources.count) file(s) to \(config.outputFile.path)"))
        logger?.log(.taskStatus(taskName: taskName, status: .completed(true)))
    }

    /// Groups the parsed binaries by table and language.
    ///
    /// A table ships once per language, and two of them ship a second
    /// byte-identical copy in another archive — so a language maps to a
    /// list of paths, all written from the same strings.
    private static func tableSources(
        from sources: [(path: String, table: PBRStringTable)],
        logger: Logger?
    ) -> [PBRStringCatalog.TableSource] {
        let order = PBREngine.Data().stringLanguageCodes
        func rank(_ code: String) -> Int { order.firstIndex(of: code) ?? order.count }

        let byTable = Dictionary(grouping: sources) { $0.table.tableID }
        return byTable.keys.sorted().map { tableID in
            let copies = byTable[tableID] ?? []
            let byLanguage = Dictionary(grouping: copies) { $0.table.languageCode }
            let codes = byLanguage.keys.sorted {
                rank($0) == rank($1) ? $0 < $1 : rank($0) < rank($1)
            }
            let languages = codes.map { code -> PBRStringCatalog.LanguageSource in
                let forLanguage = (byLanguage[code] ?? []).sorted { $0.path < $1.path }
                if forLanguage.count > 1 {
                    logger?.log(.info("Table \(tableID) \(code) ships \(forLanguage.count) copies: "
                                      + forLanguage.map(\.path).joined(separator: ", ")))
                }
                return .init(
                    code: code,
                    paths: forLanguage.map(\.path),
                    table: forLanguage[0].table
                )
            }
            return .init(tableID: tableID, languages: languages)
        }
    }
}

extension PBRStringsBuild {

    static func build(
        config: Config,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        let taskName = "Build PBR strings"
        logger?.log(.taskStatus(taskName: taskName, status: .started))

        let catalogue: PBRStringCatalog = try fileSystem.decodeJSON(from: config.stringsFile)
        let resolution = try catalogue.resolve()

        var written = 0
        for table in resolution.tables {
            for language in table.languages {
                for path in language.paths {
                    let file = config.unpackedFolder.file(path)
                    // Read the target first: it carries the one header field
                    // the document doesn't (the id high-bits word), and it
                    // says which table and language it is, so writing over
                    // the wrong file is caught rather than shipped.
                    guard let existing = fileSystem.readFile(at: file) else {
                        throw PBRStringsErrors.missingTarget(path)
                    }
                    guard PBRStringTable.isStringTable(existing) else {
                        throw PBRStringsErrors.targetIsNotAStringTable(path)
                    }
                    let current = try PBRStringTable(binary: existing)
                    guard current.tableID == table.tableID,
                          current.languageCode == language.code
                    else {
                        throw PBRStringsErrors.targetMismatch(
                            path: path,
                            expectedTable: table.tableID,
                            expectedLanguage: language.code,
                            foundTable: current.tableID,
                            foundLanguage: current.languageCode
                        )
                    }
                    let rebuilt = PBRStringTable(
                        tableID: table.tableID,
                        languageCode: language.code,
                        idHighBits: current.idHighBits,
                        strings: language.strings
                    )
                    try fileSystem.writeFile(
                        try rebuilt.rawData(), at: file, overwrite: config.overwrite
                    )
                    written += 1
                }
            }
        }

        let directoryFile = config.unpackedFolder.file(resolution.directoryPath)
        guard fileSystem.readFile(at: directoryFile) != nil else {
            throw PBRStringsErrors.missingTarget(resolution.directoryPath)
        }
        try fileSystem.writeFile(
            resolution.directory.rawData(), at: directoryFile, overwrite: config.overwrite
        )

        logger?.log(.info("Wrote \(resolution.directory.records.count) string id(s) across "
                          + "\(written) file(s), and the directory"))
        logger?.log(.taskStatus(taskName: taskName, status: .completed(true)))
    }
}
