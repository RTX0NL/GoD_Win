import GoDFoundation
import GoDEngine
import Dolphin
import GeniusSonority
import PBR
import Structs

extension PBROps {

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

            case let .dumpCommonTables(unpackedFolder, overwrite, japanese, pbrPath, engines):
                try dumpCommonTables(
                    unpackedFolder: unpackedFolder, overwrite: overwrite,
                    japanese: japanese, pbrPath: pbrPath, engines: engines,
                    fileSystem: fileSystem, logger: logger
                )
            }
        }
    }

    /// Types the raw `common.fsys` `.bin` entries an unpack produced into
    /// header JSON + row CSV, and rewrites the archive's registry so each
    /// typed entry carries its reassembly metadata (struct names + files)
    /// directly — no separate manifest. The raw `.bin` is removed.
    private static func dumpCommonTables(
        unpackedFolder: Folder, overwrite: Bool, japanese: Bool,
        pbrPath: Folder, engines: [Folder]?, fileSystem: FileSystemTree, logger: Logger?
    ) throws {
        let taskName = "Dump PBR common tables"
        logger?.log(.taskStatus(taskName: taskName, status: .started))

        let pbrEngine = try PBREngine(from: pbrPath, in: fileSystem)
        let format = pbrEngine.data.commonTableFormat

        // Entry structs resolve against PBR's definitions first, then any
        // engine the config adds — a struct naming a species/move/item enum
        // needs the Pokemon engine in the list, since `getStruct` only ever
        // consults one engine's own enums.
        let structEngine = try GenericEngine(combining: [pbrPath] + (engines ?? []), in: fileSystem)

        let registryFile = unpackedFolder.folder("Archives").file("common.fsys.json")
        let registry: FSYSRegistry = try fileSystem.decodeJSON(from: registryFile)
        // Registry paths are rooted at the unpack root (e.g. `/Data/Common/…`),
        // matching the entries the FSYS unpack wrote; disk writes prefix the
        // real `unpackedFolder`.
        let commonRoot = Folder("/Data/Common")
        func write(_ data: GoDData, to rooted: File) throws {
            try fileSystem.writeFile(data, at: unpackedFolder.file(rooted.path), overwrite: overwrite)
        }

        var newEntries = [FSYSRegistry.Entry]()
        var typedCount = 0
        var demotedCount = 0

        for (index, entry) in registry.entries.enumerated() {
            // Registry entries are in archive order, so the entry index is the
            // common.fsys file index the table descriptors are keyed on.
            guard let table = pbrEngine.commonTable(fileIndex: index, japanese: japanese),
                  table.structName != nil,
                  let binData = fileSystem.readFile(at: unpackedFolder.file(entry.file.path))?.allData else {
                newEntries.append(entry)
                continue
            }

            // A table this build lays out differently keeps its raw `.bin`
            // rather than aborting the dump. One undocumented table used to
            // cost every table after it plus the operations chained behind
            // this one — the JP disc types 7 of 32 before `Countries` throws.
            // Decode *and* serialize before touching the tree, so a table
            // that fails halfway leaves no partial artifacts behind.
            let decoded: (typed: PBREngine.TypedCommonTable, csv: String)?
            do {
                guard let typed = try pbrEngine.typeCommonTable(table, binary: binData, structs: structEngine) else {
                    newEntries.append(entry)
                    continue
                }
                decoded = (typed, try StructTableCSV.encode(
                    entries: typed.entries, definition: typed.entryDefinition
                ))
            } catch {
                logger?.log(.warning(
                    "common.fsys table '\(table.name)' (index \(index)) didn't type: \(error) "
                    + "Keeping it as a raw binary entry."
                ))
                demotedCount += 1
                newEntries.append(entry)
                continue
            }
            guard let (typed, csv) = decoded else {
                newEntries.append(entry)
                continue
            }

            // The packer leaves filler in the records' alignment gaps and a
            // CSV has no column for it, so the fills are measured and carried
            // in the registry for the repack to write back. No round-trip
            // check: a struct that describes this table badly produces a CSV
            // anyway, and the repack differing is what reports it. `measure`
            // returns nil when a declared padding run varies from row to row —
            // which means it is an unnamed live field, not padding — and that
            // now shows up as a table that rebuilds with zeroes there.
            let paddingFills = StructPaddingFill.measure(
                in: typed.entries, definition: typed.entryDefinition
            ) ?? []

            let tableFolder = commonRoot.folder(table.name)
            let headerFile = tableFolder.file(table.name + ".header.json")
            try fileSystem.encodeJSON(typed.header, to: unpackedFolder.file(headerFile.path), overwrite: overwrite)

            let csvFile = tableFolder.file(table.name + ".csv")
            try write(GoDData(byteStream: [UInt8](csv.utf8), byteOrder: .big), to: csvFile)

            var leadingFile: File?
            if let leading = typed.leadingExtra {
                let f = tableFolder.file(table.name + ".string_pool.bin")
                try write(leading, to: f)
                leadingFile = f
            }
            var trailingFile: File?
            if let trailing = typed.trailingExtra {
                let f = tableFolder.file(table.name + ".name_table.bin")
                try write(trailing, to: f)
                trailingFile = f
            }

            // Replace the raw table binary with the typed files.
            try? fileSystem.deleteFile(at: unpackedFolder.file(entry.file.path))

            newEntries.append(FSYSRegistry.Entry(
                metadata: entry.metadata,
                file: csvFile,
                dataTable: .init(
                    tableName: table.name,
                    entryStructName: typed.entryDefinition.name,
                    headerStructName: format.headerStructName,
                    headerFile: headerFile,
                    leadingExtraFile: leadingFile,
                    trailingExtraFile: trailingFile,
                    entryPaddingFills: paddingFills
                )
            ))
            typedCount += 1
        }

        let updated = FSYSRegistry(groupID: registry.groupID, metaData: registry.metaData, entries: newEntries)
        try fileSystem.encodeJSON(updated, to: registryFile, overwrite: true)

        // deck.fsys: same treatment, keyed by entry file type (no extras).
        let deckRegistryFile = unpackedFolder.folder("Archives").file("deck.fsys.json")
        var deckCount = 0
        if let deckRegistry: FSYSRegistry = try? fileSystem.decodeJSON(from: deckRegistryFile) {
            var deckEntries = [FSYSRegistry.Entry]()
            for entry in deckRegistry.entries {
                guard let fileType = entry.metadata.fileType,
                      let deck = pbrEngine.deckTable(forType: fileType),
                      let binData = fileSystem.readFile(at: unpackedFolder.file(entry.file.path))?.allData else {
                    deckEntries.append(entry)
                    continue
                }
                // Same policy as common.fsys: an undecodable deck keeps its
                // raw `.bin` instead of failing the whole dump.
                let decoded: (typed: (header: StructData, entries: [StructData], entryDefinition: StructDefinition), csv: String)
                do {
                    let typed = try pbrEngine.typeDeckTable(deck, binary: binData, structs: structEngine)
                    decoded = (typed, try StructTableCSV.encode(
                        entries: typed.entries, definition: typed.entryDefinition
                    ))
                } catch {
                    logger?.log(.warning(
                        "deck.fsys table '\(deck.fileType)' didn't type: \(error) "
                        + "Keeping it as a raw binary entry."
                    ))
                    demotedCount += 1
                    deckEntries.append(entry)
                    continue
                }
                let (typed, csv) = decoded
                // Same policy as the common tables: measure the filler the CSV
                // can't carry, and don't check the round trip.
                let paddingFills = StructPaddingFill.measure(
                    in: typed.entries, definition: typed.entryDefinition
                ) ?? []
                // Typed files sit next to the raw bin, sharing its base name.
                let stem = entry.file.path.withoutExtensions
                let headerFile = File(stem + ".header.json")
                let csvFile = File(stem + ".csv")
                try fileSystem.encodeJSON(typed.header, to: unpackedFolder.file(headerFile.path), overwrite: overwrite)
                try write(GoDData(byteStream: [UInt8](csv.utf8), byteOrder: .big), to: csvFile)
                try? fileSystem.deleteFile(at: unpackedFolder.file(entry.file.path))

                deckEntries.append(FSYSRegistry.Entry(
                    metadata: entry.metadata,
                    file: csvFile,
                    dataTable: .init(
                        tableName: deck.fileType,
                        entryStructName: typed.entryDefinition.name,
                        headerStructName: pbrEngine.data.deckHeaderStructName,
                        headerFile: headerFile,
                        leadingExtraFile: nil,
                        trailingExtraFile: nil,
                        entryPaddingFills: paddingFills
                    )
                ))
                deckCount += 1
            }
            let updatedDecks = FSYSRegistry(groupID: deckRegistry.groupID, metaData: deckRegistry.metaData, entries: deckEntries)
            try fileSystem.encodeJSON(updatedDecks, to: deckRegistryFile, overwrite: true)
        }

        logger?.log(.info("  Typed \(typedCount) common.fsys + \(deckCount) deck.fsys data tables"))
        if demotedCount > 0 {
            logger?.log(.warning(
                "  \(demotedCount) table\(demotedCount == 1 ? "" : "s") kept as raw binary "
                + "because the struct didn't match this build."
            ))
        }
        logger?.log(.taskStatus(taskName: taskName, status: .completed(true)))
    }
}
