//
//  NintendoCompressionFixtures.swift
//
//  A known mixed-compressibility input and its Yaz0 and Yay0 streams,
//  pinning what our encoders emit. Both formats compress the same input so
//  the two streams can be compared against each other as well as against
//  themselves.
//
//  These freeze *our* encoder's output, so they catch unintended drift —
//  they are not evidence the streams match Nintendo's. The hand-authored
//  streams in the Yaz0/Yay0 test files are the independent ground truth for
//  the on-wire format.
//

import Foundation
import GoDFoundation

public enum NintendoCompressionFixtures {

    /// Mixed-compressibility input, shaped to exercise every branch of the
    /// encoders: long repeats (2-byte matches), a zero run (the 3-byte
    /// long-match form), near-misses that force literals, and a tail that
    /// repeats from far enough back to test the window.
    public static func sampleInput() -> [UInt8] {
        var bytes: [UInt8] = []
        let phrase = Array("THE LEGEND OF ZELDA ".utf8)
        for _ in 0..<10 { bytes += phrase }
        bytes += [UInt8](repeating: 0, count: 512)
        bytes += deterministicBytes(256, seed: 0x5941_5A30)   // "YAZ0"
        bytes += phrase                                       // long-range repeat
        bytes += [UInt8](repeating: 0xFF, count: 24)
        return bytes
    }

    public static func files() -> [FixtureFile] {
        let input = sampleInput()
        let source = GoDData(byteStream: input, byteOrder: .big)
        return [
            FixtureFile(
                relativePath: "\(FixtureDir.foundation)/nintendo_lz77_sample.bin",
                bytes: input
            ),
            FixtureFile(
                relativePath: "\(FixtureDir.foundation)/nintendo_lz77_sample.yaz0",
                bytes: Yaz0Compressor().compress(source).rawBytes
            ),
            FixtureFile(
                relativePath: "\(FixtureDir.foundation)/nintendo_lz77_sample.yay0",
                bytes: Yay0Compressor().compress(source).rawBytes
            ),
        ]
    }
}
