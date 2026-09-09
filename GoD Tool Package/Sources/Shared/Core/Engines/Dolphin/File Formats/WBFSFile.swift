//
//  WBFSFile.swift
//
//  WBFS ("Wii Backup File System") — the container USB loaders and wit
//  store Wii discs in. A WBFS file is a tiny partition: a header naming
//  its sector geometry, a table of disc slots, and for each disc a copy of
//  the disc header plus a block map (`wlba`) that sends every block of the
//  logical 4.7 GB image to a block in the file, or to nothing. Unallocated
//  blocks read as zero. No compression, no crypto: the disc data is stored
//  verbatim, still encrypted as it is on the disc.
//
//  The restored image is a view, not a buffer. Setup hands it to the same
//  streaming copy a raw `.iso` goes through, so peak memory is one copy
//  chunk rather than the disc.
//
//  Reference: Documentation/File Formats/Shared/WBFS - Wii Backup File System.md
//  (layout from libwbfs — `wbfs_open_partition`, `wbfs_open_disc`,
//  `wbfs_disc_read`)
//

import Foundation
import GoDFoundation

public struct WBFSFile {

    public static let formatName = "wbfs"
    public static let magic: [UInt8] = [0x57, 0x42, 0x46, 0x53]  // "WBFS"
    /// Bytes 0x00–0x0B; the disc table follows immediately.
    public static let headerSize = 12
    public static let maxDiscSlots = 500

    /// A single-layer Wii disc is 143 432 sectors of 0x8000 bytes. libwbfs
    /// hardcodes it, and every block map is sized from it — a WBFS cannot
    /// hold a dual-layer image.
    public static let wiiSectorSizeShift = 15
    public static let wiiSectorCount = 143_432
    public static let wiiDiscSize = wiiSectorCount << wiiSectorSizeShift  // 0x1_1824_0000

    public enum Error: Swift.Error, CustomStringConvertible {
        case notAWBFS
        case unsupportedGeometry(hdSectorSizeShift: Int, blockSizeShift: Int)
        case noDiscs
        case emptySlot(Int)
        case blockOutsideContainer(block: Int, discBlock: Int)

        public var description: String {
            switch self {
            case .notAWBFS:
                return "Input isn't a WBFS container (missing WBFS magic)"
            case let .unsupportedGeometry(hd, block):
                return "WBFS sector geometry is out of range (hd sector 2^\(hd), block 2^\(block))"
            case .noDiscs:
                return "WBFS container holds no discs"
            case .emptySlot(let slot):
                return "WBFS disc slot \(slot) is empty"
            case let .blockOutsideContainer(block, discBlock):
                return "WBFS block \(block) (disc block \(discBlock)) lies outside the container — truncated file?"
            }
        }
    }

    /// log2 of the "hard disk" sector size, the unit the container's layout
    /// is measured in. 512 bytes in practice.
    public let hdSectorSizeShift: Int
    /// log2 of the WBFS block size — the unit the disc is split into.
    /// 2 MiB in practice.
    public let blockSizeShift: Int
    /// hd sectors the container spans, per its own header.
    public let hdSectorCount: Int
    /// Disc slots in use, ascending.
    public let discSlots: [Int]

    private let backing: GoDReadable

    public var hdSectorSize: Int { 1 << hdSectorSizeShift }
    public var blockSize: Int { 1 << blockSizeShift }
    /// Blocks the container holds, per its header. Block 0 is the header
    /// and disc-info block and never holds disc data.
    public var blockCount: Int { hdSectorCount >> (blockSizeShift - hdSectorSizeShift) }
    /// Entries in each disc's block map. Floor division, so the tail of the
    /// disc past the last whole block (256 KiB at 2 MiB blocks) is never
    /// stored and reads as zero.
    public var blocksPerDisc: Int { WBFSFile.wiiSectorCount >> (blockSizeShift - WBFSFile.wiiSectorSizeShift) }
    /// One disc's record — 0x100-byte disc header plus the block map —
    /// rounded up to a whole hd sector.
    public var discInfoSize: Int {
        let raw = 0x100 + blocksPerDisc * 2
        let mask = hdSectorSize - 1
        return (raw + mask) & ~mask
    }

