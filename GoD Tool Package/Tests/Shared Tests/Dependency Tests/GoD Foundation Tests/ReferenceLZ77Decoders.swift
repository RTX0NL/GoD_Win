//
//  ReferenceLZ77Decoders.swift
//
//  Deliberately independent decoders for Yaz0 and Yay0, transcribed from
//  the format documentation rather than derived from the production code.
//
//  A round-trip test only proves the encoder and decoder agree with each
//  other — an encoder that writes a subtly wrong distance and a decoder
//  that reads it back the same wrong way would pass. Checking our encoder's
//  output against these instead breaks that circularity, the same way
//  `WiiDiscFixtures` cross-checks the Wii crypto by building discs without
//  calling it.
//
//  Written for obviousness, not speed or robustness: they expand the flags
//  into an explicit queue instead of shifting a register, and they trap
//  rather than throw on malformed input, so only well-formed streams should
//  be handed to them.
//

import Foundation

enum ReferenceYaz0 {

    static func decode(_ stream: [UInt8]) -> [UInt8] {
        precondition(Array(stream[0 ..< 4]) == Array("Yaz0".utf8), "not a Yaz0 stream")
        let size = readBigEndianUInt32(stream, at: 4)

        var output: [UInt8] = []
        var cursor = 0x10
        var pendingFlags: [Bool] = []

        while output.count < size {
            if pendingFlags.isEmpty {
                pendingFlags = expandFlagByte(stream[cursor])
                cursor += 1
            }
            if pendingFlags.removeFirst() {
                output.append(stream[cursor])
                cursor += 1
            } else {
                let high = Int(stream[cursor])
                let low = Int(stream[cursor + 1])
                cursor += 2
                var length = high >> 4
                if length == 0 {
                    length = Int(stream[cursor]) + 18
                    cursor += 1
                } else {
                    length += 2
                }
                copyBackReference(
                    distance: ((high & 0x0F) << 8 | low) + 1,
                    length: length,
                    into: &output
                )
            }
        }

        return Array(output.prefix(size))
    }
}

enum ReferenceYay0 {

    static func decode(_ stream: [UInt8]) -> [UInt8] {
        precondition(Array(stream[0 ..< 4]) == Array("Yay0".utf8), "not a Yay0 stream")
        let size = readBigEndianUInt32(stream, at: 4)

        var output: [UInt8] = []
        var maskCursor = 0x10
        var linkCursor = readBigEndianUInt32(stream, at: 8)
        var chunkCursor = readBigEndianUInt32(stream, at: 12)
        var pendingFlags: [Bool] = []

        while output.count < size {
            if pendingFlags.isEmpty {
                // A mask word is four flag bytes, most significant first.
                for offset in 0 ..< 4 {
                    pendingFlags += expandFlagByte(stream[maskCursor + offset])
                }
                maskCursor += 4
            }
            if pendingFlags.removeFirst() {
                output.append(stream[chunkCursor])
                chunkCursor += 1
            } else {
                let high = Int(stream[linkCursor])
                let low = Int(stream[linkCursor + 1])
                linkCursor += 2
                var length = high >> 4
                if length == 0 {
                    length = Int(stream[chunkCursor]) + 18
                    chunkCursor += 1
                } else {
                    length += 2
                }
                copyBackReference(
                    distance: ((high & 0x0F) << 8 | low) + 1,
                    length: length,
                    into: &output
                )
            }
        }

        return Array(output.prefix(size))
    }
}

// MARK: - Shared helpers

/// The eight flags in a byte, most significant bit first.
private func expandFlagByte(_ byte: UInt8) -> [Bool] {
    (0 ..< 8).map { bit in (byte >> (7 - bit)) & 1 == 1 }
}

private func readBigEndianUInt32(_ bytes: [UInt8], at offset: Int) -> Int {
    Int(bytes[offset]) << 24
        | Int(bytes[offset + 1]) << 16
        | Int(bytes[offset + 2]) << 8
        | Int(bytes[offset + 3])
}

/// One byte at a time, so a reference into the run being written works.
private func copyBackReference(distance: Int, length: Int, into output: inout [UInt8]) {
    let start = output.count - distance
    precondition(start >= 0, "back-reference points before the start of the output")
    for offset in 0 ..< length {
        let byte = output[start + offset]
        output.append(byte)
    }
}
