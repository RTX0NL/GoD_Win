//
//  IPSPatchedView.swift
//
//  The result of applying an IPS patch, as a readable.
//
//  Reading a window reads the same window of the input and writes each
//  overlapping record over it, in file order — later records win, which is the
//  format's own rule and the reason they are applied rather than merged.
//
//  The output can be longer than the input: records may write past its end,
//  and the bytes between them are zero. It can also be shorter, when the patch
//  carries the trailing truncation field.
//

import Foundation

public final class IPSPatchedView: GoDReadable {

    private let input: GoDReadable
    private let patch: GoDReadable
    private let records: [IPSPatch.Record]
    private let inputSize: Int

    public let length: Int

    public var byteOrder: ByteOrder { input.byteOrder }

    public init(input: GoDReadable, patch: GoDReadable, ips: IPSPatch) {
        self.input = input
        self.patch = patch
        self.inputSize = input.length
        let grown = max(input.length, ips.coverage)
        let length = ips.truncation ?? grown
        self.length = length
        // A truncated output can cut a record in half, so anything starting
        // past the end goes, and the rest is clipped on read.
        self.records = ips.records.filter { $0.offset < length }
    }

    public func read(atAddress address: UInt, length readLength: UInt) -> GoDData? {
        let start = Int(address)
        let count = Int(readLength)
        guard start >= 0, count >= 0, start + count <= length else { return nil }
        guard count > 0 else { return GoDData(byteOrder: byteOrder) }
        let end = start + count

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

        for record in records {
            let overlapStart = max(record.offset, start)
            let overlapEnd = min(record.offset + record.length, end)
            guard overlapStart < overlapEnd else { continue }
            let skip = overlapStart - record.offset
            let span = overlapEnd - overlapStart
            switch record.payload {
            case .run(let byte):
                for index in 0 ..< span { bytes[overlapStart - start + index] = byte }
            case .literal(let patchOffset):
                guard let payload = patch.read(atAddress: patchOffset + skip, length: span),
                      payload.length == span else {
                    return nil
                }
                var cursor = overlapStart - start
                for byte in payload.rawBytes {
                    bytes[cursor] = byte
                    cursor += 1
                }
            }
        }
        return GoDData(byteStream: bytes, byteOrder: byteOrder)
    }
}