    /// Parses the container header and disc table. Disc block maps are read
    /// when a disc is opened, not here.
    public init(binary: GoDReadable) throws {
        guard binary.length >= WBFSFile.headerSize + WBFSFile.maxDiscSlots,
              let head = binary.read(atAddress: 0, length: WBFSFile.headerSize)?.rawBytes else {
            throw Error.notAWBFS
        }
        guard Array(head[0..<4]) == WBFSFile.magic else { throw Error.notAWBFS }

        let hdSectorCount = Int(head[4]) << 24 | Int(head[5]) << 16 | Int(head[6]) << 8 | Int(head[7])
        let hdShift = Int(head[8])
        let blockShift = Int(head[9])
        // 512-byte to 64 KiB hd sectors; 32 KiB (one Wii sector) to 64 MiB
        // blocks, never smaller than an hd sector. Anything else is not a
        // geometry libwbfs would have written.
        guard (9...16).contains(hdShift), (15...26).contains(blockShift), blockShift >= hdShift else {
            throw Error.unsupportedGeometry(hdSectorSizeShift: hdShift, blockSizeShift: blockShift)
        }

        guard let table = binary.read(atAddress: WBFSFile.headerSize, length: WBFSFile.maxDiscSlots)?.rawBytes else {
            throw Error.notAWBFS
        }
        let slots = table.enumerated().compactMap { $0.element != 0 ? $0.offset : nil }
        guard !slots.isEmpty else { throw Error.noDiscs }

        self.hdSectorSizeShift = hdShift
        self.blockSizeShift = blockShift
        self.hdSectorCount = hdSectorCount
        self.discSlots = slots
        self.backing = binary
    }

    /// The disc in `slot` as a full-size Wii image, read through its block
    /// map on demand.
    public func discImage(slot: Int) throws -> WBFSDiscImage {
        guard discSlots.contains(slot) else { throw Error.emptySlot(slot) }
        let infoOffset = hdSectorSize + slot * discInfoSize
        guard let header = backing.read(atAddress: infoOffset, length: 0x100),
              let table = backing.read(atAddress: infoOffset + 0x100, length: blocksPerDisc * 2)?.rawBytes else {
            throw Error.notAWBFS
        }
        var map = [Int](repeating: 0, count: blocksPerDisc)
        for i in 0..<blocksPerDisc {
            map[i] = Int(table[2 * i]) << 8 | Int(table[2 * i + 1])
        }
        // Every allocated block has to lie inside the container. Block 0 is
        // the header block, and a block past the end of the file means the
        // image was truncated — better to say so here than to fail a read
        // 3 GB into a copy.
        for (discBlock, block) in map.enumerated() where block != 0 {
            guard block < blockCount, (block + 1) << blockSizeShift <= backing.length else {
                throw Error.blockOutsideContainer(block: block, discBlock: discBlock)
            }
        }
        return WBFSDiscImage(backing: backing, blockMap: map, blockSizeShift: blockSizeShift, header: header)
    }

    /// The first disc in the container — what a single-disc `.wbfs`, the
    /// only kind loaders write, holds.
    public func firstDiscImage() throws -> WBFSDiscImage {
        try discImage(slot: discSlots[0])
    }
}

/// A Wii disc image resolved through a WBFS block map on every read.
///
/// `length` is the full single-layer disc; blocks the container never
/// allocated read as zero, which is what they were on the disc (the
/// container only drops all-zero blocks, or blocks a loader chose to
/// scrub). No `allData`: producing the buffer would mean holding 4.7 GB,
/// and every consumer of a disc image reads through `GoDReadable`.
public final class WBFSDiscImage: GoDReadable {
    public let byteOrder: ByteOrder = .big
    public let length: Int = WBFSFile.wiiDiscSize

    /// The 0x100-byte record header the container keeps beside the block
    /// map: the disc header — game ID, disc number, title — as the image's
    /// own first bytes have it. Not byte-identical to them: wit stamps an
    /// `MD5#` tag plus a digest over 0xEC–0xFF of the record.
    public let header: GoDData

    private let backing: GoDReadable
    private let blockMap: [Int]
    private let blockSizeShift: Int

    init(backing: GoDReadable, blockMap: [Int], blockSizeShift: Int, header: GoDData) {
        self.backing = backing
        self.blockMap = blockMap
        self.blockSizeShift = blockSizeShift
        self.header = header
    }

    /// Blocks the container stores for this disc.
    public var allocatedBlockCount: Int { blockMap.reduce(0) { $0 + ($1 != 0 ? 1 : 0) } }

    public func read(atAddress address: UInt, length: UInt) -> GoDData? {
        let start = Int(address)
        let count = Int(length)
        guard count > 0, start >= 0, start + count <= self.length else { return nil }

        let result = GoDData(length: count, byteOrder: .big)
        let blockSize = 1 << blockSizeShift
        var cursor = start
        var written = 0
        while written < count {
            let discBlock = cursor >> blockSizeShift
            let inBlock = cursor & (blockSize - 1)
            let n = min(blockSize - inBlock, count - written)
            // Past the map (the unstored tail) or unallocated: leave zeros.
            if discBlock < blockMap.count, blockMap[discBlock] != 0 {
                let source = (blockMap[discBlock] << blockSizeShift) + inBlock
                guard let chunk = backing.read(atAddress: source, length: n) else { return nil }
                result.write(chunk, atAddress: written)
            }
            cursor += n
            written += n
        }
        return result
    }
}
