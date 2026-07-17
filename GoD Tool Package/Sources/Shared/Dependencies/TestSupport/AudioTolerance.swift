//
//  AudioTolerance.swift
//
//  Tolerance comparators for lossy audio companions. DSP-ADPCM decode isn't
//  bit-exact and doesn't reach a byte-stable fixed point, so a golden WAV
//  can't be compared byte-for-byte on the decode side — compare the PCM
//  within a small RMS error instead. (Encode stays exact: the WAV carries
//  lossless PCM and the ADPCM encoder is deterministic.)
//

import Foundation

/// Comparator for 16-bit little-endian PCM WAV artifacts: same byte length,
/// same sample count, and per-sample RMS difference within `maxRMS`
/// (Int16 full-scale is 32768). Assumes a standard 44-byte RIFF header.
public func wavPCMTolerance(maxRMS: Double) -> ArtifactComparator {
    let headerSize = 44
    return { actual, expected in
        guard actual.count == expected.count, actual.count > headerSize else { return false }
        func samples(_ bytes: [UInt8]) -> [Int16] {
            var out: [Int16] = []
            out.reserveCapacity((bytes.count - headerSize) / 2)
            var i = headerSize
            while i + 1 < bytes.count {
                out.append(Int16(bitPattern: UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8)))
                i += 2
            }
            return out
        }
        let a = samples(actual)
        let e = samples(expected)
        guard a.count == e.count else { return false }
        guard !a.isEmpty else { return true }
        var sumSq = 0.0
        for i in 0..<a.count {
            let d = Double(a[i]) - Double(e[i])
            sumSq += d * d
        }
        let rms = (sumSq / Double(a.count)).squareRoot()
        if ProcessInfo.processInfo.environment["PRINT_WAV_RMS"] != nil {
            FileHandle.standardError.write(Data("WAV RMS diff = \(rms)\n".utf8))
        }
        return rms <= maxRMS
    }
}
