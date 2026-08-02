import GoDFoundation
import GameCube
import GeniusSonority
import Colosseum

extension GCIOps {

    static func build(
        config: BuildConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .buildGCI(inputFolder, gciFile, overwrite):
                try buildGCI(
                    inputFolder: inputFolder,
                    gciFile: gciFile,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )
            }
        }
    }

    private static func buildGCI(
        inputFolder: Folder,
        gciFile: File,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        logger?.log(.taskStatus(taskName: "Build GCI", status: .started))

        let manifestPath = inputFolder.file(manifestFilename)
        let header: GCIFile.Header = try fileSystem.decodeJSON(from: manifestPath)

        let body: GoDData
        if isXDSaveShape(header: header) {
            guard
                let banner = fileSystem.readFile(at: inputFolder.file(bannerFilename))?.allData,
                let header0 = fileSystem.readFile(at: inputFolder.file(header0Filename))?.allData,
                let header1 = fileSystem.readFile(at: inputFolder.file(header1Filename))?.allData,
                let slotA = fileSystem.readFile(at: inputFolder.file(slotAFilename))?.allData,
                let slotB = fileSystem.readFile(at: inputFolder.file(slotBFilename))?.allData
            else {
                throw GCIOpsErrors.missingRegion(folder: inputFolder, .init())
            }
            let card = GSSaveCardFile(
                banner: banner,
                header0: header0,
                header1: header1,
                slotA: slotA,
                slotB: slotB
            )
            body = try card.assembledBody()
        } else if isColoSaveShape(header: header) {
            guard let preamble = fileSystem.readFile(at: inputFolder.file(preambleFilename))?.allData else {
                throw GCIOpsErrors.missingRegion(folder: inputFolder, .init())
            }
            var slots: [GoDData] = []
            for i in 0..<ColoSaveCardFile.slotCount {
                guard let slot = fileSystem.readFile(at: inputFolder.file(coloSlotFilename(i)))?.allData else {
                    throw GCIOpsErrors.missingRegion(folder: inputFolder, .init())
                }
                slots.append(slot)
            }
            body = try ColoSaveCardFile(preamble: preamble, slots: slots).assembledBody()
        } else {
            guard let raw = fileSystem.readFile(at: inputFolder.file(bodyFilename))?.allData else {
                throw GCIOpsErrors.missingRegion(folder: inputFolder, .init())
            }
            body = raw
        }

        let stem = gciFile.fileName.withoutExtensions
        let gci = GCIFile(name: stem.isEmpty ? "save" : stem, header: header, body: body)
        let assembled = try gci.assembled()

        try fileSystem.writeFile(assembled, at: gciFile, overwrite: overwrite)
        logger?.log(.info("Wrote \(assembled.length) bytes to \(gciFile.path)"))
        logger?.log(.taskStatus(taskName: "Build GCI", status: .completed(true)))
    }
}
