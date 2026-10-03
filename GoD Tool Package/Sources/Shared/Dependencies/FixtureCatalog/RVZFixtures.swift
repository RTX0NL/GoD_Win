//
//  RVZFixtures.swift
//
//  Builds WIA and RVZ files for tests.
//
//  Deliberately an independent encoder: it writes raw fields at canonical
//  offsets straight from the format description rather than calling anything
//  in `RVZImage`, so a test that reads one back is cross-checking the reader
//  instead of round-tripping it against itself. Same reasoning as
//  `WiiDiscFixtures`, which stands in for a Wii disc mastering tool.
//
//  It can emit payloads three ways — stored plainly, wrapped in a Zstandard
//  frame of raw blocks, or RVZ-packed — because those are the three shapes
//  the reader has to unwrap, and a fixture that only ever used one would
//  leave the other two to the corpus tests.
//

import Foundation
import GoDFoundation
import Dolphin

public enum RVZFixtures {

    public static let clusterSize = 0x8000
    public static let userDataPerCluster = 0x7C00

    /// One non-partition span of the disc.
    public struct RawRegion {
        public var discOffset: UInt64
        public var data: [UInt8]

        public init(discOffset: UInt64, data: [UInt8]) {
            self.discOffset = discOffset
            self.data = data
        }
    }

    /// One Wii partition, given as the decrypted, hash-stripped payload its
    /// two segments cover.
    public struct Partition {
        public var titleKey: [UInt8]
        /// Absolute disc sector where the partition's encrypted data starts.
        public var firstSector: UInt32
        /// Sectors in the management segment (`pd[0]`).
        public var managementSectors: UInt32
        /// Sectors in the data segment (`pd[1]`). Zero leaves it empty.
        public var dataSectors: UInt32
        /// `managementSectors + dataSectors` clusters' worth of user data,
        /// at 0x7C00 per cluster.
        public var decryptedData: [UInt8]
        /// Exceptions for group `i` of the whole partition, keyed by the
        /// index of the group within its own segment's chunk sequence.
        public var exceptionsByChunk: [Int: [WIAExceptionList.Exception]]

        public init(
            titleKey: [UInt8],
            firstSector: UInt32,
            managementSectors: UInt32,
            dataSectors: UInt32,
            decryptedData: [UInt8],
            exceptionsByChunk: [Int: [WIAExceptionList.Exception]] = [:]
        ) {
            self.titleKey = titleKey
            self.firstSector = firstSector
            self.managementSectors = managementSectors
            self.dataSectors = dataSectors
            self.decryptedData = decryptedData
            self.exceptionsByChunk = exceptionsByChunk
        }
    }

    /// How a group's payload is stored.
    public enum PayloadEncoding {
        /// Written as-is, with the group's "compressed" flag clear.
        case stored
        /// Wrapped in a Zstandard frame built only of raw blocks — a valid
        /// frame the decoder must walk, with no entropy coding involved.
        case zstdRawFrame
    }

    public struct Image {
        public var isRVZ: Bool = true
        public var compression: WIADisc.Compression = .none
        public var chunkSize: UInt32 = 0x8000
        public var discType: WIADisc.DiscType = .gamecube
        /// First 0x80 bytes of the original disc.
        public var discHeader: [UInt8] = [UInt8](repeating: 0, count: 0x80)
        public var isoSize: UInt64 = 0
        public var rawRegions: [RawRegion] = []
        public var partitions: [Partition] = []
        public var encoding: PayloadEncoding = .stored
        /// Groups whose data is entirely zero are written as `data_size = 0`
        /// rather than stored, which is the format's no-IO shortcut.
        public var elideZeroGroups: Bool = true

        public init() {}
    }

    // MARK: - Build

