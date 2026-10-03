//
//  RVZImage.swift
//
//  A whole WIA or RVZ file, and the restore that turns it back into a raw
//  disc image.
//
//  The format's own structs live in `WIAHeader.swift` and
//  `WIAPartition.swift`; this file is the part that knows how they fit
//  together — which groups belong to which region of the disc, how a group's
//  payload is layered (compression, then RVZ packing, then exception lists),
//  and in what order the pieces are written back out.
//
//  Read only. GoD-Tool restores a `.rvz` / `.wia` to an ISO and never
//  produces one, so there is no writer here and no Zstandard encoder in the
//  package to build one with.
//
//  Reference: dolphin-emu/dolphin `docs/WiaAndRvz.md`,
//  `Source/Core/DiscIO/WIABlob.cpp`
//

import Foundation
import GoDFoundation

/// Supplies the Wii-specific half of a restore.
///
/// WIA/RVZ stores Wii partition data decrypted and with its hash blocks
/// stripped, so rebuilding the disc means recomputing the H0/H1/H2 tree and
/// re-encrypting with the partition's title key. That is Wii disc knowledge,
/// which this module deliberately doesn't carry — the caller injects it, the
/// same way a `FileFormatRegistry` is injected at its use site. A GameCube
/// image needs none, and asking for one is how the restore reports that a
/// Wii image was handed to a caller that can't finish it.
public protocol WiiPartitionRestorer {

    /// Encrypt one group of a Wii partition.
    ///
    /// - Parameters:
    ///   - decryptedUserData: exactly `clustersPerGroup × userDataPerCluster`
    ///     bytes (0x1F0000). A short final group is zero-padded by the
    ///     caller, because the hashes of the absent clusters still appear in
    ///     the hash blocks of the present ones.
    ///   - titleKey: the partition's 16-byte title key, already decrypted —
    ///     WIA/RVZ stores it that way, so no common key is needed.
    ///   - hashExceptions: replacements to write over the recomputed hashes
    ///     before encryption. Each offset addresses the group's hash region:
    ///     `offset / 0x400` picks the cluster and `offset % 0x400` the byte
    ///     within its 0x400-byte hash block.
    /// - Returns: `clustersPerGroup × clusterSize` bytes (0x200000).
    func encryptGroup(
        decryptedUserData: [UInt8],
        titleKey: [UInt8],
        hashExceptions: [WIAExceptionList.Exception]
    ) throws -> [UInt8]
}

public enum RVZError: Error, CustomStringConvertible {
    case badMagic([UInt8])
    case headerHashMismatch(field: String)
    case unsupportedCompression(String)
    case invalidChunkSize(UInt32)
    case truncated(what: String)
    case groupIndexOutOfRange(index: Int, count: Int)
    case groupSizeMismatch(group: Int, expected: Int, found: Int)
    case packedSizeMismatch(group: Int, expected: Int, found: Int)
    case nonContiguousPartitionSegments(partition: Int)
    case missingPartitionRestorer(partitionCount: Int)
    case exceptionOffsetOutOfRange(UInt16)
    case partitionShortOfItsSectors(partition: Int, declared: Int, covered: Int)
    case writePastEndOfDisc(what: String, offset: Int, length: Int, discSize: Int)

    public var description: String {
        switch self {
        case let .badMagic(bytes):
            let spelled = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "Not a WIA or RVZ file: magic is \(spelled), not \"WIA\\x01\" or \"RVZ\\x01\""
        case let .headerHashMismatch(field):
            return "WIA/RVZ \(field) does not match the bytes it covers; the file is damaged"
        case let .unsupportedCompression(name):
            return "WIA/RVZ compression \(name) is not implemented"
        case let .invalidChunkSize(size):
            return String(format: "WIA/RVZ chunk size 0x%X is not one the format allows", size)
        case let .truncated(what):
            return "WIA/RVZ file ends before its \(what)"
        case let .groupIndexOutOfRange(index, count):
            return "WIA/RVZ references group \(index) but the table holds \(count)"
        case let .groupSizeMismatch(group, expected, found):
            return "WIA/RVZ group \(group) yields \(found) bytes where its region needs \(expected)"
        case let .packedSizeMismatch(group, expected, found):
            return "WIA/RVZ group \(group) declares \(expected) packed bytes but carries \(found)"
        case let .nonContiguousPartitionSegments(partition):
            return "WIA/RVZ partition \(partition)'s two data segments leave a gap, which no restore can fill"
        case let .missingPartitionRestorer(count):
            return "This image holds \(count) Wii partition(s); restoring them needs the Wii hash and "
                + "encryption layer, which the caller did not supply"
        case let .exceptionOffsetOutOfRange(offset):
            return String(format: "WIA/RVZ hash exception at offset 0x%04X falls outside its group's hash region", offset)
        case let .partitionShortOfItsSectors(partition, declared, covered):
            return "WIA/RVZ partition \(partition) declares \(declared) sectors but its groups cover only \(covered)"
        case let .writePastEndOfDisc(what, offset, length, discSize):
            return "WIA/RVZ \(what) would write \(length) bytes at \(offset), past the "
                + "\(discSize)-byte disc the image declares"
        }
    }
}

