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
        guard fileSystem.itemExists(at: manifestPath) else {
            throw GCIOpsErrors.missingManifest(file: manifestPath, .init())
        }
        let manifest: SaveManifest = try fileSystem.decodeJSON(from: manifestPath)

        let bodyLength = Int(manifest.header.blockCount) * GCIFile.blockSize
        let layout = try manifest.layout(bodyLength: bodyLength)

        let metadataRegion = layout.metadataRegion
        var regionBytes: [String: GoDData] = [:]
        for region in layout.regions where region.name != metadataRegion?.name {
            let path = inputFolder.file(region.binaryFilename)
            guard let bytes = fileSystem.readFile(at: path)?.allData else {
                throw GCIOpsErrors.missingRegion(
                    folder: inputFolder, name: region.binaryFilename, .init()
                )
            }
            regionBytes[region.name] = bytes
        }

        // The metadata region is built from scratch out of its artifacts.
        // It has no file of its own, so there is nothing to read back and
        // nothing of the old save to carry forward.
        if let metadataRegion, let card = manifest.card {
            regionBytes[metadataRegion.name] = try rebuildCardMetadata(
                region: metadataRegion,
                card: card,
                header: manifest.header,
                inputFolder: inputFolder,
                fileSystem: fileSystem,
                logger: logger
            )
        } else if let metadataRegion {
            // A metadata region the manifest says nothing about is all
            // fill, which is the right answer for a save that declares no
            // banner, icon or comments.
            regionBytes[metadataRegion.name] = GoDData(
                byteStream: [UInt8](repeating: metadataRegion.fill, count: metadataRegion.length),
                byteOrder: .big
            )
        }

        let body = try layout.assembled(regionBytes: regionBytes)

        // Any checksum the game keeps over its own metadata is recomputed
        // last, over the assembled body. An edited banner or comment
        // changes bytes these cover, so replaying the dumped value would
        // hand the game a save it rejects.
        for rule in manifest.integrity {
            try rule.apply(to: body)
        }
        if !manifest.integrity.isEmpty {
            logger?.log(.info("Applied \(manifest.integrity.count) save integrity rule(s)"))
        }

        let stem = gciFile.fileName.withoutExtensions
        let gci = GCIFile(name: stem.isEmpty ? "save" : stem, header: manifest.header, body: body)
        let assembled = try gci.assembled()

        try fileSystem.writeFile(assembled, at: gciFile, overwrite: overwrite)
        logger?.log(.info("Wrote \(assembled.length) bytes to \(gciFile.path)"))
        logger?.log(.taskStatus(taskName: "Build GCI", status: .completed(true)))
    }

    /// Build the metadata region from scratch.
    ///
    /// Fill the whole region with its declared fill byte, then write the
    /// images and the comments over it. Nothing is copied from the save
    /// that was dumped: the dump refused to proceed unless every byte
    /// outside those artifacts equalled the fill, so filling reproduces
    /// them. Any checksum is applied later, over the assembled body.
    private static func rebuildCardMetadata(
        region: CardSaveLayout.Region,
        card: SaveManifest.Card,
        header: GCIFile.Header,
        inputFolder: Folder,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws -> GoDData {
        let rebuilt = GoDData(
            byteStream: [UInt8](repeating: region.fill, count: region.length),
            byteOrder: .big
        )

        if let images = card.images {
            guard let layout = CardImageBlock.layout(header: header) else {
                throw GCIOpsErrors.imageLayoutUnavailable(.init())
            }
            var pngData: [String: GoDData] = [:]
            for entry in imageArtifactPaths(images: images) {
                let path = inputFolder.file(entry.path)
                guard let data = fileSystem.readFile(at: path)?.allData else {
                    throw GCIOpsErrors.missingArtifact(file: path, .init())
                }
                pngData[entry.filename] = data
            }
            let block = try CardImageBlock.fromArtifacts(layout: layout, pngData: pngData)
            let encoded = try block.encoded()
            guard layout.offset >= region.offset, layout.end <= region.end else {
                throw GCIOpsErrors.imageBlockOutsideRegion(region: region.name, .init())
            }
            rebuilt.write(encoded, atAddress: UInt(layout.offset - region.offset))
        }

        if let comments = card.comments {
            let decoded = CardComments(
                title: comments.title,
                subtitle: comments.subtitle,
                encoding: comments.encoding
            )
            let start = comments.offset - region.offset
            guard start >= 0, start + CardComments.byteCount <= region.length else {
                throw GCIOpsErrors.commentsOutsideRegion(region: region.name, .init())
            }
            rebuilt.write(
                GoDData(byteStream: decoded.encoded(), byteOrder: .big),
                atAddress: UInt(start)
            )
        }

        guard rebuilt.length == region.length else {
            throw GCIOpsErrors.regionLengthChanged(
                name: region.name, expected: region.length, actual: rebuilt.length, .init()
            )
        }
        return rebuilt
    }

    /// Artifact paths the manifest names, paired with the bare filenames
    /// `CardImageBlock` keys its pieces by.
    private static func imageArtifactPaths(
        images: SaveManifest.Images
    ) -> [(filename: String, path: String)] {
        var entries: [(filename: String, path: String)] = []
        if let banner = images.bannerFile,
           let filename = CardImageBlock.artifactFilename(for: .banner) {
            entries.append((filename, banner))
        }
        for frame in images.frames {
            guard let filename = CardImageBlock.artifactFilename(
                for: .frame(slot: frame.slot)
            ) else { continue }
            entries.append((filename, frame.file))
        }
        return entries
    }
}
