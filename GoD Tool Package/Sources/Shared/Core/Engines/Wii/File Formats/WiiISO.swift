import GoDFoundation
import GoDEngine
import Dolphin
import Structs

/// Represents a complete Wii disc image with multiple encrypted partitions.
/// The FileSystemTree presents partitions as top-level folders (DATA, UPDATE, CHANNEL)
/// with the disc header as a top-level file.
public final class WiiISO: FileSystemTree {
    public static let formatName = "Wii.iso"

    private let wiiEngine: WiiEngine
    private let dolphinEngine: DolphinEngine
    private var partitions: [(name: String, partition: WiiPartition)]
    private let discHeader: GoDData
    private let regionSettings: GoDData

    private static let partitionTypeNames = ["DATA", "UPDATE", "CHANNEL"]

    /// The second magic word every Wii disc carries at 0x4FFFC, outside both the
    /// disc header and any partition. A format invariant like WiiCrypto's cluster
    /// geometry, so it lives in code rather than in the engine's disc constants
    /// (those are serialized per project, and an added field would stop older
    /// engine folders from decoding).
    private static let discMagicWord2: UInt32 = 0xC3F81A8E
    private static let discMagicWord2Offset = 0x4FFFC

    private static func partitionName(for type: Int, index: Int, total: Int) -> String {
        if type < partitionTypeNames.count {
            let baseName = partitionTypeNames[type]
            if total > 1 { return "\(baseName)_\(index)" }
            return baseName
        }
        return "PARTITION_\(type)_\(index)"
    }

    // MARK: - FileSystemTree

    /// Backing FST for top-level disc files (disc_header.bin, region_settings.bin)
    private let topLevelFST = InMemoryFST()

    public func inspectFile(at path: File) -> FileMetaData? {
        if path.path == "/disc_header.bin" || path.path == "/region_settings.bin" {
            return topLevelFST.inspectFile(at: path)
        }
        if let (_, relativePath) = resolvePartition(for: path.path) {
            return partitionForPath(path.path)?.partition.inspectFile(at: File(relativePath))
        }
        return nil
    }

    public func readFile(at path: File) -> GoDReadable? {
        if path.path == "/disc_header.bin" || path.path == "/region_settings.bin" {
            return topLevelFST.readFile(at: path)?.allData
        }
        if let (_, relativePath) = resolvePartition(for: path.path) {
            return partitionForPath(path.path)?.partition.readFile(at: File(relativePath))?.allData
        }
        return nil
    }

    public func writeFile(_ file: GoDReadable, at path: File, overwrite: Bool) throws {
        guard let (_, relativePath) = resolvePartition(for: path.path),
              let partition = partitionForPath(path.path)?.partition else {
            throw FSTErrors.invalidPath(path.path, .init())
        }
        try partition.writeFile(file, at: File(relativePath), overwrite: overwrite)
    }

    /// Moving files across partition boundaries isn't modelled.
    public func moveFile(at path: File, to newPath: File, overwrite: Bool) throws {
        throw FSTErrors.failedToMoveFile(path, newPath, .init())
    }

    public func deleteFile(at path: File) throws {
        guard let (_, relativePath) = resolvePartition(for: path.path),
              let partition = partitionForPath(path.path)?.partition else {
            throw FSTErrors.invalidPath(path.path, .init())
        }
        try partition.deleteFile(at: File(relativePath))
    }

    public func inspectFolder(at path: Folder) -> FolderMetaData? {
        if path.path == "/" {
            return topLevelFST.inspectFolder(at: path)
        }
        if let (name, relativePath) = resolvePartition(for: path.path) {
            guard let partMeta = partitionForPath(path.path)?.partition.inspectFolder(at: Folder(relativePath)) else {
                return nil
            }
            // Prefix partition-relative paths with the partition folder so callers
            // can use the returned paths directly against this WiiISO.
            let prefix = "/\(name)"
            return FolderMetaData(
                name: partMeta.name,
                size: partMeta.size,
                notes: partMeta.notes,
                files: partMeta.files.map { File(prefix + $0.path) },
                subFolders: partMeta.subFolders.map { Folder(prefix + $0.path) }
            )
        }
        return nil
    }

