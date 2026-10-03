//
//  ReferenceVCDIFFDecoder.swift
//
//  An independently written VCDIFF decoder, for cross-checking the encoder.
//
//  The code table here is *derived arithmetically from the ranges in RFC 3284*
//  rather than built by appending entries in order, which is how the production
//  table is made. Two different derivations of the same table is the point: a
//  mistake in one shows up as a disagreement rather than as a patch that
//  round-trips through its own error.
//
//  Holds whole files and traps on malformed input: well-formed patches only.
//

import Foundation

enum ReferenceVCDIFF {

    enum Instruction: Equatable {
        case noop
        case add(size: Int)
        case run(size: Int)
        case copy(size: Int, mode: Int)
    }

    /// The default code table, worked out per code from the spec's ranges.
    static func instructions(for code: Int) -> (Instruction, Instruction) {
        switch code {
        case 0:
            return (.run(size: 0), .noop)
        case 1 ... 18:
            return (.add(size: code == 1 ? 0 : code - 1), .noop)
        case 19 ... 162:
            let index = code - 19
            let slot = index % 16
            return (.copy(size: slot == 0 ? 0 : slot + 3, mode: index / 16), .noop)
        case 163 ... 234:
            let index = code - 163
            let within = index % 12
            return (
                .add(size: within / 3 + 1),
                .copy(size: within % 3 + 4, mode: index / 12)
            )
        case 235 ... 246:
            let index = code - 235
            return (.add(size: index % 4 + 1), .copy(size: 4, mode: 6 + index / 4))
        default:
            return (.copy(size: 4, mode: code - 247), .add(size: 1))
        }
    }

    static func apply(_ patch: [UInt8], to source: [UInt8]) -> [UInt8] {
        precondition(Array(patch[0 ..< 3]) == [0xD6, 0xC3, 0xC4], "not a VCDIFF patch")
        precondition(patch[3] == 0, "unsupported version")
        var cursor = 4
        let headerIndicator = patch[cursor]; cursor += 1
        precondition(headerIndicator & 0x03 == 0, "secondary compression or a custom table")
        if headerIndicator & 0x04 != 0 {
            let size = integer(patch, &cursor)
            cursor += size
        }

        var output = [UInt8]()
        while cursor < patch.count {
            let windowIndicator = patch[cursor]; cursor += 1
            var segmentLength = 0
            var segmentPosition = 0
            if windowIndicator & 0x03 != 0 {
                segmentLength = integer(patch, &cursor)
                segmentPosition = integer(patch, &cursor)
            }
            _ = integer(patch, &cursor)                       // delta encoding length
            let targetLength = integer(patch, &cursor)
            let deltaIndicator = patch[cursor]; cursor += 1
            precondition(deltaIndicator == 0, "per-section compression")
            let dataLength = integer(patch, &cursor)
            let instructionLength = integer(patch, &cursor)
            let addressLength = integer(patch, &cursor)
            if windowIndicator & 0x04 != 0 { cursor += 4 }    // xdelta3's checksum

            var dataCursor = cursor
            var instructionCursor = cursor + dataLength
            var addressCursor = cursor + dataLength + instructionLength
            let windowEnd = cursor + dataLength + instructionLength + addressLength

            var window = [UInt8]()
            var near = [Int](repeating: 0, count: 4)
            var same = [Int](repeating: 0, count: 3 * 256)
            var nextSlot = 0

            func remember(_ address: Int) {
                near[nextSlot] = address
                nextSlot = (nextSlot + 1) % near.count
                same[address % same.count] = address
            }

            while window.count < targetLength {
                let code = Int(patch[instructionCursor]); instructionCursor += 1
                let pair = instructions(for: code)
                for instruction in [pair.0, pair.1] {
                    switch instruction {
                    case .noop:
                        continue
                    case .add(let declared):
                        let size = declared == 0 ? integer(patch, &instructionCursor) : declared
                        window += patch[dataCursor ..< dataCursor + size]
                        dataCursor += size
                    case .run(let declared):
                        let size = declared == 0 ? integer(patch, &instructionCursor) : declared
                        let byte = patch[dataCursor]; dataCursor += 1
                        window += [UInt8](repeating: byte, count: size)
                    case .copy(let declared, let mode):
                        let size = declared == 0 ? integer(patch, &instructionCursor) : declared
                        let here = segmentLength + window.count
                        let address: Int
                        switch mode {
                        case 0:
                            address = integer(patch, &addressCursor)
                        case 1:
                            address = here - integer(patch, &addressCursor)
                        case 2, 3, 4, 5:
                            address = near[mode - 2] + integer(patch, &addressCursor)
                        default:
                            let row = mode - 6
                            let slot = Int(patch[addressCursor]); addressCursor += 1
                            address = same[row * 256 + slot]
                        }
                        remember(address)
                        var position = address
                        for _ in 0 ..< size {
                            if position < segmentLength {
                                window.append(source[segmentPosition + position])
                            } else {
                                window.append(window[position - segmentLength])
                            }
                            position += 1
                        }
                    }
                }
            }
            precondition(window.count == targetLength, "a window overshot its length")
            output += window
            cursor = windowEnd
        }
        return output
    }

    /// Base 128, most significant digit first, continuation in the high bit.
    private static func integer(_ bytes: [UInt8], _ cursor: inout Int) -> Int {
        var value = 0
        while true {
            let byte = bytes[cursor]
            cursor += 1
            value = value * 128 + Int(byte & 0x7F)
            if byte & 0x80 == 0 { return value }
        }
    }
}