public struct RVZImage {

    /// Bytes of user data per Wii cluster, and per cluster on disc. Repeated
    /// here rather than reached for from the Wii engine, because the WIA/RVZ
    /// geometry is defined in these terms and this module has no Wii
    /// dependency.
    public static let userDataPerCluster = 0x7C00
    public static let clusterSize = 0x8000
    public static let hashBlockSize = 0x400
    public static let clustersPerGroup = 64
    /// Decrypted bytes in one 2 MiB group: 64 × 0x7C00.
    public static let groupDataSize = clustersPerGroup * userDataPerCluster

    public let header: WIAFileHeader
    public let disc: WIADisc
    public let partitions: [WIAPartition]
    public let rawData: [WIARawData]
    public let groups: [WIAGroupEntry]

    /// True when the file is the RVZ variant. Taken from the magic, which is
    /// what the reference implementation dispatches on — `WIADisc.isRVZ`
    /// infers it from the compression and chunk size instead, and that is a
    /// heuristic. The distinction decides the group entry's width, so
    /// guessing it wrong misreads the whole table.
    public let isRVZ: Bool

    private let source: GoDReadable

    /// Bytes of disc space one group covers.
    public var chunkSize: Int { Int(disc.chunkSize) }

    /// Bytes of *decrypted partition data* one group covers: the same span
    /// with its hash blocks removed.
    public var chunkDataSize: Int {
        chunkSize / RVZImage.clusterSize * RVZImage.userDataPerCluster
    }

    /// Exception lists a Wii partition group carries. Always
    /// `chunkSize / 2 MiB`, and at least one — an RVZ chunk smaller than
    /// 2 MiB carries exactly one, covering only itself.
    public var exceptionListsPerGroup: Int {
        max(1, chunkDataSize / RVZImage.groupDataSize)
    }

    // MARK: - Parse

