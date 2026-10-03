//
//  UPSPatchedView.swift
//
//  The result of applying a UPS patch, as a readable rather than a buffer.
//
//  Reading a window of it reads the same window of the input, XORs in
//  whichever hunks overlap it — their bytes fetched from the patch file as
//  needed — and hands the result back. So patching a 1.4 GB disc image costs
//  the hunk index plus a window, and `FileHandleAccess.write` streams it out.
//
//  The direction is a property of this view, not of the patch: UPS stores the
//  XOR of the two files, so the same hunks that turn the source into the
//  target turn the target back into the source. All that changes is which
//  file is the input and how long the output is.
//

import Foundation

public final class UPSPatchedView: GoDReadable {

    private let input: GoDReadable
    private let patch: GoDReadable
    /// Ordered, disjoint, and clipped to the output — see `init`.
    private let hunks: [UPSPatch.Hunk]
    private let inputSize: Int

    public let length: Int
    public let direction: PatchDirection

    public var byteOrder: ByteOrder { input.byteOrder }

    /// - Parameter direction: which side of the patch `input` is.
    public init(input: GoDReadable, patch: GoDReadable, ups: UPSPatch, direction: PatchDirection) {
        self.input = input
        self.patch = patch
        self.direction = direction
        self.inputSize = ups.inputSize(applying: direction)
        let outputSize = ups.outputSize(applying: direction)
        self.length = outputSize
        // A patch covers max(sourceSize, targetSize) positions, so applying
        // it in the direction with the shorter output leaves hunk data with
        // nowhere to go. Those bytes belong to the other direction's tail and
        // are dropped here rather than treated as an error.
        self.hunks = ups.hunks.compactMap { hunk in
            guard hunk.outputOffset < outputSize else { return nil }
            let clipped = min(hunk.length, outputSize - hunk.outputOffset)
            guard clipped > 0 else { return nil }
            return clipped == hunk.length
                ? hunk
                : UPSPatch.Hunk(outputOffset: hunk.outputOffset, patchOffset: hunk.patchOffset, length: clipped)
        }
    }

    public func read(atAddress address: UInt, length readLength: UInt) -> GoDData? {
        let start = Int(address)
        let count = Int(readLength)
        guard start >= 0, count >= 0, start + count <= length else { return nil }
        guard count > 0 else { return GoDData(byteOrder: byteOrder) }

        // The input, zero-extended: the output can run past the end of the
        // file being patched, and those positions are supplied by hunks
        // XORing against zero.
        var bytes: [UInt8]
        let fromInput = max(0, min(count, inputSize - start))
        if fromInput == count {
            guard let window = input.read(atAddress: start, length: count) else { return nil }
            bytes = window.rawBytes
        } else if fromInput > 0 {
            guard let window = input.read(atAddress: start, length: fromInput) else { return nil }
            bytes = window.rawBytes + [UInt8](repeating: 0, count: count - fromInput)
        } else {
            bytes = [UInt8](repeating: 0, count: count)
        }
        guard bytes.count == count else { return nil }

        let end = start + count
        var index = firstHunkIndex(reaching: start)
        while index < hunks.count, hunks[index].outputOffset < end {
            let hunk = hunks[index]
            let overlapStart = max(hunk.outputOffset, start)
            let overlapEnd = min(hunk.outputOffset + hunk.length, end)
            if overlapStart < overlapEnd {
                let patchOffset = hunk.patchOffset + (overlapStart - hunk.outputOffset)
                guard let payload = patch.read(atAddress: patchOffset, length: overlapEnd - overlapStart) else {
                    return nil
                }
                let xor = payload.rawBytes
                guard xor.count == overlapEnd - overlapStart else { return nil }
                var cursor = overlapStart - start
                for byte in xor {
                    bytes[cursor] ^= byte
                    cursor += 1
                }
            }
            index += 1
        }
        return GoDData(byteStream: bytes, byteOrder: byteOrder)
    }

    /// The first hunk that could reach `offset`. Hunks are ordered and
    /// disjoint, so this is a binary search.
    private func firstHunkIndex(reaching offset: Int) -> Int {
        var low = 0
        var high = hunks.count
        while low < high {
            let middle = (low + high) / 2
            if hunks[middle].outputOffset + hunks[middle].length <= offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