    public static func build(_ image: Image) -> GoDData {
        // A payload wrapped in a Zstandard frame is marked "compressed",
        // which tells the reader to decompress it with the file's declared
        // method — so the two have to agree.
        precondition(
            image.encoding != .zstdRawFrame || image.compression == .zstd,
            "encoding .zstdRawFrame needs compression .zstd"
        )
        var groups: [(offset: Int, size: Int, compressed: Bool, packedSize: UInt32)] = []
        var payloads: [[UInt8]] = []

        let chunk = Int(image.chunkSize)
        let chunkDataSize = chunk / clusterSize * userDataPerCluster
        let exceptionListsPerGroup = max(1, chunkDataSize / (64 * userDataPerCluster))

        /// Records one group and returns nothing; payload offsets are fixed
        /// up once the tables' sizes are known.
        func addGroup(data: [UInt8], exceptionLists: [WIAExceptionList]) {
            let allZero = data.allSatisfy { $0 == 0 }
            let noExceptions = exceptionLists.allSatisfy { $0.exceptions.isEmpty }
            if image.elideZeroGroups && allZero && noExceptions {
                groups.append((offset: 0, size: 0, compressed: false, packedSize: 0))
                payloads.append([])
                return
            }
            var body = [UInt8]()
            for list in exceptionLists { body.append(contentsOf: list.encode()) }
            if !exceptionLists.isEmpty && image.encoding == .stored {
                // Uncompressed payloads pad the lists out to a 4-byte
                // boundary; compressed ones do not.
                while body.count % 4 != 0 { body.append(0) }
            }
            body.append(contentsOf: data)

            switch image.encoding {
            case .stored:
                groups.append((offset: 0, size: body.count, compressed: false, packedSize: 0))
                payloads.append(body)
            case .zstdRawFrame:
                let frame = zstdRawFrame(body)
                groups.append((offset: 0, size: frame.count, compressed: true, packedSize: 0))
                payloads.append(frame)
            }
        }

        // Raw-data entries.
        var rawEntries: [WIARawData] = []
        for region in image.rawRegions {
            let skipped = Int(region.discOffset) % clusterSize
            let alignedSize = region.data.count + skipped
            var padded = [UInt8](repeating: 0, count: skipped)
            padded.append(contentsOf: region.data)
            let firstGroup = groups.count
            var produced = 0
            while produced < alignedSize {
                let length = min(chunk, alignedSize - produced)
                addGroup(data: Array(padded[produced..<(produced + length)]), exceptionLists: [])
                produced += length
            }
            rawEntries.append(WIARawData(
                discOffset: region.discOffset,
                size: UInt64(region.data.count),
                firstGroupIndex: UInt32(firstGroup),
                groupCount: UInt32(groups.count - firstGroup)
            ))
        }

        // Partitions.
        var partitionEntries: [WIAPartition] = []
        for partition in image.partitions {
            var segments: [WIAPartitionSegment] = []
            var consumed = 0
            let counts = [partition.managementSectors, partition.dataSectors]
            var sectorCursor = partition.firstSector
            for (segmentIndex, sectors) in counts.enumerated() {
                guard sectors > 0 else {
                    segments.append(WIAPartitionSegment())
                    continue
                }
                let segmentBytes = Int(sectors) * userDataPerCluster
                let firstGroup = groups.count
                var produced = 0
                var chunkIndex = 0
                while produced < segmentBytes {
                    let length = min(chunkDataSize, segmentBytes - produced)
                    let slice = Array(
                        partition.decryptedData[(consumed + produced)..<(consumed + produced + length)]
                    )
                    // Exceptions are keyed per segment's chunk index for
                    // segment 0 and offset by 1000 for segment 1, so a test
                    // can address either without ambiguity.
                    let key = segmentIndex == 0 ? chunkIndex : 1000 + chunkIndex
                    var lists = [WIAExceptionList](repeating: WIAExceptionList(), count: exceptionListsPerGroup)
                    if let exceptions = partition.exceptionsByChunk[key], !exceptions.isEmpty {
                        lists[0] = WIAExceptionList(exceptions: exceptions)
                    }
                    addGroup(data: slice, exceptionLists: lists)
                    produced += length
                    chunkIndex += 1
                }
                segments.append(WIAPartitionSegment(
                    firstSector: sectorCursor,
                    sectorCount: sectors,
                    firstGroupIndex: UInt32(firstGroup),
                    groupCount: UInt32(groups.count - firstGroup)
                ))
                consumed += segmentBytes
                sectorCursor += sectors
            }
            partitionEntries.append(WIAPartition(
                titleKey: partition.titleKey,
                managementSegment: segments[0],
                dataSegment: segments.count > 1 ? segments[1] : WIAPartitionSegment()
            ))
        }

        // Lay the file out: head, disc, partition table, raw table, group
        // table, payloads.
        //
        // The group table stores the payload offsets, and its own compressed
        // size shifts where those payloads start — so the sizes are settled
        // first. That works because this encoder's "compression" is a frame
        // of raw blocks, whose length depends only on the plain length, not
        // on the bytes.
        let groupStride = image.isRVZ ? WIAGroupEntry.rvzByteSize : WIAGroupEntry.wiaByteSize
        let partitionTableOffset = WIAFileHeader.fixedSize + WIADisc.fixedFieldsSize
        let partitionTableSize = partitionEntries.count * WIAPartition.byteSize
        let rawTableOffset = partitionTableOffset + partitionTableSize
        let rawTableSize = storedSize(of: rawEntries.count * WIARawData.byteSize, with: image.compression)
        let groupTableOffset = rawTableOffset + rawTableSize
        let groupTableSize = storedSize(of: groups.count * groupStride, with: image.compression)
        var payloadCursor = groupTableOffset + groupTableSize
        // Payload offsets are stored divided by 4.
        payloadCursor = (payloadCursor + 3) & ~3
        for i in 0..<groups.count where groups[i].size > 0 {
            groups[i].offset = payloadCursor
            payloadCursor += payloads[i].count
            payloadCursor = (payloadCursor + 3) & ~3
        }

        let partitionTable = GoDData(byteOrder: .big)
        for entry in partitionEntries {
            let bytes = GoDData(length: WIAPartition.byteSize, byteOrder: .big)
            entry.write(into: bytes, at: 0)
            partitionTable.append(bytes)
        }
        let rawTablePlain = GoDData(byteOrder: .big)
        for entry in rawEntries {
            let bytes = GoDData(length: WIARawData.byteSize, byteOrder: .big)
            entry.write(into: bytes, at: 0)
            rawTablePlain.append(bytes)
        }
        let groupTablePlain = GoDData(byteOrder: .big)
        for group in groups {
            let entry: WIAGroupEntry = image.isRVZ
                ? .rvz(
                    dataOffsetDiv4: UInt32(group.offset / 4),
                    dataSize: UInt32(group.size),
                    isCompressed: group.compressed,
                    rvzPackedSize: group.packedSize
                )
                : .wia(dataOffsetDiv4: UInt32(group.offset / 4), dataSize: UInt32(group.size))
            let bytes = GoDData(length: groupStride, byteOrder: .big)
            entry.write(into: bytes, at: 0)
            groupTablePlain.append(bytes)
        }
        // Unlike the partition table, which the format stores plainly, the
        // raw-data and group tables go through the file's compressor. Their
        // stored sizes therefore change, which is why the payload offsets
        // computed above have to be recomputed below.
        let rawTable = compress(rawTablePlain, with: image.compression)
        let groupTable = compress(groupTablePlain, with: image.compression)
        precondition(rawTable.length == rawTableSize && groupTable.length == groupTableSize,
                     "table sizes must be predictable from their plain length")

        var disc = WIADisc(
            discType: image.discType,
            compression: image.compression,
            compressionLevel: 0,
            chunkSize: image.chunkSize,
            discHeader: image.discHeader,
            partitionCount: UInt32(partitionEntries.count),
            partitionStructSize: UInt32(WIAPartition.byteSize),
            partitionTableOffset: UInt64(partitionTableOffset),
            partitionHash: SHA1.hash(partitionTable.rawBytes),
            rawDataCount: UInt32(rawEntries.count),
            rawDataOffset: UInt64(rawTableOffset),
            rawDataCompressedSize: UInt32(rawTableSize),
            groupCount: UInt32(groups.count),
            groupTableOffset: UInt64(groupTableOffset),
            groupTableCompressedSize: UInt32(groupTableSize),
            compressionData: []
        )
        if partitionEntries.isEmpty {
            disc.partitionHash = SHA1.hash([])
        }
        let discBytes = disc.binaryData

        var header = WIAFileHeader(
            magic: image.isRVZ ? WIAFileHeader.rvzMagic : WIAFileHeader.wiaMagic,
            version: 0x0100_0000,
            versionCompatible: 0x0003_0000,
            discSize: UInt32(discBytes.length),
            discHash: SHA1.hash(discBytes.rawBytes),
            isoFileSize: image.isoSize,
            wiaFileSize: UInt64(payloadCursor),
            fileHeadHash: [UInt8](repeating: 0, count: 20)
        )
        // `file_head_hash` covers the struct up to but not including itself.
        let headPrefix = Array(header.binaryData.rawBytes[0..<0x34])
        header.fileHeadHash = SHA1.hash(headPrefix)

        let file = GoDData(length: payloadCursor, byteOrder: .big)
        file.write(header.binaryData, atAddress: 0)
        file.write(discBytes, atAddress: UInt(WIAFileHeader.fixedSize))
        if partitionTableSize > 0 {
            file.write(partitionTable, atAddress: UInt(partitionTableOffset))
        }
        if rawTableSize > 0 {
            file.write(rawTable, atAddress: UInt(rawTableOffset))
        }
        if groupTableSize > 0 {
            file.write(groupTable, atAddress: UInt(groupTableOffset))
        }
        for i in 0..<groups.count where groups[i].size > 0 {
            file.write(
                GoDData(byteStream: payloads[i], byteOrder: .big),
                atAddress: UInt(groups[i].offset)
            )
        }
        return file
    }

