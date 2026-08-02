//
//  GoDStreamedData.swift
//
//  A `GoDReadable` backed by a file on disk rather than by bytes in memory.
//
//  `GoDData` is the right shape for anything you intend to hold, edit and hand
//  around whole. It is the wrong shape for a disc image: a GameCube ISO is
//  1.4 GB and a Wii ISO 4.7 GB, of which a dump reads the boot header, the FST,
//  and then one member file at a time. Loading it as a `GoDData` costs the
//  whole image in RAM to read a few megabytes of it.
//
//  Every reader that takes a disc image should therefore accept `GoDReadable`,
//  not `GoDData`, and be handed one of these. Reads are served straight from
//  the file, so peak memory is the size of the largest single read rather than
//  the size of the image.
//
//  **Read semantics match `GoDData` exactly.** A range running past the end
//  returns nil rather than a short read — parsers depend on that, notably
//  `readString`/`readGSString`, which walk forward two bytes at a time and
//  stop when a read fails.
//
//  **Thread safety:** not synchronized, matching `GoDData` and
//  `FileSystemTree`. The handle carries one file offset and the block cache is
//  a plain dictionary, so concurrent reads of the same instance are undefined.
//  Open one per thread if you need to fan out.
//

import Foundation

public final class GoDStreamedData: GoDReadable {

    public let byteOrder: ByteOrder

    /// Total size of the backing file, read once at open. A file being
    /// appended to underneath us is out of scope — disc images don't grow
    /// while they're being dumped.
    public let length: Int

    public let file: File

    private var handle: FileHandle?

    // MARK: - Block cache
    //
    // Without this, `readGSString` would issue one syscall per character.
    // Reads that fit inside a block are served from a cached copy of that
    // block; larger reads bypass the cache entirely so that streaming a
    // 30 MB member file doesn't evict everything and cost 30 MB of cache.

    private static let blockSize = 0x10000    // 64 KB
    private static let maxCachedBlocks = 64   // 4 MB ceiling

    private var blocks: [Int: Data] = [:]
    private var blockOrder: [Int] = []

    // MARK: - Lifecycle

    public init(file: File, byteOrder: ByteOrder = .big) throws {
        let url = file.url
        guard let size = FileHandleAccess.fileSize(at: url) else {
            throw FSTErrors.fileNotFound(file, .init())
        }
        let opened: FileHandle
        do {
            opened = try FileHandle(forReadingFrom: url)
        } catch {
            throw FSTErrors.underlying("failed to open \(file) for streamed reading", error, .init())
        }
        self.file = file
        self.byteOrder = byteOrder
        self.length = size
        self.handle = opened
    }

    /// Releases the file descriptor. Reads after this return nil rather than
    /// trapping — a closed source behaves like a source with nothing in it.
    public func close() {
        try? handle?.close()
        handle = nil
        blocks.removeAll()
        blockOrder.removeAll()
    }

    deinit { close() }

    // MARK: - GoDReadable

    /// Reads the whole file. Defined because some callers legitimately need
    /// every byte — writing the image back out, handing it to a converter —
    /// but it is the one operation here that costs the file's full size in
    /// memory, which is what this type exists to avoid. Prefer `read`.
    public var allData: GoDData? {
        read(atAddress: 0, length: length)
    }


    public func read(atAddress address: UInt, length: UInt) -> GoDData? {
        let start = Int(address)
        let count = Int(length)
        let end = start + count
        // Same bounds contract as `GoDData.read`: out of range is nil, not a
        // short read.
        guard start >= 0, count >= 0, end <= self.length else { return nil }
        guard count > 0 else { return GoDData(byteOrder: byteOrder) }

        if count > Self.blockSize {
            guard let data = readDirect(offset: start, count: count) else { return nil }
            return GoDData(data: data, byteOrder: byteOrder)
        }

        var result = Data()
        result.reserveCapacity(count)
        var cursor = start
        while cursor < end {
            let index = cursor / Self.blockSize
            guard let block = block(at: index) else { return nil }
            let blockStart = index * Self.blockSize
            let from = cursor - blockStart
            let to = min(block.count, end - blockStart)
            guard from < to else { return nil }
            result.append(block.subdata(in: from..<to))
            cursor = blockStart + to
        }
        return GoDData(data: result, byteOrder: byteOrder)
    }

    // MARK: - Backing reads

    private func block(at index: Int) -> Data? {
        if let cached = blocks[index] { return cached }
        let offset = index * Self.blockSize
        let count = min(Self.blockSize, length - offset)
        guard count > 0, let data = readDirect(offset: offset, count: count) else { return nil }

        blocks[index] = data
        blockOrder.append(index)
        if blockOrder.count > Self.maxCachedBlocks {
            blocks.removeValue(forKey: blockOrder.removeFirst())
        }
        return data
    }

    private func readDirect(offset: Int, count: Int) -> Data? {
        guard let handle else { return nil }
        do {
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.read(upToCount: count), data.count == count else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