    public init(binary: GoDReadable) throws {
        self.source = binary

        guard let headerBytes = binary.read(atAddress: 0, length: UInt(WIAFileHeader.fixedSize)) else {
            throw RVZError.truncated(what: "file header")
        }
        let header = try WIAFileHeader(binary: headerBytes)
        self.header = header
        self.isRVZ = header.magic == WIAFileHeader.rvzMagic

        // `file_head_hash` covers the struct up to but not including itself.
        guard let hashed = headerBytes.read(atAddress: 0, length: 0x34) else {
            throw RVZError.truncated(what: "file header")
        }
        guard SHA1.hash(hashed.rawBytes) == header.fileHeadHash else {
            throw RVZError.headerHashMismatch(field: "file_head_hash")
        }

        guard let discBytes = binary.read(
            atAddress: UInt(WIAFileHeader.fixedSize),
            length: UInt(header.discSize)
        ) else {
            throw RVZError.truncated(what: "disc struct")
        }
        // The hash covers `disc_size` bytes, which may include trailing
        // `compr_data` the parser ignores.
        guard SHA1.hash(discBytes.rawBytes) == header.discHash else {
            throw RVZError.headerHashMismatch(field: "disc_hash")
        }
        let disc = try WIADisc(binary: discBytes)
        self.disc = disc

        switch disc.compression {
        case .none, .zstd:
            break
        case .purge:
            throw RVZError.unsupportedCompression("PURGE (a legacy WIA mode Dolphin itself no longer writes)")
        case .bzip2:
            throw RVZError.unsupportedCompression("bzip2")
        case .lzma:
            throw RVZError.unsupportedCompression("LZMA")
        case .lzma2:
            throw RVZError.unsupportedCompression("LZMA2")
        }
        if isRVZ && disc.compression == .purge {
            throw RVZError.unsupportedCompression("PURGE, which RVZ does not allow")
        }

        // Chunk size rules: a multiple of 2 MiB, or — RVZ only — a power of
        // two from 32 KiB up.
        let chunk = Int(disc.chunkSize)
        let twoMiB = 0x20_0000
        if chunk == 0 {
            throw RVZError.invalidChunkSize(disc.chunkSize)
        } else if chunk % twoMiB == 0 {
            // Fine for both variants.
        } else if isRVZ, chunk >= 0x8000, chunk & (chunk - 1) == 0 {
            // Fine for RVZ.
        } else {
            throw RVZError.invalidChunkSize(disc.chunkSize)
        }
        guard chunk % RVZImage.clusterSize == 0 else {
            throw RVZError.invalidChunkSize(disc.chunkSize)
        }

        // Partition table: uncompressed, `part_t_size` bytes per entry so a
        // future wider struct still reads.
        let partitionStride = Int(disc.partitionStructSize)
        let partitionTableSize = Int(disc.partitionCount) * partitionStride
        var partitions = [WIAPartition]()
        if partitionTableSize > 0 {
            guard partitionStride > 0 else {
                throw RVZError.truncated(what: "partition table")
            }
            guard let table = binary.read(
                atAddress: UInt(disc.partitionTableOffset),
                length: UInt(partitionTableSize)
            ) else {
                throw RVZError.truncated(what: "partition table")
            }
            guard SHA1.hash(table.rawBytes) == disc.partitionHash else {
                throw RVZError.headerHashMismatch(field: "part_hash")
            }
            let bytes = table.rawBytes
            partitions.reserveCapacity(Int(disc.partitionCount))
            for i in 0..<Int(disc.partitionCount) {
                var entry = Array(bytes[(i * partitionStride)..<min((i + 1) * partitionStride, bytes.count)])
                if entry.count < WIAPartition.byteSize {
                    entry.append(contentsOf: [UInt8](repeating: 0, count: WIAPartition.byteSize - entry.count))
                }
                partitions.append(try WIAPartition(
                    binary: GoDData(byteStream: entry, byteOrder: .big),
                    at: 0
                ))
            }
        }
        self.partitions = partitions

        // Raw-data and group tables are compressed with the file's method.
        let rawTable = try RVZImage.readCompressedTable(
            from: binary,
            offset: disc.rawDataOffset,
            compressedSize: Int(disc.rawDataCompressedSize),
            expectedSize: Int(disc.rawDataCount) * WIARawData.byteSize,
            compression: disc.compression,
            what: "raw-data table"
        )
        var rawData = [WIARawData]()
        rawData.reserveCapacity(Int(disc.rawDataCount))
        let rawTableData = GoDData(byteStream: rawTable, byteOrder: .big)
        for i in 0..<Int(disc.rawDataCount) {
            rawData.append(try WIARawData(binary: rawTableData, at: i * WIARawData.byteSize))
        }
        self.rawData = rawData

        let groupStride = isRVZ ? WIAGroupEntry.rvzByteSize : WIAGroupEntry.wiaByteSize
        let groupTable = try RVZImage.readCompressedTable(
            from: binary,
            offset: disc.groupTableOffset,
            compressedSize: Int(disc.groupTableCompressedSize),
            expectedSize: Int(disc.groupCount) * groupStride,
            compression: disc.compression,
            what: "group table"
        )
        var groups = [WIAGroupEntry]()
        groups.reserveCapacity(Int(disc.groupCount))
        let groupTableData = GoDData(byteStream: groupTable, byteOrder: .big)
        for i in 0..<Int(disc.groupCount) {
            if isRVZ {
                groups.append(try WIAGroupEntry(rvzBinary: groupTableData, at: i * groupStride))
            } else {
                groups.append(try WIAGroupEntry(wiaBinary: groupTableData, at: i * groupStride))
            }
        }
        self.groups = groups
    }

    private static func readCompressedTable(
        from binary: GoDReadable,
        offset: UInt64,
        compressedSize: Int,
        expectedSize: Int,
        compression: WIADisc.Compression,
        what: String
    ) throws -> [UInt8] {
        guard expectedSize > 0 else { return [] }
        guard compressedSize > 0,
              let stored = binary.read(atAddress: UInt(offset), length: UInt(compressedSize)) else {
            throw RVZError.truncated(what: what)
        }
        let decompressed = try decompress(stored.rawBytes, compression: compression, expectedSize: expectedSize)
        guard decompressed.count >= expectedSize else {
            throw RVZError.truncated(what: what)
        }
        return decompressed
    }

