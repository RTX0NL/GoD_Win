//
//  ReferenceUPSPatcher.swift
//
//  A deliberately independent UPS applier and patch reader, transcribed from
//  the format documentation rather than derived from the production code.
//
//  A round trip only proves the writer and the reader agree with each other:
//  a creator that encodes its hunk offsets one byte early and an applier that
//  reads them back the same way would pass every test. Checking the created
//  patch through this instead breaks that circularity — the same reasoning as
//  `ReferenceLZ77Decoders` and `WiiDiscFixtures`.
//
//  Written for obviousness, not speed: it holds whole files, decodes its
//  variable-width integers a byte at a time from a plain array, and traps
//  rather than throws, so only well-formed patches should be handed to it.
//

import Foundation

enum ReferenceUPS {

    struct Patch {
        let sourceSize: Int
        let targetSize: Int
        /// `(outputOffset, xor bytes)`, in the order they appear.
        let hunks: [(offset: Int, bytes: [UInt8])]
        let sourceCRC: UInt32
        let targetCRC: UInt32
        let patchCRC: UInt32
    }

    /// Parse a patch, from the spec:
    ///
    ///   "UPS1", VLV source size, VLV target size, then hunks until 12 bytes
    ///   from the end: a VLV relative offset, XOR bytes, a 0x00 terminator
    ///   that also advances the position. Footer: three little-endian CRC-32s.
    static func parse(_ patch: [UInt8]) -> Patch {
        precondition(Array(patch[0 ..< 4]) == Array("UPS1".utf8), "not a UPS patch")
        var cursor = 4
        let sourceSize = decode(patch, &cursor)
        let targetSize = decode(patch, &cursor)

        var hunks = [(offset: Int, bytes: [UInt8])]()
        var position = 0
        let bodyEnd = patch.count - 12
        while cursor < bodyEnd {
            position += decode(patch, &cursor)
            var bytes = [UInt8]()
            while patch[cursor] != 0 {
                bytes.append(patch[cursor])
                cursor += 1
            }
            cursor += 1
            hunks.append((position, bytes))
            position += bytes.count + 1
        }

        return Patch(
            sourceSize: sourceSize,
            targetSize: targetSize,
            hunks: hunks,
            sourceCRC: word(patch, bodyEnd),
            targetCRC: word(patch, bodyEnd + 4),
            patchCRC: word(patch, bodyEnd + 8)
        )
    }

    /// Apply `patch` to `input`, in the direction `input` fits.
    ///
    /// The XOR data is symmetric, so the only thing the direction changes is
    /// how long the output is.
    static func apply(_ patch: [UInt8], to input: [UInt8]) -> [UInt8] {
        let parsed = parse(patch)
        if input.count == parsed.sourceSize, crc32(input) == parsed.sourceCRC {
            return apply(patch, to: input, producing: parsed.targetSize)
        }
        if input.count == parsed.targetSize, crc32(input) == parsed.targetCRC {
            return apply(patch, to: input, producing: parsed.sourceSize)
        }
        preconditionFailure("the input is neither side of this patch")
    }

    /// Apply forward without asking which side the input is.
    ///
    /// For comparing two appliers over an input that is neither file — which is
    /// how a real patch can be exercised without the ROM it was cut against.
    static func applyForward(_ patch: [UInt8], to input: [UInt8]) -> [UInt8] {
        apply(patch, to: input, producing: parse(patch).targetSize)
    }

    private static func apply(_ patch: [UInt8], to input: [UInt8], producing outputSize: Int) -> [UInt8] {
        let parsed = parse(patch)
        var output = [UInt8](repeating: 0, count: outputSize)
        for index in 0 ..< min(outputSize, input.count) {
            output[index] = input[index]
        }
        for hunk in parsed.hunks {
            for (step, byte) in hunk.bytes.enumerated() {
                let position = hunk.offset + step
                guard position < outputSize else { continue }
                output[position] ^= byte
            }
        }
        return output
    }

    /// byuu's decoder: each continuation byte contributes seven bits *and*
    /// adds the running multiplier back on, which is what undoes the
    /// encoder's decrement.
    private static func decode(_ bytes: [UInt8], _ cursor: inout Int) -> Int {
        var value = 0
        var shift = 1
        while true {
            let byte = bytes[cursor]
            cursor += 1
            value += Int(byte & 0x7F) * shift
            if byte & 0x80 != 0 { return value }
            shift <<= 7
            value += shift
        }
    }

    private static func word(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    /// CRC-32 written out longhand, so the fixtures are not checked against
    /// the same table the production code uses.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
