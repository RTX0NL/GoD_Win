import GoDFoundation
import GoDEngine
import Dolphin
import Structs

/// Represents a single decrypted Wii disc partition.
/// Each partition contains its own file system (boot.bin, bi2, apploader, DOL, FST, user files)
/// along with encryption metadata (ticket, TMD, cert chain, H3 table).
public final class WiiPartition: FileSystemTree {
    public static let formatName = "Wii.partition"

    public let type: Int
    public let ticket: GoDData
    public let tmd: GoDData
    public let certChain: GoDData
    public let h3Table: GoDData

    private let wiiEngine: WiiEngine
    private let dolphinEngine: DolphinEngine
    fileprivate let fst = InMemoryFST()

    private static let partitionTypeNames = ["DATA", "UPDATE", "CHANNEL"]
    private var typeName: String {
        type < Self.partitionTypeNames.count ? Self.partitionTypeNames[type] : "PARTITION_\(type)"
    }

    /// Where a non-DATA partition's opaque decrypted payload is kept. UPDATE and
    /// CHANNEL partitions hold IOS/WAD data with no game filesystem, so they are
    /// dumped and rebuilt as one blob. This is our own dump layout rather than a
    /// game constant, so it lives here and not in the engine's partition files.
    private static let partitionDataFile = File("/sys/partition_data.bin")

    // MARK: - FileSystemTree delegation

    public func inspectFile(at path: File) -> FileMetaData? { fst.inspectFile(at: path) }
    public func readFile(at path: File) -> GoDData? { fst.readFile(at: path) }
    public func moveFile(at path: File, to newPath: File, overwrite: Bool) throws { try fst.moveFile(at: path, to: newPath, overwrite: overwrite) }
    public func writeFile(_ file: GoDData, at path: File, overwrite: Bool) throws {
        file.setByteOrder(.big)
        try fst.writeFile(file, at: path, overwrite: overwrite)
    }
    public func deleteFile(at path: File) throws { try fst.deleteFile(at: path) }
    public func inspectFolder(at path: Folder) -> FolderMetaData? { fst.inspectFolder(at: path) }
    public func moveFolder(at path: Folder, to newPath: Folder, overwrite: Bool) throws { try fst.moveFolder(at: path, to: newPath, overwrite: overwrite) }
    public func createFolder(at path: Folder, overwrite: Bool) throws { try fst.createFolder(at: path, overwrite: overwrite) }
    public func deleteFolder(at path: Folder) throws { try fst.deleteFolder(at: path) }

    // MARK: - Decrypt from ISO data