    private static func decompress(
        _ bytes: [UInt8],
        compression: WIADisc.Compression,
        expectedSize: Int?
    ) throws -> [UInt8] {
        switch compression {
        case .none:
            return bytes
        case .zstd:
            return try Zstd.decompress(bytes, expectedSize: expectedSize)
        case .purge, .bzip2, .lzma, .lzma2:
            // Rejected at parse time; repeated here so a new call site can't
            // slip past the check.
            throw RVZError.unsupportedCompression("\(compression)")
        }
    }

    // MARK: - Group payloads

    /// Everything one group carries, unwrapped.
    struct GroupContents {
        var data: [UInt8]
        var exceptionLists: [WIAExceptionList]
    }

    /// Read, decompress and unpack one group.
    ///
    /// The payload is layered: the file's compression on the outside, then
    /// the exception lists, then the RVZ packing. An RVZ group may opt out of
    /// compression individually (bit 31 of `data_size` clear), and when it
    /// does its exception lists are stored plainly and padded to a 4-byte
    /// boundary — the one place the layering changes shape.
    ///
    /// - Parameters:
    ///   - dataSize: bytes of disc or partition data this group must yield.
    ///   - dataOffset: where the group's first byte lands within its own
    ///     region, which is what positions the junk PRNG.
    func readGroup(
        index: Int,
        dataSize: Int,
        exceptionListCount: Int,
        dataOffset: Int
    ) throws -> GroupContents {
        guard index >= 0, index < groups.count else {
            throw RVZError.groupIndexOutOfRange(index: index, count: groups.count)
        }
        let entry = groups[index]

        // A stored size of 0 means "all zeros, no exceptions" — no IO at all.
        if entry.dataSize == 0 {
            return GroupContents(
                data: [UInt8](repeating: 0, count: dataSize),
                exceptionLists: Array(repeating: WIAExceptionList(), count: exceptionListCount)
            )
        }

        guard let stored = source.read(
            atAddress: UInt(entry.dataOffset),
            length: UInt(entry.dataSize)
        ) else {
            throw RVZError.truncated(what: "group \(index)'s payload")
        }
        let raw = stored.rawBytes

        var groupCompression = disc.compression
        var packedSize = 0
        if case let .rvz(_, _, isCompressed, rvzPackedSize) = entry {
            if !isCompressed { groupCompression = .none }
            packedSize = Int(rvzPackedSize)
        }

        // With a real compressor the exception lists are inside the stream;
        // with NONE they precede it, 4-byte aligned.
        let body: [UInt8]
        var exceptionLists = [WIAExceptionList]()
        exceptionLists.reserveCapacity(exceptionListCount)
        if groupCompression == .none {
            var cursor = 0
            for _ in 0..<exceptionListCount {
                let (list, consumed) = try WIAExceptionList.decode(from: raw, at: cursor)
                exceptionLists.append(list)
                cursor += consumed
            }
            if exceptionListCount > 0 {
                cursor = (cursor + 3) & ~3
            }
            guard cursor <= raw.count else {
                throw RVZError.truncated(what: "group \(index)'s exception lists")
            }
            body = Array(raw[cursor...])
        } else {
            let decompressed = try RVZImage.decompress(
                raw,
                compression: groupCompression,
                expectedSize: packedSize > 0 ? packedSize : dataSize
            )
            var cursor = 0
            for _ in 0..<exceptionListCount {
                let (list, consumed) = try WIAExceptionList.decode(from: decompressed, at: cursor)
                exceptionLists.append(list)
                cursor += consumed
            }
            guard cursor <= decompressed.count else {
                throw RVZError.truncated(what: "group \(index)'s exception lists")
            }
            body = Array(decompressed[cursor...])
        }

        let data: [UInt8]
        if packedSize > 0 {
            guard body.count == packedSize else {
                throw RVZError.packedSizeMismatch(group: index, expected: packedSize, found: body.count)
            }
            data = try RVZPacking.unpack(body, expandedSize: dataSize, dataOffset: dataOffset)
        } else {
            data = body
        }
        guard data.count == dataSize else {
            throw RVZError.groupSizeMismatch(group: index, expected: dataSize, found: data.count)
        }
        return GroupContents(data: data, exceptionLists: exceptionLists)
    }

    // MARK: - Disc regions

    /// Which part of the image covers a span of the disc.
    enum DiscRegionKind: Equatable {
        case raw(entry: Int)
        case partition(index: Int)
    }

