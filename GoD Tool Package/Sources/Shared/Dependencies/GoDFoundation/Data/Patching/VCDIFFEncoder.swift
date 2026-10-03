//
//  VCDIFFEncoder.swift
//
//  Writes a VCDIFF patch: a window per chunk of the target, each one's bytes
//  described as copies from the source and literals where nothing matches.
//
//  This is the one format here whose writer does a real search, because it is
//  the only one whose instructions can say "these bytes are over there" — which
//  is the whole reason to reach for it. The search is deliberately plain:
//
//  * **A hash index over the source**, sampled every `stride` bytes rather than
//    at every offset. The stride grows with the source so the index stays
//    bounded — a 1.4 GB disc image would otherwise want tens of millions of
//    entries. A coarser stride finds fewer short matches and all the long ones,
//    which is the trade that suits whole files having moved.
//  * **Greedy, not optimal.** The first verified match at a position is taken
//    and extended; no attempt is made to find a better one a byte later.
//  * **Only three instruction codes**, each carrying its size explicitly, and
//    every address in SELF mode. That means nothing written here depends on the
//    address caches' state — a reader still has to implement them, because
//    other writers use them.
//
//  The result is a legal RFC 3284 stream that xdelta3 reads. The checksum
//  xdelta3 stamps on each window is *not* written: it is that tool's extension,
//  and a strict reader would reject a window flag it doesn't know. It is
//  verified on the way in, where it costs nothing and catches everything.
//

import Foundation

public struct VCDIFFEncoder {

    public var windowSize: Int
    /// The number of bytes a hash key covers, and the shortest match worth a
    /// COPY: below this, the instruction and address cost more than the bytes.
    public var blockSize: Int
    /// The ceiling on index entries, which sets the sampling stride.
    public var maximumIndexEntries: Int
    /// How far a single COPY may run. A match cannot usefully exceed the
    /// window it is in, so the default is the window size; verification reads
    /// the source in chunks regardless, so this is not a memory bound.
    public var maximumMatch: Int
    /// The shortest repeat worth a RUN instruction.
    public var minimumRun: Int

    public init(
        windowSize: Int = 8 << 20,
        blockSize: Int = 32,
        maximumIndexEntries: Int = 1 << 21,
        maximumMatch: Int? = nil,
        minimumRun: Int = 32
    ) {
        self.windowSize = windowSize
        self.blockSize = blockSize
        self.maximumIndexEntries = maximumIndexEntries
        self.maximumMatch = maximumMatch ?? windowSize
        self.minimumRun = minimumRun
    }

    public func encode(source: GoDReadable, target: GoDReadable) throws -> GoDData {
        let name = VCDIFFPatchCodec.formatName
        let sourceSize = source.length
        let targetSize = target.length

        var patch = VCDIFFPatch.magic + [VCDIFFPatch.supportedVersion]
        patch.append(0)   // no secondary compressor, no code table, no app header

        let index = sourceSize >= blockSize ? try buildIndex(of: source, name: name) : [:]

        var windowStart = 0
        while windowStart < targetSize {
            let windowLength = min(windowSize, targetSize - windowStart)
            try autoreleasepool {
                let bytes = try PatchDiff.read(target, at: windowStart, count: windowLength, name: name)
                let sections = try encodeWindow(bytes: bytes, source: source, index: index, name: name)
                patch += window(for: sections, sourceSize: sourceSize, targetLength: windowLength)
            }
            windowStart += windowLength
        }

        return GoDData(byteStream: patch, byteOrder: .big)
    }

    // MARK: - The source index

    /// `hash of blockSize bytes → offset`, sampled.
    private func buildIndex(of source: GoDReadable, name: String) throws -> [UInt64: Int] {
        let sourceSize = source.length
        let stride = self.stride(forSourceOfSize: sourceSize)
        var index = [UInt64: Int]()
        index.reserveCapacity(min(maximumIndexEntries, sourceSize / stride + 1))

        let chunkSize = 8 << 20
        var offset = 0
        while offset + blockSize <= sourceSize {
            try autoreleasepool {
                // Overlap by a block so a sample never straddles two chunks.
                let span = min(chunkSize + blockSize, sourceSize - offset)
                let chunk = try PatchDiff.read(source, at: offset, count: span, name: name)
                var position = 0
                while position + blockSize <= chunk.count {
                    let key = VCDIFFEncoder.hash(chunk, at: position, count: blockSize)
                    index[key] = offset + position
                    position += stride
                }
            }
            offset += chunkSize
        }
        return index
    }

