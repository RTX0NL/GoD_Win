//
//  VCDIFFPatchedView.swift
//
//  The result of applying a VCDIFF patch, decoded a window at a time.
//
//  Windows are independent — each one's addresses reach into its own source
//  segment and its own output, and the caches reset at the boundary — so a read
//  only has to decode the windows it lands in. The last one decoded is kept,
//  which makes a sequential pass over the output decode each window once.
//
//  Memory is therefore one window, not one file: xdelta3 writes 8 MiB windows.
//  A patch that declares a single enormous window is a single enormous decode,
//  and nothing can be done about that from this side.
//

import Foundation

public final class VCDIFFPatchedView: GoDReadable {

    private let patch: GoDReadable
    private let source: GoDReadable?
    private let windows: [VCDIFFPatch.Window]

    private var cachedIndex: Int?
    private var cachedBytes: [UInt8] = []

    public let length: Int
    public var byteOrder: ByteOrder { source?.byteOrder ?? patch.byteOrder }

    public init(patch: GoDReadable, source: GoDReadable?, vcdiff: VCDIFFPatch) {
        self.patch = patch
        self.source = source
        self.windows = vcdiff.windows
        self.length = vcdiff.targetSize
    }

    public func read(atAddress address: UInt, length readLength: UInt) -> GoDData? {
        let start = Int(address)
        let count = Int(readLength)
        guard start >= 0, count >= 0, start + count <= length else { return nil }
        guard count > 0 else { return GoDData(byteOrder: byteOrder) }

        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        var cursor = start
        while cursor < start + count {
            guard let index = windowIndex(containing: cursor) else { return nil }
            guard let decoded = try? window(at: index) else { return nil }
            let window = windows[index]
            let offset = cursor - window.targetStart
            let take = min(decoded.count - offset, start + count - cursor)
            guard take > 0 else { return nil }
            bytes += decoded[offset ..< offset + take]
            cursor += take
        }
        return GoDData(byteStream: bytes, byteOrder: byteOrder)
    }

    /// Decode a window, or hand back the one already decoded.
    private func window(at index: Int) throws -> [UInt8] {
        if cachedIndex == index { return cachedBytes }
        let decoded = try VCDIFFWindowDecoder.decode(
            window: windows[index], patch: patch, source: source
        )
        cachedIndex = index
        cachedBytes = decoded
        return decoded
    }

    private func windowIndex(containing offset: Int) -> Int? {
        var low = 0
        var high = windows.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let window = windows[middle]
            if offset < window.targetStart {
                high = middle - 1
            } else if offset >= window.targetStart + window.targetLength {
                low = middle + 1
            } else {
                return middle
            }
        }
        return nil
    }
}