    struct DiscRegion: Equatable {
        var discRange: Range<Int>
        var kind: DiscRegionKind
    }

    /// One cacheable unit of restored disc bytes: the smallest span the image
    /// can produce without doing the work twice.
    ///
    /// For a raw region that is one chunk; for a Wii partition it is a whole
    /// 2 MiB group, because producing any byte of one means decompressing
    /// every chunk that feeds it and running a hash-and-encrypt pass over the
    /// lot.
    public struct RestoredBlock {
        public let discRange: Range<Int>
        public let bytes: [UInt8]
    }

    /// Bytes of disc space one Wii partition group covers.
    static var partitionGroupDiscSize: Int { clustersPerGroup * clusterSize }

    /// Where a partition sits and how much of it there is.
    struct PartitionGeometry {
        var firstSector: Int
        var totalSectors: Int
        var discRange: Range<Int>
        /// Total decrypted bytes, at `userDataPerCluster` per sector.
        var dataSize: Int
    }

    func geometry(ofPartition index: Int) -> PartitionGeometry {
        let partition = partitions[index]
        let firstSector = Int(partition.managementSegment.firstSector)
        let secondCount = Int(partition.dataSegment.sectorCount)
        // The two segments together cover the partition. wit splits at the
        // FST end rounded up to 2 MiB and leaves segment 1 empty when there
        // is nothing past it.
        let totalSectors = secondCount != 0
            ? Int(partition.dataSegment.firstSector) - firstSector + secondCount
            : Int(partition.managementSegment.sectorCount)
        let start = firstSector * RVZImage.clusterSize
        return PartitionGeometry(
            firstSector: firstSector,
            totalSectors: totalSectors,
            discRange: start..<(start + totalSectors * RVZImage.clusterSize),
            dataSize: totalSectors * RVZImage.userDataPerCluster
        )
    }

    /// Every region the image covers, partitions first.
    ///
    /// Partitions are searched before raw data so that where the two overlap,
    /// the partition wins — the order the buffer-building restore wrote them
    /// in, and therefore the behaviour that is already measured. Nothing in
    /// the corpus overlaps, but the precedence costs nothing to preserve and
    /// means the lookup needs no disjointness assumption.
    var discRegions: [DiscRegion] {
        var regions = [DiscRegion]()
        regions.reserveCapacity(partitions.count + rawData.count)
        for index in partitions.indices {
            regions.append(DiscRegion(discRange: geometry(ofPartition: index).discRange,
                                      kind: .partition(index: index)))
        }
        for (index, entry) in rawData.enumerated() {
            // The first entry says it starts at 0x80 and is 0x4FF80 bytes,
            // but it really covers 0x50000 from offset 0. The rule is
            // general: round the offset down to a cluster boundary and grow
            // the size to match, rather than special-casing that entry.
            let stored = Int(entry.discOffset)
            let skipped = stored % RVZImage.clusterSize
            let start = stored - skipped
            let size = Int(entry.size) + skipped
            guard size > 0 else { continue }
            regions.append(DiscRegion(discRange: start..<(start + size), kind: .raw(entry: index)))
        }
        return regions
    }

    /// Check the structural assumptions a restore depends on, without
    /// reading any group. Called once, so a malformed image fails before any
    /// work rather than partway through a 4.7 GB output.
    func validateLayout() throws {
        for index in partitions.indices {
            let partition = partitions[index]
            let geometry = geometry(ofPartition: index)
            var dataCursor = 0
            for segment in [partition.managementSegment, partition.dataSegment] {
                guard segment.sectorCount > 0 else { continue }
                let segmentDataOffset = (Int(segment.firstSector) - geometry.firstSector)
                    * RVZImage.userDataPerCluster
                guard segmentDataOffset == dataCursor else {
                    throw RVZError.nonContiguousPartitionSegments(partition: index)
                }
                dataCursor += Int(segment.sectorCount) * RVZImage.userDataPerCluster
            }
            guard dataCursor == geometry.dataSize else {
                throw RVZError.partitionShortOfItsSectors(
                    partition: index,
                    declared: geometry.totalSectors,
                    covered: dataCursor / RVZImage.userDataPerCluster
                )
            }
        }
    }

    // MARK: - Block production