    /// Parse and decrypt a partition from raw ISO data.
    /// Uses lazy decryption — groups are only decrypted when their data is accessed.
    public init(
        data: GoDData,
        partitionOffset: Int,
        partitionType: Int,
        commonKey: [UInt8],
        wiiEngine: WiiEngine,
        dolphinEngine: DolphinEngine,
        logger: Logger? = nil
    ) throws {
        self.wiiEngine = wiiEngine
        self.dolphinEngine = dolphinEngine
        self.type = partitionType
        data.setByteOrder(.big)

        let partFiles = wiiEngine.data.partitionFiles
        let partTypeName = partitionType < Self.partitionTypeNames.count ? Self.partitionTypeNames[partitionType] : "PARTITION_\(partitionType)"

        // Read ticket (0x2A4 bytes at partition start)
        guard let ticketData = data.read(atAddress: partitionOffset, length: 0x2A4) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        self.ticket = ticketData

        // Decrypt title key
        guard let titleKey = WiiCrypto.decryptTitleKey(ticketData: ticketData, commonKey: commonKey) else {
            logger?.log(.error("Failed to decrypt title key for \(partTypeName) partition (truncated ticket)"))
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        logger?.log(.info("Decrypted title key for \(partTypeName) partition at 0x\(String(partitionOffset, radix: 16, uppercase: true))"))
        logger?.log(.info("  Title ID: \(ticketData.read(atAddress: 0x1DC, length: 8)?.rawBytes.map { String(format: "%02x", $0) }.joined() ?? "?")"))
        logger?.log(.info("  Title key: \(titleKey.map { String(format: "%02x", $0) }.joined())"))

        // Read partition header at offset 0x2A4 from partition start
        guard let partHeaderData = data.read(atAddress: partitionOffset + 0x2A4, length: 0x1C) else {
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        partHeaderData.setByteOrder(.big)

        let tmdSize = Int(partHeaderData.readSafely(atAddress: 0x00) as UInt32)
        let tmdOffset = Int(partHeaderData.readSafely(atAddress: 0x04) as UInt32) << 2
        let certSize = Int(partHeaderData.readSafely(atAddress: 0x08) as UInt32)
        let certOffset = Int(partHeaderData.readSafely(atAddress: 0x0C) as UInt32) << 2
        let h3Offset = Int(partHeaderData.readSafely(atAddress: 0x10) as UInt32) << 2
        let dataOffset = Int(partHeaderData.readSafely(atAddress: 0x14) as UInt32) << 2
        let dataSize = Int(partHeaderData.readSafely(atAddress: 0x18) as UInt32) << 2

        logger?.log(.info("  Partition header: TMD=0x\(String(tmdSize, radix: 16)) @ 0x\(String(tmdOffset, radix: 16)), cert=0x\(String(certSize, radix: 16)) @ 0x\(String(certOffset, radix: 16)), H3 @ 0x\(String(h3Offset, radix: 16)), data=0x\(String(dataSize, radix: 16)) @ 0x\(String(dataOffset, radix: 16))"))

        // Read TMD
        guard let tmdData = data.read(atAddress: partitionOffset + tmdOffset, length: tmdSize) else {
            logger?.log(.error("Failed to read TMD for \(partTypeName) partition"))
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        self.tmd = tmdData

        // Read cert chain
        guard let certData = data.read(atAddress: partitionOffset + certOffset, length: certSize) else {
            logger?.log(.error("Failed to read cert chain for \(partTypeName) partition"))
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        self.certChain = certData

        // Read H3 hash table (0x18000 bytes)
        guard let h3Data = data.read(atAddress: partitionOffset + h3Offset, length: 0x18000) else {
            logger?.log(.error("Failed to read H3 table for \(partTypeName) partition"))
            throw FileFormatErrors.invalid(format: Self.formatName)
        }
        self.h3Table = h3Data

        // Create lazy-decrypting view over the encrypted partition data.
        // Groups are only decrypted when their bytes are actually read.
        let absoluteDataStart = partitionOffset + dataOffset
        let groupSize = wiiEngine.data.disc.dataGroupSize
        let userDataPerGroup = wiiEngine.data.disc.userDataPerGroup
        let groupCount = dataSize / groupSize

        let decryptedView = WiiDecryptedPartitionView(
            encryptedData: data,
            partitionDataStart: absoluteDataStart,
            dataSize: dataSize,
            titleKey: titleKey,
            groupSize: groupSize,
            userDataPerGroup: userDataPerGroup
        )

        logger?.log(.info("  Encrypted data: \(groupCount) groups (\(dataSize) bytes) starting at 0x\(String(absoluteDataStart, radix: 16, uppercase: true))"))
        logger?.log(.info("  Decrypted view length: \(decryptedView.length) bytes"))

        // Create folder structure
        try fst.createFolder(at: partFiles.systemFolder, overwrite: true)

        // Write partition metadata as files
        try fst.writeFile(ticketData, at: partFiles.ticketFile, overwrite: true)
        try fst.writeFile(tmdData, at: partFiles.tmdFile, overwrite: true)
        try fst.writeFile(certData, at: partFiles.certFile, overwrite: true)
        try fst.writeFile(h3Data, at: partFiles.h3File, overwrite: true)

        // Only DATA partitions (type 0) have a game filesystem (boot.bin, DOL, FST, user files).
        // UPDATE and CHANNEL partitions contain IOS/WAD data — store as raw decrypted blob.
        if partitionType == 0 {
            let taskName = "Decrypt \(partTypeName) partition"
            logger?.log(.taskStatus(taskName: taskName, status: .started))

            try fst.createFolder(at: partFiles.filesFolder, overwrite: true)

            // Parse boot.bin
            let bootDataStruct = dolphinEngine.bootDataStruct
            guard let bootData = decryptedView.read(struct: bootDataStruct, atAddress: 0) else {
                logger?.log(.error("Failed to parse boot.bin from decrypted \(partTypeName) partition"))
                logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
                throw FileFormatErrors.invalid(format: Self.formatName)
            }
            try fst.writeFile(bootData.data, at: partFiles.bootFile, overwrite: true)
            logger?.log(.info("  Parsed boot.bin (\(bootData.length) bytes)"))

            // Parse bi2.bin
            let bi2Struct = dolphinEngine.bi2Struct
            let bi2Offset = dolphinEngine.data.systemFiles.bi2DataOffset
            guard let bi2Data = decryptedView.read(struct: bi2Struct, atAddress: bi2Offset) else {
                logger?.log(.error("Failed to parse bi2.bin from decrypted \(partTypeName) partition"))
                logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
                throw FileFormatErrors.invalid(format: Self.formatName)
            }
            try fst.writeFile(bi2Data.data, at: partFiles.bi2File, overwrite: true)
            logger?.log(.info("  Parsed bi2.bin (\(bi2Data.length) bytes)"))

            // Parse apploader
            let apploaderStruct = dolphinEngine.apploaderHeaderStruct
            let apploaderOffset = dolphinEngine.data.systemFiles.apploaderOffset
            guard let apploaderHeader = decryptedView.read(struct: apploaderStruct, atAddress: apploaderOffset) else {
                logger?.log(.error("Failed to parse apploader header from decrypted \(partTypeName) partition"))
                logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
                throw FileFormatErrors.invalid(format: Self.formatName)
            }
            let appSize: Int = try apploaderHeader.size
            let trailerSize: Int = try apploaderHeader.trailer_size
            let totalApploaderSize = apploaderHeader.length + appSize + trailerSize
            guard let apploaderData = decryptedView.read(atAddress: apploaderOffset, length: totalApploaderSize) else {
                logger?.log(.error("Failed to read apploader data from decrypted \(partTypeName) partition"))
                logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
                throw FileFormatErrors.invalid(format: Self.formatName)
            }
            try fst.writeFile(apploaderData, at: partFiles.apploaderFile, overwrite: true)
            logger?.log(.info("  Parsed apploader (\(totalApploaderSize) bytes)"))

            // Parse main.dol
            // Wii partition offsets in boot.bin are stored >> 2 (divided by fstOffsetMultiplier)
            let offsetMultiplier = wiiEngine.data.disc.fstOffsetMultiplier
            let dolOffset: Int = try bootData.main_executable_offset * offsetMultiplier
            let dolHeaderStruct = dolphinEngine.dolHeaderStruct
            guard let dolHeader = decryptedView.read(struct: dolHeaderStruct, atAddress: dolOffset) else {
                logger?.log(.error("Failed to parse DOL header from decrypted \(partTypeName) partition at offset 0x\(String(dolOffset, radix: 16))"))
                logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
                throw FileFormatErrors.invalid(format: Self.formatName)
            }
            let textSizes: [UInt32] = try dolHeader.text_sections_sizes
            let dataSizes: [UInt32] = try dolHeader.data_sections_sizes
            let dolSize = dolHeader.length + textSizes.map(\.asInt).reduce(0, +) + dataSizes.map(\.asInt).reduce(0, +)
            logger?.log(.info("  DOL: offset=0x\(String(dolOffset, radix: 16)) header=\(dolHeader.length) text=\(textSizes.map(\.asInt)) data=\(dataSizes.map(\.asInt)) total=\(dolSize) viewLen=\(decryptedView.length)"))
            guard let dolData = decryptedView.read(atAddress: dolOffset, length: dolSize) else {
                logger?.log(.error("Failed to read DOL data: offset=0x\(String(dolOffset, radix: 16)) size=0x\(String(dolSize, radix: 16)) end=0x\(String(dolOffset + dolSize, radix: 16)) viewLen=0x\(String(decryptedView.length, radix: 16))"))
                logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
                throw FileFormatErrors.invalid(format: Self.formatName)
            }
            try fst.writeFile(dolData, at: partFiles.executableFile, overwrite: true)
            logger?.log(.info("  Parsed main.dol (\(dolSize) bytes) at offset 0x\(String(dolOffset, radix: 16))"))

            // Parse FST (offsets in Wii boot.bin are stored >> 2)
            let fstOffset: Int = try bootData.fst_offset * offsetMultiplier
            let fstSize: Int = try bootData.fst_size * offsetMultiplier
            guard let fstData = decryptedView.read(atAddress: fstOffset, length: fstSize) else {
                logger?.log(.error("Failed to read FST from decrypted \(partTypeName) partition at offset 0x\(String(fstOffset, radix: 16))"))
                logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
                throw FileFormatErrors.invalid(format: Self.formatName)
            }
            try fst.writeFile(fstData, at: partFiles.fstFile, overwrite: true)
            logger?.log(.info("  Parsed fst.bin (\(fstSize) bytes) at offset 0x\(String(fstOffset, radix: 16))"))

            // Parse user files from FST. A Wii FST stores each entry's file
            // offset >> 2 as well, so the Wii multiplier has to be passed in —
            // the Dolphin engine's own value is 1.
            let userSectionOffset: Int = try bootData.user_data_offset * offsetMultiplier
            let fstManifest = try DolphinFST(
                tocData: fstData,
                userSectionOffset: userSectionOffset,
                dolphinEngine: dolphinEngine,
                offsetMultiplier: offsetMultiplier
            )

            try fstManifest.folders.sorted().forEach { folder in
                try fst.createFolder(at: folder, overwrite: true)
            }

            let sortedFiles = fstManifest.files.keys.sorted()
            let totalFiles = sortedFiles.count
            logger?.log(.info("  Extracting \(totalFiles) user files from \(partTypeName) partition"))

            for (index, file) in sortedFiles.enumerated() {
                guard let (offset, size) = fstManifest.files[file],
                      let fileData = decryptedView.read(atAddress: offset + userSectionOffset, length: size) else { continue }
                try fst.writeFile(fileData, at: file, overwrite: true)

                if totalFiles > 0, (index + 1) % max(totalFiles / 20, 1) == 0 || index == totalFiles - 1 {
                    let percentage = Percentage(Double(index + 1) / Double(totalFiles) * 100)
                    logger?.log(.taskStatus(taskName: taskName, status: .progress(percentage)))
                }
            }

            logger?.log(.taskStatus(taskName: taskName, status: .completed(true)))

        } else {
            let taskName = "Extract \(partTypeName) partition"
            logger?.log(.taskStatus(taskName: taskName, status: .started))
            // Non-DATA partition: store raw decrypted data as a blob
            if let rawData = decryptedView.read(atAddress: 0, length: decryptedView.length) {
                try fst.writeFile(rawData, at: Self.partitionDataFile, overwrite: true)
                logger?.log(.info("  Stored \(partTypeName) partition data (\(decryptedView.length) bytes)"))
            }
            logger?.log(.taskStatus(taskName: taskName, status: .completed(true)))
        }
    }

    /// Initialize from an existing file system tree (for building).
    public init(
        fst source: FileSystemTree,
        rootFolder: Folder,
        partitionType: Int,
        ticket: GoDData,
        tmd: GoDData,
        certChain: GoDData,
        h3Table: GoDData,
        wiiEngine: WiiEngine,
        dolphinEngine: DolphinEngine
    ) {
        self.wiiEngine = wiiEngine
        self.dolphinEngine = dolphinEngine
        self.type = partitionType
        self.ticket = ticket
        self.tmd = tmd
        self.certChain = certChain
        self.h3Table = h3Table
        try? importFST(source, from: rootFolder, to: Folder("/"), overwrite: true)
    }

    // MARK: - Encrypt to binary

    /// Lay the DATA partition's game filesystem back out into a decrypted
    /// payload — bi2, apploader, DOL, FST, user files — with boot.bin updated to
    /// match. Every offset boot.bin and the FST record is stored >> 2 on a Wii
    /// disc, which is what the read path multiplies back up.
    private func rebuiltGameFilesystem(taskName: String, logger: Logger?) throws -> GoDData {
        let partFiles = wiiEngine.data.partitionFiles
        let systemFiles = dolphinEngine.data.systemFiles
        let offsetMultiplier = max(wiiEngine.data.disc.fstOffsetMultiplier, 1)

        func encodingFailure() -> Error {
            logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
            return FileFormatErrors.failedToEncode(format: Self.formatName, target: "Wii partition")
        }

        let decryptedData = GoDData(length: 0, byteOrder: .big)

        guard let bootFileData = readFile(at: partFiles.bootFile),
              let bootStruct = bootFileData.read(struct: dolphinEngine.bootDataStruct, atAddress: 0) else {
            logger?.log(.error("Failed to read boot.bin for \(typeName) partition encryption"))
            throw encodingFailure()
        }

        guard let bi2Data = readFile(at: partFiles.bi2File) else { throw encodingFailure() }
        decryptedData.write(bi2Data, atAddress: systemFiles.bi2DataOffset)

        guard let apploaderData = readFile(at: partFiles.apploaderFile) else { throw encodingFailure() }
        let apploaderOffset = systemFiles.apploaderOffset
        decryptedData.write(apploaderData, atAddress: apploaderOffset)

        guard let dolData = readFile(at: partFiles.executableFile) else { throw encodingFailure() }
        let dolAlignment = max(systemFiles.dolOffsetAlignment, 1)
        let dolOffset = (apploaderOffset + apploaderData.length).aligned(to: dolAlignment)
        decryptedData.write(dolData, atAddress: dolOffset)

        let fstManifest = DolphinFST(fileSystem: self, root: partFiles.filesFolder)
        // boot.bin stores the FST size >> 2 as well, so reserve whole words.
        let fstSize = fstManifest.tocDataLength.aligned(to: offsetMultiplier)
        let fstOffset = (dolOffset + dolData.length).aligned(to: offsetMultiplier)

        let userAlignment = max(dolphinEngine.data.userFiles.userOffsetAlignment, 1)
        let userOffset = (fstOffset + fstSize).aligned(to: userAlignment)

        let fstData = try fstManifest.tocData(
            userOffset: userOffset,
            dolphinEngine: dolphinEngine,
            offsetMultiplier: offsetMultiplier
        )
        decryptedData.write(fstData, atAddress: fstOffset)

        bootStruct.main_executable_offset = dolOffset / offsetMultiplier
        bootStruct.fst_offset = fstOffset / offsetMultiplier
        bootStruct.fst_size = fstSize / offsetMultiplier
        bootStruct.max_fst_size = fstSize / offsetMultiplier
        bootStruct.user_data_offset = userOffset / offsetMultiplier

        logger?.log(.info("  Layout: DOL @ 0x\(String(dolOffset, radix: 16)), FST @ 0x\(String(fstOffset, radix: 16)), user @ 0x\(String(userOffset, radix: 16))"))

        let sortedFiles = fstManifest.files.sorted(by: { $0.value.offsetInUserSection < $1.value.offsetInUserSection })
        for (file, value) in sortedFiles {
            guard let fileData = fst.readFile(at: file) else { throw encodingFailure() }
            decryptedData.write(fileData, atAddress: userOffset + value.offsetInUserSection)
        }

        // boot.bin last, now that every offset it records is known.
        decryptedData.write(struct: bootStruct, atAddress: systemFiles.bootDataOffset)
        return decryptedData
    }

    /// Rebuild the partition into encrypted binary data.
    public func encrypt(commonKey: [UInt8], logger: Logger? = nil) throws -> GoDData {
        let partFiles = wiiEngine.data.partitionFiles
        let taskName = "Encrypt \(typeName) partition"
        logger?.log(.taskStatus(taskName: taskName, status: .started))

        // Only DATA partitions carry a game filesystem to lay out again. UPDATE
        // and CHANNEL partitions were dumped as one opaque decrypted blob, so
        // that blob *is* their payload — asking them for a boot.bin would fail.
        let decryptedData: GoDData
        if type == 0 {
            decryptedData = try rebuiltGameFilesystem(taskName: taskName, logger: logger)
        } else {
            guard let blob = readFile(at: Self.partitionDataFile) else {
                logger?.log(.error("Failed to read \(Self.partitionDataFile.path) for \(typeName) partition encryption"))
                logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
                throw FileFormatErrors.failedToEncode(format: Self.formatName, target: "Wii partition")
            }
            decryptedData = blob
        }

        // Read ticket for title key
        guard let ticketData = readFile(at: partFiles.ticketFile) else {
            logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
            throw FileFormatErrors.failedToEncode(format: Self.formatName, target: "Wii partition")
        }
        guard let titleKey = WiiCrypto.decryptTitleKey(ticketData: ticketData, commonKey: commonKey) else {
            logger?.log(.error("Failed to decrypt title key for \(typeName) partition (truncated ticket)"))
            logger?.log(.taskStatus(taskName: taskName, status: .completed(false)))
            throw FileFormatErrors.failedToEncode(format: Self.formatName, target: "Wii partition")
        }

        // Encrypt the entire decrypted user data, building the full H0/H1/H2/H3 hash tree.
        // encryptPartitionData zero-pads up to a whole number of 64-cluster groups.
        let (encryptedBytes, h3TableBytes) = WiiCrypto.encryptPartitionData(
            decryptedUserData: decryptedData.rawBytes,
            titleKey: titleKey
        )
        let encryptedData = GoDData(byteStream: encryptedBytes, byteOrder: .big)
        let h3TableData = GoDData(byteStream: h3TableBytes, byteOrder: .big)
        logger?.log(.info("  Encrypted \(encryptedBytes.count / 0x8000) clusters (\(encryptedBytes.count) bytes); rebuilt H3 table"))

        // Persist the rebuilt H3 table into the /sys h3 file image.
        try fst.writeFile(h3TableData, at: partFiles.h3File, overwrite: true)

        // Link + fakesign the TMD:
        //   - content 0's SHA-1 (TMD offset 0x1F4, 20 bytes) = SHA1(rebuilt H3 table)
        //   - then fakesign so the (now-invalid) RSA signature passes signature-strip loaders.
        // The ticket is written verbatim (its original signature covers only the title key, which we did not change).
        let tmdCopy = GoDData(byteStream: tmd.rawBytes, byteOrder: .big)
        let h3Hash = SHA1.hash(h3TableBytes)
        tmdCopy.write(GoDData(byteStream: h3Hash, byteOrder: .big), atAddress: 0x1F4)
        let fakesignedTMD = WiiCrypto.fakesignTMD(tmdCopy)
        try fst.writeFile(fakesignedTMD, at: partFiles.tmdFile, overwrite: true)

        // Build partition: ticket + header area + TMD + cert + H3 + encrypted data
        let result = GoDData(byteOrder: .big)

        // Write ticket at offset 0
        result.write(ticket, atAddress: 0)

        // Partition header at offset 0x2A4
        let tmdOffsetInPartition = 0x2C0
        let certOffsetInPartition = (tmdOffsetInPartition + fakesignedTMD.length).aligned(to: 0x20)
        let h3OffsetInPartition = (certOffsetInPartition + certChain.length).aligned(to: 0x20)
        let dataOffsetInPartition = (h3OffsetInPartition + 0x18000).aligned(to: 0x8000)

        // Write header
        result.write(UInt32(fakesignedTMD.length), atAddress: 0x2A4)
        result.write(UInt32(tmdOffsetInPartition >> 2), atAddress: 0x2A8)
        result.write(UInt32(certChain.length), atAddress: 0x2AC)
        result.write(UInt32(certOffsetInPartition >> 2), atAddress: 0x2B0)
        result.write(UInt32(h3OffsetInPartition >> 2), atAddress: 0x2B4)
        result.write(UInt32(dataOffsetInPartition >> 2), atAddress: 0x2B8)
        result.write(UInt32(encryptedData.length >> 2), atAddress: 0x2BC)

        // Write fakesigned TMD, cert, rebuilt H3 table, and encrypted data.
        result.write(fakesignedTMD, atAddress: tmdOffsetInPartition)
        result.write(certChain, atAddress: certOffsetInPartition)
        result.write(h3TableData, atAddress: h3OffsetInPartition)
        result.write(encryptedData, atAddress: dataOffsetInPartition)

        logger?.log(.taskStatus(taskName: taskName, status: .completed(true)))
        return result
    }
}

// MARK: - Random access
//
// Pass-through to the partition's backing tree, matching the whole-file
// forwarders above.

public extension WiiPartition {
    func fileSize(at path: File) -> Int? { fst.fileSize(at: path) }

    func readFile(at path: File, range: Range<Int>) -> GoDData? {
        fst.readFile(at: path, range: range)
    }

    func appendToFile(_ data: GoDData, at path: File) throws {
        try fst.appendToFile(data, at: path)
    }

    func writeFile(_ data: GoDData, at path: File, offset: Int) throws {
        try fst.writeFile(data, at: path, offset: offset)
    }

    func resizeFile(at path: File, to length: Int) throws {
        try fst.resizeFile(at: path, to: length)
    }
}
