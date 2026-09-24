import GoDFoundation
import GoDEngine
import GameCube
import GeniusSonority
import Colosseum

extension GCIOps {

    static let manifestFilename = "gci-manifest.json"
    static let cardFolderName = "Card"

    /// Region filenames the Genius Sonority shapes produce. The XD and
    /// Colosseum save operations read these directly, so the names are
    /// part of the contract between the two layers.
    static let slotAFilename    = "slot-a.bin"
    static let slotBFilename    = "slot-b.bin"

    /// Per-slot filenames Colosseum uses (3 slots vs XD's 2).
    static func coloSlotFilename(_ index: Int) -> String { "slot-\(index + 1).bin" }

    static func dump(
        config: DumpConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .dumpGCI(gciFile, outputFolder, overwrite, saveEngine):
                try dumpGCI(
                    gciFile: gciFile,
                    outputFolder: outputFolder,
                    overwrite: overwrite,
                    saveEngineFolder: saveEngine,
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
        saveEngineFolder: Folder?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        logger?.log(.taskStatus(taskName: "Dump GCI", status: .started))
        guard let raw = fileSystem.readFile(at: gciFile)?.allData else {
            throw GCIOpsErrors.inputNotFound(file: gciFile, .init())
        }

        let stem = gciFile.fileName.withoutExtensions
        let parsed = try GCIFile(data: raw, name: stem.isEmpty ? "save" : stem)
        let body = parsed.body

        let (layout, source, integrity) = try resolveLayout(
            header: parsed.header,
            body: body,
            saveEngineFolder: saveEngineFolder,
            fileSystem: fileSystem,
            logger: logger
        )

        // Every region that isn't card metadata is the game's own and is
        // written out untouched.
        for region in layout.gameDataRegions {
            try fileSystem.writeFile(
                try layout.slice(region, from: body),
                at: outputFolder.file(region.binaryFilename),
                overwrite: overwrite
            )
        }

        var card: SaveManifest.Card?
        if let metadataRegion = layout.metadataRegion {
            card = try dumpCardMetadata(
                region: metadataRegion,
                header: parsed.header,
                body: body,
                integrity: integrity,
                outputFolder: outputFolder,
                overwrite: overwrite,
                fileSystem: fileSystem,
                logger: logger
            )
        }

        let manifest = SaveManifest(
            header: parsed.header,
            layoutSource: source,
            regions: layout.regions,
            card: card,
            integrity: integrity
        )
        try fileSystem.encodeJSON(
            manifest, to: outputFolder.file(manifestFilename), overwrite: overwrite
        )

        logger?.log(.info(
            "Split \(parsed.header.gamecode) save body (\(body.length) bytes) into "
            + layout.regions.map(\.name).joined(separator: ", ")
            + " (\(source.rawValue) layout)"
        ))
        logger?.log(.taskStatus(taskName: "Dump GCI", status: .completed(true)))
    }

    // MARK: - Layout

    /// Pick the region list: the engine's declaration when one fits this
    /// save, otherwise the layout derived from the directory entry.
    static func resolveLayout(
        header: GCIFile.Header,
        body: GoDData,
        saveEngineFolder: Folder?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> (CardSaveLayout, SaveManifest.LayoutSource, [CardIntegrityRule]) {
        if let declaration = saveCardDeclaration(
            header: header, folder: saveEngineFolder, fileSystem: fileSystem, logger: logger
        ) {
            if declaration.bodyLength == body.length {
                do {
                    let layout = try CardSaveLayout(
                        regions: declaration.regions, bodyLength: body.length
                    )
                    return (layout, .declared, declaration.integrity)
                } catch {
                    // A declaration that doesn't tile is an engine-data
                    // bug. Say so and carry on generically rather than
                    // failing the whole dump.
                    logger?.log(.warning(
                        "Save region declaration for \(header.gamecode) is unusable, "
                        + "falling back to the derived layout: \(error)"
                    ))
                }
            } else {
                logger?.log(.warning(
                    "\(header.gamecode) declares a \(declaration.bodyLength)-byte save body "
                    + "but this save's is \(body.length); using the derived layout, so the "
                    + "game's own regions will not be split out"
                ))
            }
        }
        return (
            try CardSaveLayout.derived(header: header, bodyLength: body.length),
            .derived,
            []
        )
    }

    /// The save-card shape for this save, from the project's own engine
    /// when a path was configured, else from the default engine for the
    /// gamecode. A game with no declaration gets `nil` and the derived
    /// layout, which is the path every non-Pokémon title takes.
    private static func saveCardDeclaration(
        header: GCIFile.Header,
        folder: Folder?,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) -> GeniusSonorityEngine.Data.SaveCard? {
        if let folder {
            do {
                let engine = try GeniusSonorityEngine(from: folder, in: fileSystem)
                return engine.data.saveCard
            } catch {
                logger?.log(.warning(
                    "Could not load the save engine at \(folder.path): \(error)"
                ))
            }
        }
        guard let game = gsGame(forGamecode: header.gamecode) else { return nil }
        return GeniusSonorityEngine.defaultEngine(for: game).data.saveCard
    }

    /// Which Genius Sonority title a gamecode belongs to, if any.
    static func gsGame(forGamecode gamecode: String) -> GSGame? {
        switch gamecode.prefix(3) {
        case "GXX": return .galeOfDarkness
        case "GC6": return .colosseum
        default: return nil
        }
    }

    // MARK: - Card metadata

    /// Describe the metadata region entirely in artifacts, writing none
    /// of its bytes.
    ///
    /// The rebuild recreates the region from scratch — fill byte, then
    /// images, comments and checksum — so a dump is only valid if every
    /// byte of the region is accounted for by something derivable. This
    /// checks exactly that and refuses the save otherwise, rather than
    /// quietly keeping a copy of the bytes it couldn't explain.
    private static func dumpCardMetadata(
        region: CardSaveLayout.Region,
        header: GCIFile.Header,
        body: GoDData,
        integrity: [CardIntegrityRule],
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> SaveManifest.Card {
        var covered: [Range<Int>] = []

        var images: SaveManifest.Images?
        if let block = try CardImageBlock.decode(body: body, header: header) {
            guard block.verifies(against: body) else {
                throw GCIOpsErrors.imagesNotReproducible(
                    gamecode: header.gamecode,
                    offset: block.layout.offset,
                    length: block.layout.length,
                    .init()
                )
            }
            images = try dumpImages(
                block: block,
                header: header,
                outputFolder: outputFolder,
                overwrite: overwrite,
                fileSystem: fileSystem,
                logger: logger
            )
            covered.append(block.layout.offset..<block.layout.end)
        }

        var comments: SaveManifest.Comments?
        if let decoded = CardComments.decode(body: body, header: header) {
            guard decoded.verifies(against: body, header: header) else {
                throw GCIOpsErrors.commentsNotReproducible(
                    gamecode: header.gamecode,
                    offset: Int(header.commentsAddr),
                    .init()
                )
            }
            comments = .init(
                encoding: decoded.encoding,
                offset: Int(header.commentsAddr),
                title: decoded.title,
                subtitle: decoded.subtitle
            )
            covered.append(
                Int(header.commentsAddr)..<(Int(header.commentsAddr) + CardComments.byteCount)
            )
        }

        // A checksum is re-derived on build, so its stored word counts as
        // accounted for even though nothing writes it here.
        for rule in integrity where rule.storeAt >= region.offset && rule.storeAt + 4 <= region.end {
            covered.append(rule.storeAt..<(rule.storeAt + 4))
        }

        try verifyRemainderIsFill(
            region: region, covered: covered, body: body, header: header
        )

        return .init(images: images, comments: comments)
    }

    /// Every byte of the metadata region that no artifact describes has
    /// to equal the region's fill, because that is all the rebuild will
    /// put there. One that doesn't is a save this tool cannot reproduce,
    /// and saying so is the point — the alternative is a stored copy that
    /// makes the rebuild a patch rather than a derivation.
    private static func verifyRemainderIsFill(
        region: CardSaveLayout.Region,
        covered: [Range<Int>],
        body: GoDData,
        header: GCIFile.Header
    ) throws {
        let bytes = body.rawBytes
        var cursor = region.offset
        var samples: [(offset: Int, value: UInt8)] = []
        var total = 0

        func check(_ from: Int, _ to: Int) {
            for offset in from..<min(to, bytes.count) where bytes[offset] != region.fill {
                total += 1
                if samples.count < 4 { samples.append((offset, bytes[offset])) }
            }
        }

        for range in covered.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            let lower = max(range.lowerBound, region.offset)
            let upper = min(range.upperBound, region.end)
            guard lower < upper else { continue }
            if lower > cursor { check(cursor, lower) }
            cursor = max(cursor, upper)
        }
        if cursor < region.end { check(cursor, region.end) }

        guard total == 0 else {
            throw GCIOpsErrors.metadataNotReproducible(
                gamecode: header.gamecode,
                region: region.name,
                fill: region.fill,
                count: total,
                samples: samples,
                .init()
            )
        }
    }

    private static func dumpImages(
        block: CardImageBlock,
        header: GCIFile.Header,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> SaveManifest.Images {
        let cardFolder = outputFolder.folder(cardFolderName)
        var bannerFile: String?
        var frames: [SaveManifest.Frame] = []
        let artifacts = try block.pngArtifacts()
        for (filename, data) in artifacts.sorted(by: { $0.key < $1.key }) {
            try fileSystem.writeFile(
                data, at: cardFolder.file(filename), overwrite: overwrite
            )
        }
        if block.banner != nil, let filename = CardImageBlock.artifactFilename(for: .banner) {
            bannerFile = "\(cardFolderName)/\(filename)"
        }
        for frame in block.frames {
            guard let filename = CardImageBlock.artifactFilename(
                for: .frame(slot: frame.slot)
            ) else { continue }
            frames.append(.init(
                slot: frame.slot,
                format: frame.format,
                speed: frame.speed,
                videoFrames: frame.speed.videoFrames,
                file: "\(cardFolderName)/\(filename)"
            ))
        }

        let ambiguous = CardImageBlock.frameWalkIsAmbiguous(header: header)
        if ambiguous {
            logger?.log(.warning(
                "This save has a live icon frame after an empty one. Nintendo's own "
                + "library and Dolphin disagree about how many frames that means, so "
                + "the icon may animate differently than it did."
            ))
        }

        return .init(
            bannerFormat: block.bannerFormat,
            animationOrder: block.animationOrder,
            offset: block.layout.offset,
            length: block.layout.length,
            bannerFile: bannerFile,
            frames: frames,
            frameWalkIsAmbiguous: ambiguous ? true : nil
        )
    }
}