    /// The block of restored disc bytes containing `discOffset`, or nil when
    /// no region covers it — an unclaimed run, which reads as zeroes.
    ///
    /// This is the one place restored bytes are produced. Both the
    /// buffer-building `restoreISO` and the lazy `RVZDiscImageView` go
    /// through it, so they cannot drift apart.
    public func block(
        containingDiscOffset discOffset: Int,
        partitionRestorer: WiiPartitionRestorer? = nil
    ) throws -> RestoredBlock? {
        guard let region = discRegions.first(where: { $0.discRange.contains(discOffset) }) else {
            return nil
        }
        switch region.kind {
        case let .raw(entry):
            return try rawBlock(entry: entry, region: region, discOffset: discOffset)
        case let .partition(index):
            guard let partitionRestorer else {
                throw RVZError.missingPartitionRestorer(partitionCount: partitions.count)
            }
            return try partitionBlock(
                index: index,
                region: region,
                discOffset: discOffset,
                restorer: partitionRestorer
            )
        }
    }

    private func rawBlock(entry: Int, region: DiscRegion, discOffset: Int) throws -> RestoredBlock {
        let descriptor = rawData[entry]
        let offsetInEntry = (discOffset - region.discRange.lowerBound) / chunkSize * chunkSize
        let start = region.discRange.lowerBound + offsetInEntry
        let length = min(chunkSize, region.discRange.upperBound - start)
        let contents = try readGroup(
            index: Int(descriptor.firstGroupIndex) + offsetInEntry / chunkSize,
            dataSize: length,
            exceptionListCount: 0,
            dataOffset: offsetInEntry
        )
        return RestoredBlock(discRange: start..<(start + length), bytes: contents.data)
    }

    private func partitionBlock(
        index: Int,
        region: DiscRegion,
        discOffset: Int,
        restorer: WiiPartitionRestorer
    ) throws -> RestoredBlock {
        let groupDiscSize = RVZImage.partitionGroupDiscSize
        let wiiGroup = (discOffset - region.discRange.lowerBound) / groupDiscSize
        let bytes = try encryptedPartitionGroup(index: index, wiiGroup: wiiGroup, restorer: restorer)
        let start = region.discRange.lowerBound + wiiGroup * groupDiscSize
        return RestoredBlock(discRange: start..<(start + bytes.count), bytes: bytes)
    }

