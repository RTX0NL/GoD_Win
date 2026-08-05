import GoDFoundation
import GoDEngine
import Dolphin
import GeniusSonority
import PBR
import Structs

extension PBROps {

    /// Rebuild manifest for the typed `common.fsys` tables. Records, per
    /// table, the files a dump produced and the struct that binds them, so a
    /// future pack can reconstruct each table binary.
    struct CommonTablesRegistry: Codable {
        struct Entry: Codable {
            let name: String
            let fileIndex: Int
            let structName: String?
            let headerFile: String?
            let csvFile: String?
            let leadingExtraFile: String?
            let trailingExtraFile: String?
            let rawFile: String?
        }
        let entries: [Entry]
    }

    static func dump(
        config: DumpConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .dumpPBR(fstFolder, outputFolder, overwrite, _, geniusPath):
                // PBR's FSYS archives are Genius Sonority's format, so the
                // shared unpack pipeline does the work. The engine's
                // `.battleRevolution` routing/naming data (loaded from the
                // project's serialized engine) decides where entries land and
                // names the "(null)"-named entries by archive + index.
                // `fstFolder` is the DATA partition root — it holds
                // `files/GSfsys.toc` and the `.fsys` archives under `files/`.
                let geniusEngine = try GeniusSonorityEngine(from: geniusPath, in: fileSystem)

                let output = try geniusEngine.unpackProject(
                    from: fstFolder,
                    fileSystem: fileSystem,
                    logger: logger
                )

                try fileSystem.importFST(output, from: "/", to: outputFolder, overwrite: overwrite, logger: logger)

            case let .dumpCommonTables(fstFolder, outputFolder, overwrite, japanese, pbrPath, geniusPath):
                try dumpCommonTables(
                    fstFolder: fstFolder, outputFolder: outputFolder, overwrite: overwrite,
                    japanese: japanese, pbrPath: pbrPath, geniusPath: geniusPath,
                    fileSystem: fileSystem, logger: logger
                )
            }
        }
    }

    private static func dumpCommonTables(
        fstFolder: Folder, outputFolder: Folder, overwrite: Bool, japanese: Bool,
        pbrPath: Folder, geniusPath: Folder, fileSystem: FileSystemTree, logger: Logger?
    ) throws {
        let taskName = "Dump PBR common tables"
        logger?.log(.taskStatus(taskName: taskName, status: .started))

        let geniusEngine = try GeniusSonorityEngine(from: geniusPath, in: fileSystem)
        let pbrEngine = try PBREngine(from: pbrPath, in: fileSystem)

        let commonFile = fstFolder.folder("files").file("common.fsys")
        guard let commonData = fileSystem.readFile(at: commonFile)?.allData else {
            throw FSTErrors.fileNotFound(commonFile, .init())
        }
        let archive = try FSYSArchive(data: commonData, engine: geniusEngine)

        var registryEntries = [CommonTablesRegistry.Entry]()

        for table in pbrEngine.data.commonTables {
            guard let entryIndex = japanese ? table.japaneseIndex : table.index,
                  entryIndex < archive.entries.count else { continue }
            let binary = archive.entries[entryIndex].data
            let tableFolder = outputFolder.folder(table.name)

            guard let typed = try pbrEngine.typeCommonTable(table, binary: binary) else {
                // Undocumented layout — keep the raw table binary.
                let rawFile = tableFolder.file(table.name + ".bin")
                try fileSystem.writeFile(binary, at: rawFile, overwrite: overwrite)
                registryEntries.append(.init(
                    name: table.name, fileIndex: entryIndex, structName: nil,
                    headerFile: nil, csvFile: nil, leadingExtraFile: nil,
                    trailingExtraFile: nil, rawFile: rawFile.path
                ))
                continue
            }

            let headerFile = tableFolder.file(table.name + ".header.json")
            try fileSystem.encodeJSON(typed.header, to: headerFile, overwrite: overwrite)

            let csv = try StructTableCSV.encode(entries: typed.entries, definition: typed.entryDefinition)
            let csvFile = tableFolder.file(table.name + ".csv")
            try fileSystem.writeFile(GoDData(byteStream: [UInt8](csv.utf8), byteOrder: .big), at: csvFile, overwrite: overwrite)

            var leadingPath: String?
            if let leading = typed.leadingExtra {
                let f = tableFolder.file(table.name + ".string_pool.bin")
                try fileSystem.writeFile(leading, at: f, overwrite: overwrite)
                leadingPath = f.path
            }
            var trailingPath: String?
            if let trailing = typed.trailingExtra {
                let f = tableFolder.file(table.name + ".name_table.bin")
                try fileSystem.writeFile(trailing, at: f, overwrite: overwrite)
                trailingPath = f.path
            }

            registryEntries.append(.init(
                name: table.name, fileIndex: entryIndex, structName: table.structName,
                headerFile: headerFile.path, csvFile: csvFile.path,
                leadingExtraFile: leadingPath, trailingExtraFile: trailingPath, rawFile: nil
            ))
        }

        let registry = CommonTablesRegistry(entries: registryEntries)
        try fileSystem.encodeJSON(registry, to: outputFolder.file("CommonTables.json"), overwrite: overwrite)

        logger?.log(.info("  Dumped \(registryEntries.count) common tables (\(registryEntries.filter { $0.structName != nil }.count) typed)"))
        logger?.log(.taskStatus(taskName: taskName, status: .completed(true)))
    }
}
