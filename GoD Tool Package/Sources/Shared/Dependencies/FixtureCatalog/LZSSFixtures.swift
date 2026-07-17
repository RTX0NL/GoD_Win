//
//  LZSSFixtures.swift
//
//  A known mixed-compressibility input and its compressed stream, pinning
//  the on-wire LZSS format (the codec inside FSYS entries).
//

import Foundation
import GoDFoundation

public enum LZSSFixtures {
    /// Mixed-compressibility input: a repeating ASCII phrase (long matches),
    /// a zero run (max-length matches), and deterministic noise (literals).
    public static func sampleInput() -> [UInt8] {
        var bytes: [UInt8] = []
        let phrase = Array("GALE OF DARKNESS ".utf8)
        for _ in 0..<12 { bytes += phrase }
        bytes += [UInt8](repeating: 0, count: 256)
        bytes += deterministicBytes(192, seed: 0x4C5A_5353)   // "LZSS"
        return bytes
    }

    public static func files() -> [FixtureFile] {
        let input = sampleInput()
        let compressed = LZSSCompressor()
            .compress(GoDData(byteStream: input, byteOrder: .big))
        return [
            FixtureFile(relativePath: "\(FixtureDir.foundation)/lzss_sample.bin", bytes: input),
            FixtureFile(relativePath: "\(FixtureDir.foundation)/lzss_sample.lzss", bytes: compressed.rawBytes),
        ]
    }
}
