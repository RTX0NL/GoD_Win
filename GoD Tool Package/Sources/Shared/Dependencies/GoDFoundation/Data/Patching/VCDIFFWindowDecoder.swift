//
//  VCDIFFWindowDecoder.swift
//
//  Runs one window's instruction stream.
//
//  A window's addresses live in a space that is its source segment followed by
//  the part of this window already written, so a COPY can take bytes from the
//  source, from what the window has produced, or across the boundary between
//  them — and one taking bytes it is still writing is how the format spells a
//  repeat. Source stretches are read in runs; everything inside the window is
//  copied a byte at a time, which is what makes an overlapping copy come out
//  right.
//

import Foundation

enum VCDIFFWindowDecoder {

    static func decode(
        window: VCDIFFPatch.Window,
        patch: GoDReadable,
        source: GoDReadable?,
        verifyChecksum: Bool = true
    ) throws -> [UInt8] {
        let name = VCDIFFPatchCodec.formatName
        var output = [UInt8]()
        output.reserveCapacity(window.targetLength)

        let data = PatchByteStream(source: patch, start: window.dataRange.lowerBound, end: window.dataRange.upperBound)
        let instructions = PatchByteStream(
            source: patch, start: window.instructionRange.lowerBound, end: window.instructionRange.upperBound
        )
        let addresses = PatchByteStream(
            source: patch, start: window.addressRange.lowerBound, end: window.addressRange.upperBound
        )
        var cache = VCDIFFAddressCache()

        while !instructions.isAtEnd, output.count < window.targetLength {
            guard let code = instructions.readByte() else { break }
            let pair = VCDIFFCodeTable.default[Int(code)]
            for instruction in [pair.0, pair.1] where instruction.type != .noop {
                let size: Int
                if instruction.size == 0 {
                    size = try integer(from: instructions, field: "instruction size", name: name)
                } else {
                    size = instruction.size
                }
                guard output.count + size <= window.targetLength else {
                    throw PatchError.malformedPatch(
                        format: name,
                        reason: "an instruction writes \(size) bytes past the window's \(window.targetLength)",
                        offset: instructions.offset
                    )
                }

                switch instruction.type {
                case .add:
                    output += try bytes(count: size, from: data, in: patch, name: name)
                case .run:
                    let byte = try bytes(count: 1, from: data, in: patch, name: name)[0]
                    output += [UInt8](repeating: byte, count: size)
                case .copy:
                    let here = window.sourceSegmentLength + output.count
                    let address = try cache.decodeAddress(
                        mode: instruction.mode,
                        here: here,
                        nextInteger: { try integer(from: addresses, field: "copy address", name: name) },
                        nextByte: {
                            guard let byte = addresses.readByte() else {
                                throw PatchError.malformedPatch(
                                    format: name, reason: "the address section ended early", offset: addresses.offset
                                )
                            }
                            return byte
                        }
                    )
                    try copy(
                        from: address, count: size, into: &output,
                        window: window, source: source, name: name
                    )
                case .noop:
                    break
                }
            }
        }

        guard output.count == window.targetLength else {
            throw PatchError.malformedPatch(
                format: name,
                reason: "the window's instructions produced \(output.count) bytes, not the \(window.targetLength) it declares",
                offset: window.instructionRange.lowerBound
            )
        }
        if verifyChecksum, let expected = window.adler32 {
            let computed = Adler32.compute(output)
            guard computed == expected else {
                throw PatchError.windowChecksumMismatch(
                    format: name, window: window.targetStart, expected: expected, computed: computed
                )
            }
        }
        return output
    }

    /// Copy `count` bytes starting at `address` in the window's address space.
    private static func copy(
        from address: Int,
        count: Int,
        into output: inout [UInt8],
        window: VCDIFFPatch.Window,
        source: GoDReadable?,
        name: String
    ) throws {
        var cursor = address
        var remaining = count
        guard cursor >= 0 else {
            throw PatchError.malformedPatch(format: name, reason: "a copy address is negative", offset: 0)
        }
        while remaining > 0 {
            if cursor < window.sourceSegmentLength {
                guard let source else {
                    throw PatchError.malformedPatch(
                        format: name, reason: "a window copies from a source segment, and no source was given", offset: 0
                    )
                }
                let take = min(remaining, window.sourceSegmentLength - cursor)
                let offset = window.sourceSegmentPosition + cursor
                guard offset >= 0, offset + take <= source.length else {
                    throw PatchError.malformedPatch(
                        format: name,
                        reason: "a window reads \(take) bytes at \(offset), outside the \(source.length)-byte source",
                        offset: 0
                    )
                }
                var done = 0
                while done < take {
                    let chunk = min(8 << 20, take - done)
                    output += try PatchDiff.read(source, at: offset + done, count: chunk, name: name)
                    done += chunk
                }
                cursor += take
                remaining -= take
            } else {
                // Inside this window's own output: one byte at a time, because
                // the read position can be inside what is being written.
                let index = cursor - window.sourceSegmentLength
                guard index < output.count else {
                    throw PatchError.malformedPatch(
                        format: name,
                        reason: "a copy reads from \(index) of this window's output, which is not written yet",
                        offset: 0
                    )
                }
                output.append(output[index])
                cursor += 1
                remaining -= 1
            }
        }
    }

    private static func bytes(
        count: Int,
        from stream: PatchByteStream,
        in patch: GoDReadable,
        name: String
    ) throws -> [UInt8] {
        guard count > 0 else { return [] }
        let offset = stream.offset
        let taken = try PatchDiff.read(patch, at: offset, count: count, name: name)
        stream.skip(count)
        guard stream.offset == offset + count else {
            throw PatchError.malformedPatch(format: name, reason: "the data section ended early", offset: offset)
        }
        return taken
    }

    private static func integer(from stream: PatchByteStream, field: String, name: String) throws -> Int {
        let start = stream.offset
        do {
            return try VCDIFFInteger.decode(nextByte: { stream.readByte() })
        } catch {
            throw PatchError.malformedPatch(format: name, reason: "\(field): \(error)", offset: start)
        }
    }
}
