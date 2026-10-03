//
//  ReferenceIPSPatcher.swift
//
//  An independently transcribed IPS applier, written from the format
//  description rather than from the production code — the same cross-check
//  `ReferenceUPSPatcher` provides, and the only way a patch our own encoder
//  wrote can be checked by something other than our own decoder.
//
//  Holds whole files and traps on malformed input: well-formed patches only.
//

import Foundation

enum ReferenceIPS {

    /// Records are `offset(3) size(2) data`, a size of zero meaning
    /// `length(2) byte(1)` repeated, terminated by "EOF" where a record would
    /// start, optionally followed by a three-byte length to cut the file to.
    static func apply(_ patch: [UInt8], to input: [UInt8]) -> [UInt8] {
        precondition(Array(patch[0 ..< 5]) == Array("PATCH".utf8), "not an IPS patch")
        var output = input
        var i = 5
        while true {
            precondition(i + 3 <= patch.count, "records not terminated")
            if Array(patch[i ..< i + 3]) == Array("EOF".utf8) {
                i += 3
                break
            }
            let offset = int(patch, i, 3); i += 3
            let size = int(patch, i, 2); i += 2
            var bytes: [UInt8]
            if size == 0 {
                let runLength = int(patch, i, 2); i += 2
                bytes = [UInt8](repeating: patch[i], count: runLength); i += 1
            } else {
                bytes = Array(patch[i ..< i + size]); i += size
            }
            if output.count < offset + bytes.count {
                output += [UInt8](repeating: 0, count: offset + bytes.count - output.count)
            }
            for (step, byte) in bytes.enumerated() { output[offset + step] = byte }
        }
        if patch.count - i == 3 {
            let truncation = int(patch, i, 3)
            if output.count > truncation { output.removeLast(output.count - truncation) }
        }
        return output
    }

    private static func int(_ bytes: [UInt8], _ offset: Int, _ width: Int) -> Int {
        (0 ..< width).reduce(0) { ($0 << 8) | Int(bytes[offset + $1]) }
    }
}