    /// Produce one 2 MiB group of a Wii partition, encrypted.
    ///
    /// Gathers every chunk that feeds the group — 16 of them at the usual
    /// 128 KiB chunk size — collects their hash exceptions, zero-pads a short
    /// final group, and hands the lot to the Wii layer. A chunk never
    /// straddles a group boundary: below 2 MiB a chunk is a power-of-two
    /// number of clusters dividing 64, above it a whole multiple of 64, and a
    /// segment always starts on a group boundary.
    ///
    /// The returned bytes are truncated to the partition's real sectors, so a
    /// partition ending partway through a group writes only what it has.
    func encryptedPartitionGroup(
        index: Int,
        wiiGroup: Int,
        restorer: WiiPartitionRestorer
    ) throws -> [UInt8] {
        let partition = partitions[index]
        let geometry = geometry(ofPartition: index)
        let groupDataSize = RVZImage.groupDataSize
        let dataStart = wiiGroup * groupDataSize
        guard dataStart < geometry.dataSize else {
            throw RVZError.groupIndexOutOfRange(index: wiiGroup, count: groups.count)
        }
        let presentBytes = min(groupDataSize, geometry.dataSize - dataStart)
        let dataEnd = dataStart + presentBytes

        // Absent clusters hash as zeroes, and their hashes still land in the
        // hash blocks of the clusters that exist — so the window is always a
        // whole group.
        var window = [UInt8](repeating: 0, count: groupDataSize)
        var exceptions = [WIAExceptionList.Exception]()

        for segment in [partition.managementSegment, partition.dataSegment] {
            guard segment.sectorCount > 0 else { continue }
            let segmentDataOffset = (Int(segment.firstSector) - geometry.firstSector)
                * RVZImage.userDataPerCluster
            let segmentDataSize = Int(segment.sectorCount) * RVZImage.userDataPerCluster
            guard segmentDataOffset < dataEnd, segmentDataOffset + segmentDataSize > dataStart else {
                continue
            }

            // Only the chunks overlapping this group are read.
            let firstChunk = max(0, (dataStart - segmentDataOffset) / chunkDataSize)
            for i in firstChunk..<Int(segment.groupCount) {
                let offsetInSegment = i * chunkDataSize
                guard offsetInSegment < segmentDataSize else { break }
                let absoluteOffset = segmentDataOffset + offsetInSegment
                guard absoluteOffset < dataEnd else { break }
                let length = min(chunkDataSize, segmentDataSize - offsetInSegment)

                let contents = try readGroup(
                    index: Int(segment.firstGroupIndex) + i,
                    dataSize: length,
                    exceptionListCount: exceptionListsPerGroup,
                    // Segment-relative, as the reference reader does. The two
                    // agree modulo 32 KiB because a segment always starts on
                    // a 2 MiB boundary.
                    dataOffset: offsetInSegment
                )

                let copyStart = max(absoluteOffset, dataStart)
                let copyEnd = min(absoluteOffset + length, dataEnd)
                if copyEnd > copyStart {
                    let sourceStart = copyStart - absoluteOffset
                    let destination = copyStart - dataStart
                    window.replaceSubrange(
                        destination..<(destination + (copyEnd - copyStart)),
                        with: contents.data[sourceStart..<(sourceStart + (copyEnd - copyStart))]
                    )
                }

                // Map each list onto the 2 MiB group it describes, keeping
                // only this one's. Below 2 MiB a chunk carries one list whose
                // offsets start at the chunk, so they shift by where the
                // chunk sits in its group; at or above 2 MiB a chunk starts on
                // a group boundary and the same expression is zero.
                let shift = (absoluteOffset % groupDataSize)
                    / RVZImage.userDataPerCluster * RVZImage.hashBlockSize
                for (listIndex, list) in contents.exceptionLists.enumerated() {
                    guard !list.exceptions.isEmpty else { continue }
                    guard absoluteOffset / groupDataSize + listIndex == wiiGroup else { continue }
                    for exception in list.exceptions {
                        // Widened before adding: both halves are 16-bit and
                        // their sum can leave the range, which a malformed
                        // image should be told about rather than trap on.
                        let shifted = Int(exception.offset) + shift
                        guard shifted >= 0,
                              shifted + 20 <= RVZImage.clustersPerGroup * RVZImage.hashBlockSize,
                              shifted <= Int(UInt16.max) else {
                            throw RVZError.exceptionOffsetOutOfRange(exception.offset)
                        }
                        exceptions.append(
                            WIAExceptionList.Exception(offset: UInt16(shifted), hash: exception.hash)
                        )
                    }
                }
            }
        }

        let encrypted = try restorer.encryptGroup(
            decryptedUserData: window,
            titleKey: partition.titleKey,
            hashExceptions: exceptions
        )
        let sectors = presentBytes / RVZImage.userDataPerCluster
        let bytesToKeep = sectors * RVZImage.clusterSize
        return bytesToKeep < encrypted.count ? Array(encrypted.prefix(bytesToKeep)) : encrypted
    }

    // MARK: - Restore

    /// A random-access view over the restored disc, decoding on demand.
    ///
    /// The form to prefer: `FileHandleAccess.write` pulls a `GoDReadable` in
    /// 8 MB windows, so writing one of these to disk costs a couple of cached
    /// blocks rather than the whole image. `restoreISO` remains for callers
    /// that genuinely need the bytes in hand.
    public func discImageView(
        partitionRestorer: WiiPartitionRestorer? = nil
    ) throws -> RVZDiscImageView {
        if !partitions.isEmpty && partitionRestorer == nil {
            throw RVZError.missingPartitionRestorer(partitionCount: partitions.count)
        }
        try validateLayout()
        return RVZDiscImageView(image: self, partitionRestorer: partitionRestorer)
    }

    /// Rebuild the raw disc image into one buffer.
    ///
    /// Costs the size of the disc, so `discImageView` is what the operations
    /// use — `writeFile` streams a readable and never needs this. Kept for
    /// callers that genuinely want the bytes in hand, and because it is the
    /// reference the view is checked against.
    public func restoreISO(
        partitionRestorer: WiiPartitionRestorer? = nil,
        logger: Logger? = nil
    ) throws -> GoDData {
        let view = try discImageView(partitionRestorer: partitionRestorer)
        logger?.log(.info("Restoring \(disc.discType) image: \(view.length) bytes, "
            + "\(groups.count) groups of \(chunkSize) bytes, \(disc.compression) compression"))
        return try view.materialized()
    }
}

// MARK: - Lazy disc view

