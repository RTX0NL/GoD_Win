//
//  ReferenceBPSPatcher.swift
//
//  An independently transcribed BPS applier, written from byuu's specification
//  rather than from the production code — the cross-check that keeps a wrong
//  writer and a matching wrong reader from passing together.
//
//  Holds whole files and traps on malformed input: well-formed patches only.
//

import Foundation

enum ReferenceBPS {

    struct Header {
        let sourceSize: Int
        let targetSize: Int
        let metadata: [UInt8]
        let sourceCRC: UInt32
        let targetCRC: UInt32
        let patchCRC: UInt32
    }

    static func header(_ patch: [UInt8]) -> Header {
        precondition(Array(patch[0 ..< 4]) == Array("BPS1".utf8), "not a BPS patch")
        var i = 4
        let sourceSize = decode(patch, &i)
        let targetSize = decode(patch, &i)
        let metadataSize = decode(patch, &i)
        let metadata = Array(patch[i ..< i + metadataSize])
        let footer = patch.count - 12
        return Header(
            sourceSize: sourceSize,
            targetSize: targetSize,
            metadata: metadata,
            sourceCRC: word(patch, footer),
            targetCRC: word(patch, footer + 4),
            patchCRC: word(patch, footer + 8)
        )
    }

    /// byuu's decode loop, verbatim in structure.
    static func apply(_ patch: [UInt8], to source: [UInt8]) -> [UInt8] {
        precondition(Array(patch[0 ..< 4]) == Array("BPS1".utf8), "not a BPS patch")
        var i = 4
        _ = decode(patch, &i)                       // source size
        let targetSize = decode(patch, &i)
        let metadataSize = decode(patch, &i)
        i += metadataSize

        var target = [UInt8](repeating: 0, count: targetSize)
        var outputOffset = 0
        var sourceRelativeOffset = 0
        var targetRelativeOffset = 0
        let bodyEnd = patch.count - 12

        while i < bodyEnd {
            let data = decode(patch, &i)
            let command = data & 3
            var length = (data >> 2) + 1
            switch command {
            case 0:     // SourceRead
                while length > 0 {
                    target[outputOffset] = source[outputOffset]
                    outputOffset += 1
                    length -= 1
                }
            case 1:     // TargetRead
                while length > 0 {
                    target[outputOffset] = patch[i]
                    outputOffset += 1
                    i += 1
                    length -= 1
                }
            case 2:     // SourceCopy
                sourceRelativeOffset += signed(patch, &i)
                while length > 0 {
                    target[outputOffset] = source[sourceRelativeOffset]
                    outputOffset += 1
                    sourceRelativeOffset += 1
                    length -= 1
                }
            default:    // TargetCopy
                targetRelativeOffset += signed(patch, &i)
                while length > 0 {
                    target[outputOffset] = target[targetRelativeOffset]
                    outputOffset += 1
                    targetRelativeOffset += 1
                    length -= 1
                }
            }
        }
        precondition(outputOffset == targetSize, "the actions did not fill the target")
        return target
    }

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

    private static func signed(_ bytes: [UInt8], _ cursor: inout Int) -> Int {
        let data = decode(bytes, &cursor)
        return (data & 1) != 0 ? -(data >> 1) : (data >> 1)
    }

    private static func word(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}