    // MARK: - Table compression

    /// Wrap a table in the file's compression. The partition table is
    /// exempt — the format stores that one plainly — but the raw-data and
    /// group tables both go through the compressor.
    private static func compress(_ table: GoDData, with compression: WIADisc.Compression) -> GoDData {
        guard table.length > 0 else { return table }
        switch compression {
        case .none:
            return table
        case .zstd:
            return GoDData(byteStream: zstdRawFrame(table.rawBytes), byteOrder: .big)
        case .purge, .bzip2, .lzma, .lzma2:
            // Only used to build images the reader is expected to refuse, so
            // the bytes past the header never matter.
            return table
        }
    }

    /// How many bytes `compress` will produce for a table of `plainSize`.
    private static func storedSize(of plainSize: Int, with compression: WIADisc.Compression) -> Int {
        guard plainSize > 0 else { return 0 }
        switch compression {
        case .zstd:
            let blocks = (plainSize + 0x1_FFFF) / 0x2_0000
            return 9 + blocks * 3 + plainSize   // magic + descriptor + size, then each block header
        default:
            return plainSize
        }
    }

    // MARK: - Zstandard framing

    /// A Zstandard frame carrying `bytes` as raw (uncompressed) blocks.
    ///
    /// Valid Zstandard by construction and trivial to write, which is the
    /// point: it lets a fixture exercise the container's "this group is
    /// compressed" path without the fixture needing a real encoder.
    public static func zstdRawFrame(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x28, 0xB5, 0x2F, 0xFD]
        out.append(0xA0)  // single segment, 4-byte content size, no checksum
        let size = UInt32(bytes.count)
        for i in 0..<4 { out.append(UInt8(truncatingIfNeeded: size >> (8 * i))) }

        let maxBlock = 0x2_0000  // 128 KiB, the format's ceiling
        var cursor = 0
        repeat {
            let length = min(maxBlock, bytes.count - cursor)
            let isLast = cursor + length >= bytes.count
            let header = UInt32(length) << 3 | (isLast ? 1 : 0)  // type 0 = raw
            out.append(UInt8(truncatingIfNeeded: header))
            out.append(UInt8(truncatingIfNeeded: header >> 8))
            out.append(UInt8(truncatingIfNeeded: header >> 16))
            out.append(contentsOf: bytes[cursor..<(cursor + length)])
            cursor += length
        } while cursor < bytes.count
        return out
    }
}