/// Random-access read over the disc a WIA/RVZ image restores to, decoding
/// only what is asked for.
///
/// A class, and caching, for the same reasons `WiiDecryptedPartitionView` is:
/// the unit of work is far larger than the unit of access, so consecutive
/// reads inside one block have to hit the same decoded bytes. A Wii partition
/// block is a whole 2 MiB group — decompressing its 16 chunks and running a
/// hash-and-encrypt pass over them once per 8 MB write is the same total work
/// the buffer-building restore does; once per `read` would not be.
///
/// `allData` is deliberately left nil, as on the other decoding views: a
/// caller that wants the whole disc in memory should say so by asking
/// `RVZImage.restoreISO()`, not by having a view quietly hand over
/// several gigabytes.
public final class RVZDiscImageView: GoDReadable {

    public let byteOrder: ByteOrder = .big
    public let length: Int

    private let image: RVZImage
    private let partitionRestorer: WiiPartitionRestorer?

    /// Decoded blocks, most recently used last. Bounded by bytes rather than
    /// by count because a block is one chunk in a raw region and 2 MiB in a
    /// partition, and a count-based bound would mean very different memory
    /// for the two.
    private var cache: [RVZImage.RestoredBlock] = []
    private var cachedBytes = 0
    private let cacheLimitBytes: Int

    init(
        image: RVZImage,
        partitionRestorer: WiiPartitionRestorer?,
        cacheLimitBytes: Int = 16 << 20
    ) {
        self.image = image
        self.partitionRestorer = partitionRestorer
        self.length = Int(image.header.isoFileSize)
        self.cacheLimitBytes = max(cacheLimitBytes, RVZImage.partitionGroupDiscSize)
    }

    public func read(atAddress address: UInt, length readLength: UInt) -> GoDData? {
        let start = Int(address)
        let end = start + Int(readLength)
        guard start >= 0, end <= self.length, readLength > 0 else { return nil }

        // Starts zeroed: a run no region covers reads as zeroes, which is
        // what the buffer-building restore produced by never writing there.
        var out = [UInt8](repeating: 0, count: Int(readLength))
        var cursor = start
        while cursor < end {
            guard let block = blockContaining(cursor) else {
                // Skip to the next region rather than probing byte by byte.
                cursor = nextRegionStart(after: cursor) ?? end
                continue
            }
            let copyStart = max(block.discRange.lowerBound, cursor)
            let copyEnd = min(block.discRange.upperBound, end)
            guard copyEnd > copyStart else {
                // A block that does not reach `cursor` would loop forever.
                cursor = max(block.discRange.upperBound, cursor + 1)
                continue
            }
            let sourceStart = copyStart - block.discRange.lowerBound
            let count = copyEnd - copyStart
            // A block's bytes can be shorter than its declared range only if
            // the image is malformed; clamp rather than trap.
            guard sourceStart + count <= block.bytes.count else { return nil }
            out.replaceSubrange(
                (copyStart - start)..<(copyStart - start + count),
                with: block.bytes[sourceStart..<(sourceStart + count)]
            )
            cursor = copyEnd
        }

        // The first 0x80 bytes come from the disc struct, not from a group.
        // The raw region covering the start of the disc does hold bytes for
        // them, but they are not the disc's — the reference reader answers
        // from its own copy of the header the same way, and applying it last
        // here is what makes the buffer-building restore and this view agree.
        let headerSize = WIADisc.discHeaderSize
        if start < headerSize {
            let overlap = min(end, headerSize) - start
            let header = image.disc.discHeader
            guard header.count >= start + overlap else { return nil }
            out.replaceSubrange(0..<overlap, with: header[start..<(start + overlap)])
        }
        return GoDData(byteStream: out, byteOrder: .big)
    }

    // MARK: - Cache

    private func blockContaining(_ discOffset: Int) -> RVZImage.RestoredBlock? {
        if let hit = cache.firstIndex(where: { $0.discRange.contains(discOffset) }) {
            let block = cache.remove(at: hit)
            cache.append(block)
            return block
        }
        guard let block = try? image.block(
            containingDiscOffset: discOffset,
            partitionRestorer: partitionRestorer
        ) else {
            return nil
        }
        cache.append(block)
        cachedBytes += block.bytes.count
        while cachedBytes > cacheLimitBytes, cache.count > 1 {
            cachedBytes -= cache.removeFirst().bytes.count
        }
        return block
    }

    /// The start of the first region beginning after `offset`, so an
    /// unclaimed run is skipped in one step instead of one byte at a time.
    private func nextRegionStart(after offset: Int) -> Int? {
        image.discRegions
            .map(\.discRange.lowerBound)
            .filter { $0 > offset }
            .min()
    }
}
