//
//  BPSPatchedView.swift
//
//  The result of applying a BPS patch.
//
//  Unlike UPS and IPS, this one builds the whole target before it can answer a
//  read, and that is the format rather than a shortcut: a `TargetCopy` may take
//  its bytes from *any* earlier part of the output, including from bytes the
//  same action is still writing. Answering "what is byte N" can therefore
//  depend on an arbitrarily long chain of earlier output, so there is no
//  window-sized way to do it. Applying a BPS patch costs the target's size in
//  memory; every other tool that reads the format does the same.
//
//  The build happens once, on the first read, and is kept — the operation
//  layer writes the output and then reads it back to check its checksum.
//

import Foundation

public final class BPSPatchedView: GoDReadable {

    private let source: GoDReadable
    private let patch: GoDReadable
    private let bps: BPSPatch
    private var built: GoDData?

    public let length: Int

    public var byteOrder: ByteOrder { source.byteOrder }

    /// Only once the target exists. Before that there is nothing to hand over,
    /// and saying so keeps `materialized()` honest.
    public var allData: GoDData? { built }

    public init(source: GoDReadable, patch: GoDReadable, bps: BPSPatch) {
        self.source = source
        self.patch = patch
        self.bps = bps
        self.length = bps.targetSize
    }

    public func read(atAddress address: UInt, length readLength: UInt) -> GoDData? {
        guard let output = try? build() else { return nil }
        return output.read(atAddress: address, length: readLength)
    }

    @discardableResult
    public func build() throws -> GoDData {
        if let built { return built }
        let name = BPSPatchCodec.formatName
        var output = [UInt8](repeating: 0, count: bps.targetSize)
        var offset = 0

        for action in bps.actions {
            switch action {
            case let .sourceRead(length):
                try copy(from: source, at: offset, into: &output, at: offset, count: length, name: name)
            case let .targetRead(patchOffset, length):
                try copy(from: patch, at: patchOffset, into: &output, at: offset, count: length, name: name)
            case let .sourceCopy(sourceOffset, length):
                try copy(from: source, at: sourceOffset, into: &output, at: offset, count: length, name: name)
            case let .targetCopy(targetOffset, length):
                // Byte at a time, deliberately: the read position can be
                // inside the range being written, which is how the format
                // spells a repeat, and a block move would copy bytes that do
                // not exist yet.
                var from = targetOffset
                for step in 0 ..< length {
                    output[offset + step] = output[from]
                    from += 1
                }
            }
            offset += action.length
        }

        let data = GoDData(byteStream: output, byteOrder: byteOrder)
        built = data
        return data
    }

    /// Copy `count` bytes in windows, so one enormous action doesn't allocate
    /// its whole length on top of the output.
    private func copy(
        from readable: GoDReadable,
        at readOffset: Int,
        into output: inout [UInt8],
        at writeOffset: Int,
        count: Int,
        name: String
    ) throws {
        let window = 8 << 20
        var done = 0
        while done < count {
            let take = min(window, count - done)
            let bytes = try PatchDiff.read(readable, at: readOffset + done, count: take, name: name)
            output.replaceSubrange((writeOffset + done) ..< (writeOffset + done + take), with: bytes)
            done += take
        }
    }
}