    /// How often the source is sampled.
    ///
    /// Rounded up to a power of two, and that is not cosmetic: a window starts
    /// at a multiple of the window size, so a power-of-two stride guarantees the
    /// first position of every window is in the index. With an arbitrary stride
    /// most windows start a few dozen bytes before their first sampled offset,
    /// and an unchanged window costs those bytes as literals — 148 KB of them
    /// across a 199 MB file whose only difference was one byte.
    func stride(forSourceOfSize sourceSize: Int) -> Int {
        let wanted = max(blockSize, Int((Double(sourceSize) / Double(maximumIndexEntries)).rounded(.up)))
        var stride = blockSize
        while stride < wanted { stride <<= 1 }
        return stride
    }

    private static func hash(_ bytes: [UInt8], at offset: Int, count: Int) -> UInt64 {
        // FNV-1a: cheap, and spreading well is all this has to do.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for index in offset ..< (offset + count) {
            hash ^= UInt64(bytes[index])
            hash = hash &* 0x100_0000_01B3
        }
        return hash
    }

    // MARK: - One window

    private struct Sections {
        var data = [UInt8]()
        var instructions = [UInt8]()
        var addresses = [UInt8]()
    }

    private func encodeWindow(
        bytes: [UInt8],
        source: GoDReadable,
        index: [UInt64: Int],
        name: String
    ) throws -> Sections {
        var sections = Sections()
        var position = 0
        var literalStart = 0

        func flushLiterals(upTo end: Int) {
            guard end > literalStart else { return }
            let count = end - literalStart
            sections.instructions.append(UInt8(VCDIFFCodeTable.addWithExplicitSize))
            sections.instructions += VCDIFFInteger.encode(count)
            sections.data += bytes[literalStart ..< end]
            literalStart = end
        }

        while position < bytes.count {
            // A long repeat is a RUN, whatever the source says.
            var runLength = 1
            while position + runLength < bytes.count, bytes[position + runLength] == bytes[position] {
                runLength += 1
                if runLength >= maximumMatch { break }
            }
            if runLength >= minimumRun {
                flushLiterals(upTo: position)
                sections.instructions.append(UInt8(VCDIFFCodeTable.runWithExplicitSize))
                sections.instructions += VCDIFFInteger.encode(runLength)
                sections.data.append(bytes[position])
                position += runLength
                literalStart = position
                continue
            }

            if position + blockSize <= bytes.count {
                let key = VCDIFFEncoder.hash(bytes, at: position, count: blockSize)
                if let candidate = index[key] {
                    let matched = try match(
                        bytes: bytes, at: position, againstSource: source, at: candidate, name: name
                    )
                    if matched >= blockSize {
                        flushLiterals(upTo: position)
                        sections.instructions.append(UInt8(VCDIFFCodeTable.copySelfWithExplicitSize))
                        sections.instructions += VCDIFFInteger.encode(matched)
                        // SELF mode: the address is where it is, in a space whose
                        // first `sourceSize` bytes are the source segment.
                        sections.addresses += VCDIFFInteger.encode(candidate)
                        position += matched
                        literalStart = position
                        continue
                    }
                }
            }
            position += 1
        }
        flushLiterals(upTo: bytes.count)
        return sections
    }

    /// How far the window's bytes at `position` agree with the source at
    /// `candidate`, capped.
    private func match(
        bytes: [UInt8],
        at position: Int,
        againstSource source: GoDReadable,
        at candidate: Int,
        name: String
    ) throws -> Int {
        let available = min(bytes.count - position, source.length - candidate, maximumMatch)
        guard available >= blockSize else { return 0 }
        // Compared a chunk at a time: a match that runs to the end of an 8 MiB
        // window should cost one instruction, and reading the source for it
        // should still cost a chunk.
        let chunkSize = 1 << 20
        var matched = 0
        while matched < available {
            let take = min(chunkSize, available - matched)
            let sourceBytes = try PatchDiff.read(source, at: candidate + matched, count: take, name: name)
            var index = 0
            while index < take, sourceBytes[index] == bytes[position + matched + index] {
                index += 1
            }
            matched += index
            if index < take { break }
        }
        return matched
    }

    /// The window header around a set of sections.
    private func window(for sections: Sections, sourceSize: Int, targetLength: Int) -> [UInt8] {
        var delta = VCDIFFInteger.encode(targetLength)
        delta.append(0)   // no per-section compression
        delta += VCDIFFInteger.encode(sections.data.count)
        delta += VCDIFFInteger.encode(sections.instructions.count)
        delta += VCDIFFInteger.encode(sections.addresses.count)
        delta += sections.data
        delta += sections.instructions
        delta += sections.addresses

        var window = [UInt8]()
        if sourceSize > 0 {
            window.append(VCDIFFPatch.WindowIndicator.source)
            window += VCDIFFInteger.encode(sourceSize)
            window += VCDIFFInteger.encode(0)
        } else {
            window.append(0)
        }
        window += VCDIFFInteger.encode(delta.count)
        window += delta
        return window
    }
}