    /// Moving folders across partition boundaries isn't modelled.
    public func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) throws {
        throw FSTErrors.failedToMoveFolder(path, newPath, .init())
    }

    public func createFolder(at path: Folder, overwrite: Bool) throws {
        guard let (_, relativePath) = resolvePartition(for: path.path),
              let partition = partitionForPath(path.path)?.partition else {
            throw FSTErrors.invalidPath(path.path, .init())
        }
        try partition.createFolder(at: Folder(relativePath), overwrite: overwrite)
    }

    public func deleteFolder(at path: Folder) throws {
        guard let (_, relativePath) = resolvePartition(for: path.path),
              let partition = partitionForPath(path.path)?.partition else {
            throw FSTErrors.invalidPath(path.path, .init())
        }
        try partition.deleteFolder(at: Folder(relativePath))
    }

    private func setupTopLevelFST() {
        // Disc-level copies at the tree root are the source of truth for the
        // rebuild path (see the reader in `init(fileSystem:...)`).
        try? topLevelFST.writeFile(discHeader, at: File("/disc_header.bin"), overwrite: true)
        try? topLevelFST.writeFile(regionSettings, at: File("/region_settings.bin"), overwrite: true)
        for (name, _) in partitions {
            try? topLevelFST.createFolder(at: Folder("/\(name)"), overwrite: true)
            // Dolphin's DirectoryBlob reads the disc header/region from inside
            // each partition folder (e.g. DATA/disc/header.bin), so mirror them
            // there too. These route into the partition's own tree via writeFile.
            try? writeFile(discHeader, at: File("/\(name)/disc/header.bin"), overwrite: true)
            try? writeFile(regionSettings, at: File("/\(name)/disc/region.bin"), overwrite: true)
        }
    }

    // MARK: - Path Resolution

    private func resolvePartition(for path: String) -> (name: String, relativePath: String)? {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        for (name, _) in partitions {
            if trimmed == name {
                return (name, "/")
            }
            if trimmed.hasPrefix(name + "/") {
                let relative = "/" + String(trimmed.dropFirst(name.count + 1))
                return (name, relative)
            }
        }
        return nil
    }

    private func partitionForPath(_ path: String) -> (name: String, partition: WiiPartition)? {
        guard let (name, _) = resolvePartition(for: path) else { return nil }
        return partitions.first(where: { $0.name == name })
    }

    // MARK: - Decrypt from ISO

    /// Parse a Wii ISO from encrypted binary data.
    /// Reads an encrypted disc image.
    ///
    /// `data` is a `GoDReadable` so a 4.7 GB image never has to be resident:
    /// the header, region settings and partition table are small windows, and
    /// each partition decrypts groups on demand through
    /// `WiiDecryptedPartitionView`.
    public init(
        data: GoDReadable,
        commonKey: [UInt8],
        wiiEngine: WiiEngine,
        dolphinEngine: DolphinEngine,
        logger: Logger? = nil
    ) throws {
        self.wiiEngine = wiiEngine
        self.dolphinEngine = dolphinEngine
        // A Wii disc is only ever big-endian; a swapped source would read
        // every offset backwards and fail somewhere far from the cause.
        guard data.byteOrder == .big else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }

        let taskName = "Parse Wii ISO"
        logger?.log(.taskStatus(taskName: taskName, status: .started))

        // Read disc header (first 0x440 bytes)
        guard let headerData = data.read(atAddress: 0, length: 0x440) else {
            logger?.log(.error("Failed to read Wii disc header"))
            logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        self.discHeader = headerData

        let gameID = headerData.readString(atAddress: 0, format: .utf8, maxCharacters: 6) ?? "?"
        logger?.log(.info("Wii disc: \(gameID), size: \(data.length) bytes"))

        // Read region settings (at 0x4E000, 0x20 bytes)
        guard let regionData = data.read(atAddress: 0x4E000, length: 0x20) else {
            logger?.log(.error("Failed to read region settings"))
            logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        self.regionSettings = regionData

        // Verify Wii magic word
        let wiiMagicOffset = wiiEngine.data.disc.wiiMagicWordOffset
        let wiiMagic: UInt32 = data.readSafely(atAddress: wiiMagicOffset)
        guard wiiMagic == wiiEngine.data.disc.wiiMagicWord else {
            logger?.log(.error("Invalid Wii magic word: 0x\(String(wiiMagic, radix: 16)) (expected 0x\(String(wiiEngine.data.disc.wiiMagicWord, radix: 16)))"))
            logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
            throw FileFormatErrors.invalid(format: Self.formatName)
        }

        // Parse partition table at 0x40000
        let partTableOffset = wiiEngine.data.disc.partitionTableOffset
        var allPartitions: [(name: String, partition: WiiPartition)] = []

        for tableIndex in 0..<4 {
            let countOffset = partTableOffset + tableIndex * 8
            let tableOffsetField = partTableOffset + tableIndex * 8 + 4

            let count: UInt32 = data.readSafely(atAddress: countOffset)
            let tableOffset = Int(data.readSafely(atAddress: tableOffsetField) as UInt32) << 2

            if count == 0 { continue }

            logger?.log(.info("Partition table \(tableIndex): \(count) partition(s) at 0x\(String(tableOffset, radix: 16, uppercase: true))"))

            var typeCounts: [Int: Int] = [:]
            var partInfos: [(offset: Int, type: Int)] = []
            for i in 0..<Int(count) {
                let entryOffset = tableOffset + i * 8
                let partOffset = Int(data.readSafely(atAddress: entryOffset) as UInt32) << 2
                let partType: Int = Int(data.readSafely(atAddress: entryOffset + 4) as UInt32)
                typeCounts[partType, default: 0] += 1
                partInfos.append((offset: partOffset, type: partType))
            }

            var typeIndices: [Int: Int] = [:]
            for info in partInfos {
                let typeIndex = typeIndices[info.type, default: 0]
                typeIndices[info.type] = typeIndex + 1

                let totalOfType = typeCounts[info.type] ?? 1
                let name = Self.partitionName(for: info.type, index: typeIndex, total: totalOfType)

                logger?.log(.info("  \(name) partition at offset 0x\(String(info.offset, radix: 16, uppercase: true))"))

                let partition = try WiiPartition(
                    data: data,
                    partitionOffset: info.offset,
                    partitionType: info.type,
                    commonKey: commonKey,
                    wiiEngine: wiiEngine,
                    dolphinEngine: dolphinEngine,
                    logger: logger
                )
                allPartitions.append((name: name, partition: partition))
            }
        }

        self.partitions = allPartitions
        setupTopLevelFST()

        logger?.log(.info("Parsed \(allPartitions.count) partition(s)"))
        logger?.log(.taskStatus(taskName: taskName, status: .completed(true)))
    }

    // MARK: - Rebuild to encrypted ISO

    /// Rebuild the full Wii ISO from partition contents.
    public func encryptedData(commonKey: [UInt8], logger: Logger? = nil) throws -> GoDData {
        let taskName = "Build Wii ISO"
        logger?.log(.taskStatus(taskName: taskName, status: .started))

        let isoData = GoDData(length: 0, byteOrder: .big)

        // Write disc header
        isoData.write(discHeader, atAddress: 0)

        // Write region settings
        isoData.write(regionSettings, atAddress: 0x4E000)

        // Restore the second magic word. It sits in the unencrypted region
        // rather than in any file we dump, so a rebuild has to re-emit it —
        // wit and the drive firmware use it to recognize a Wii disc.
        isoData.write(Self.discMagicWord2, atAddress: Self.discMagicWord2Offset)

        // Build partition table and write partitions
        let partTableOffset = wiiEngine.data.disc.partitionTableOffset

        let partCount = UInt32(partitions.count)
        let partEntriesOffset = partTableOffset + 0x20

        isoData.write(partCount, atAddress: partTableOffset)
        isoData.write(UInt32(partEntriesOffset >> 2), atAddress: partTableOffset + 4)

        for i in 1..<4 {
            isoData.write(UInt32(0), atAddress: partTableOffset + i * 8)
            isoData.write(UInt32(0), atAddress: partTableOffset + i * 8 + 4)
        }

        var currentOffset = 0x50000

        for (i, (name, partition)) in partitions.enumerated() {
            currentOffset = currentOffset.aligned(to: 0x8000)

            let entryOffset = partEntriesOffset + i * 8
            isoData.write(UInt32(currentOffset >> 2), atAddress: entryOffset)
            isoData.write(UInt32(partition.type), atAddress: entryOffset + 4)

            logger?.log(.info("Writing \(name) partition at offset 0x\(String(currentOffset, radix: 16, uppercase: true))"))
            let encryptedPartition = try partition.encrypt(commonKey: commonKey, logger: logger)
            isoData.write(encryptedPartition, atAddress: currentOffset)

            currentOffset += encryptedPartition.length
        }

        // Not padded to disc capacity here: that is the separate fillISO
        // operation's job, and doing it unconditionally would make every
        // rebuild — including a test-sized one — a 4.7 GB allocation.
        logger?.log(.taskStatus(taskName: taskName, status: .completed(true)))
        return isoData
    }

    // MARK: - Build from FST

    /// Initialize from an existing file system tree for rebuilding.
    public init(
        fst source: FileSystemTree,
        rootFolder: Folder,
        commonKey: [UInt8],
        wiiEngine: WiiEngine,
        dolphinEngine: DolphinEngine
    ) {
        self.wiiEngine = wiiEngine
        self.dolphinEngine = dolphinEngine

        let headerFile = rootFolder.file("disc_header.bin")
        self.discHeader = source.readFile(at: headerFile)?.allData ?? GoDData(length: 0x440, byteOrder: .big)

        let regionFile = rootFolder.file("region_settings.bin")
        self.regionSettings = source.readFile(at: regionFile)?.allData ?? GoDData(length: 0x20, byteOrder: .big)

        var foundPartitions: [(name: String, partition: WiiPartition)] = []
        if let rootContents = source.inspectFolder(at: rootFolder) {
            for subFolder in rootContents.subFolders {
                let folderName = subFolder.folderName
                let partType: Int
                if folderName.hasPrefix("DATA") { partType = 0 }
                else if folderName.hasPrefix("UPDATE") { partType = 1 }
                else if folderName.hasPrefix("CHANNEL") { partType = 2 }
                else { continue }

                let partFiles = wiiEngine.data.partitionFiles
                let ticketFile = subFolder.file(partFiles.ticketFile.path)
                let tmdFile = subFolder.file(partFiles.tmdFile.path)
                let certFile = subFolder.file(partFiles.certFile.path)
                let h3File = subFolder.file(partFiles.h3File.path)

                let ticket = source.readFile(at: ticketFile)?.allData ?? GoDData(length: 0x2A4, byteOrder: .big)
                let tmd = source.readFile(at: tmdFile)?.allData ?? GoDData(length: 0, byteOrder: .big)
                let cert = source.readFile(at: certFile)?.allData ?? GoDData(length: 0, byteOrder: .big)
                let h3 = source.readFile(at: h3File)?.allData ?? GoDData(length: 0x18000, byteOrder: .big)

                let partition = WiiPartition(
                    fst: source,
                    rootFolder: subFolder,
                    partitionType: partType,
                    ticket: ticket,
                    tmd: tmd,
                    certChain: cert,
                    h3Table: h3,
                    wiiEngine: wiiEngine,
                    dolphinEngine: dolphinEngine
                )
                foundPartitions.append((name: folderName, partition: partition))
            }
        }
        self.partitions = foundPartitions
        setupTopLevelFST()
    }

    /// Access a specific partition by name.
    public func partition(named name: String) -> WiiPartition? {
        partitions.first(where: { $0.name == name })?.partition
    }

    /// The DATA partition (primary game content).
    public var dataPartition: WiiPartition? {
        partitions.first(where: { $0.partition.type == 0 })?.partition
    }
}

// MARK: - Sizing and readers
//
// Routed to the owning partition, the same way the whole-file operations are.
// A path outside every partition has no file to address, so these report it
// rather than silently doing nothing.

public extension WiiISO {
    func fileSize(at path: File) -> Int? {
        guard let (partition, relativePath) = partitionAndRelativePath(for: path) else { return nil }
        return partition.fileSize(at: File(relativePath))
    }

    func resizeFile(at path: File, to length: Int) throws {
        let (partition, relativePath) = try requirePartition(for: path)
        try partition.resizeFile(at: File(relativePath), to: length)
    }

    private func partitionAndRelativePath(for path: File) -> (WiiPartition, String)? {
        guard let (_, relativePath) = resolvePartition(for: path.path),
              let partition = partitionForPath(path.path)?.partition else { return nil }
        return (partition, relativePath)
    }

    private func requirePartition(for path: File) throws -> (WiiPartition, String) {
        guard let resolved = partitionAndRelativePath(for: path) else {
            throw FSTErrors.invalidPath(path.path, .init())
        }
        return resolved
    }
}
