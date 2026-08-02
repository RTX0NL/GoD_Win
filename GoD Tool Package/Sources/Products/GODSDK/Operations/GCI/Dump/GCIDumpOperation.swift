import GoDFoundation
import GameCube
import GeniusSonority
import Colosseum

extension GCIOps {

    static let manifestFilename = "gci-manifest.json"
    static let bannerFilename   = "banner.bin"
    static let header0Filename  = "header0.bin"
    static let header1Filename  = "header1.bin"
    static let slotAFilename    = "slot-a.bin"
    static let slotBFilename    = "slot-b.bin"
    static let preambleFilename = "preamble.bin"
    static let bodyFilename     = "body.bin"

    /// Per-slot filenames Colo uses (3 slots vs XD's 2).
    static func coloSlotFilename(_ index: Int) -> String { "slot-\(index + 1).bin" }

    static func dump(
        config: DumpConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .dumpGCI(gciFile, outputFolder, overwrite):
                try dumpGCI(
                    gciFile: gciFile,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    fileSystem: fileSystem,
                    logger: logger
                )
            }
        }
    }

    private static func dumpGCI(
        gciFile: File,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        logger?.log(.taskStatus(taskName: "Dump GCI", status: .started))
        guard let raw = fileSystem.readFile(at: gciFile)?.allData else {
            throw GCIOpsErrors.inputNotFound(file: gciFile, .init())
        }

        let stem = gciFile.fileName.withoutExtensions
        let parsed = try GCIFile(data: raw, name: stem.isEmpty ? "save" : stem)

        try fileSystem.encodeJSON(
            parsed.header,
            to: outputFolder.file(manifestFilename),
            overwrite: overwrite
        )

        // XD vs Colo dispatch — the on-card layouts are different
        // shapes (XD: 0x56000 / banner+2hdrs+2slots; Colo: 0x60000 /
        // 0x6000 preamble+3slots). Detect by gamecode prefix.
        let prefix = parsed.header.gamecode.prefix(3)
        let bodySize = Int(parsed.header.blockCount) * GCIFile.blockSize
        switch (prefix, bodySize) {
        case ("GXX", GSSaveCardFile.bodySize):
            let card = try GSSaveCardFile(body: parsed.body)
            try fileSystem.writeFile(card.banner, at: outputFolder.file(bannerFilename), overwrite: overwrite)
            try fileSystem.writeFile(card.header0, at: outputFolder.file(header0Filename), overwrite: overwrite)
            try fileSystem.writeFile(card.header1, at: outputFolder.file(header1Filename), overwrite: overwrite)
            try fileSystem.writeFile(card.slotA, at: outputFolder.file(slotAFilename), overwrite: overwrite)
            try fileSystem.writeFile(card.slotB, at: outputFolder.file(slotBFilename), overwrite: overwrite)
            logger?.log(.info("Split XD GCI body (\(parsed.body.length) bytes) into banner + 2 hdrs + 2 slots"))

        case ("GC6", ColoSaveCardFile.bodySize):
            let card = try ColoSaveCardFile(body: parsed.body)
            try fileSystem.writeFile(card.preamble, at: outputFolder.file(preambleFilename), overwrite: overwrite)
            for (i, slot) in card.slots.enumerated() {
                try fileSystem.writeFile(slot, at: outputFolder.file(coloSlotFilename(i)), overwrite: overwrite)
            }
            logger?.log(.info("Split Colo GCI body (\(parsed.body.length) bytes) into preamble + 3 slots"))

        default:
            try fileSystem.writeFile(parsed.body, at: outputFolder.file(bodyFilename), overwrite: overwrite)
            logger?.log(.info("GCI gamecode '\(parsed.header.gamecode)' is not a known XD/Colo shape — dumped body unsplit"))
        }

        logger?.log(.taskStatus(taskName: "Dump GCI", status: .completed(true)))
    }

    /// True when the GCI looks like a Pokémon XD save. Used by
    /// downstream ops (e.g. project setup) to decide whether to wire
    /// up XD-specific dump steps.
    static func isXDSaveShape(header: GCIFile.Header) -> Bool {
        let bodySize = Int(header.blockCount) * GCIFile.blockSize
        return header.gamecode.hasPrefix("GXX") && bodySize == GSSaveCardFile.bodySize
    }

    /// True when the GCI looks like a Pokémon Colosseum save.
    static func isColoSaveShape(header: GCIFile.Header) -> Bool {
        let bodySize = Int(header.blockCount) * GCIFile.blockSize
        return header.gamecode.hasPrefix("GC6") && bodySize == ColoSaveCardFile.bodySize
    }
}
