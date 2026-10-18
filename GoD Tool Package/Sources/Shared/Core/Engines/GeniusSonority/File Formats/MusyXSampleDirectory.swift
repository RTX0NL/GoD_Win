//
//  MusyXSampleDirectory.swift
//
//  MusyX sample directory (`.sdir`): where each sample of a bank lives in
//  its `.samp` and how to decode it. Colosseum keeps all its music and
//  sound effects in MusyX banks; XD keeps a few. The `.samp` is raw
//  DSP-ADPCM with no header, so the directory is the only way in.
//
//  Layout (big-endian), from amuse's AudioGroupSampleDirectory and checked
//  on the US Colosseum disc (docs in Shadow Saga's spec/audio_cries.md):
//
//    entry, 0x20 bytes, until a sample id of 0xFFFF:
//      0x00 u16 sample id        0x02 u16 pad
//      0x04 u32 offset in .samp  0x08 u32 (0)
//      0x0C u8  base pitch (MIDI key the sample plays at its own rate)
//      0x0D u8  pad              0x0E u16 sample rate
//      0x10 u32 sample count (low 24 bits), format (top 8; 0 = DSP-ADPCM)
//      0x14 u32 loop start       0x18 u32 loop length (0 = one-shot)
//      0x1C u32 offset of the ADPCM parameter block, inside the .sdir
//
//    parameter block:
//      0x00 u16 bytes per frame  0x02 u8 initial predictor/scale  0x03 u8
//      0x04 s16 hist2            0x06 s16 hist1
//      0x08 s16 x 16 coefficients (8 pairs)
//

import Foundation

public struct MusyXSampleDirectory {

    public struct Sample: Codable, Equatable {
        public let id: Int
        public let offset: Int
        public let basePitch: Int
        public let sampleRate: Int
        public let sampleCount: Int
        /// The top byte of the count word: 0 is DSP-ADPCM, the only format
        /// this decodes.
        public let format: Int
        public let loopStart: Int
        public let loopLength: Int
        public let predictorScale: Int
        public let hist1: Int16
        public let hist2: Int16
        public let coefficients: [Int16]

        /// Bytes the sample occupies in the `.samp`: 8-byte frames of 14.
        public var byteLength: Int { (sampleCount + 13) / 14 * 8 }
    }

    public static let entrySize = 0x20
    public let samples: [Sample]

    public init(bytes: [UInt8]) throws {
        func u16(_ at: Int) throws -> Int {
            guard at + 2 <= bytes.count else { throw MusyXError.truncated(at) }
            return Int(bytes[at]) << 8 | Int(bytes[at + 1])
        }
        func u32(_ at: Int) throws -> Int {
            guard at + 4 <= bytes.count else { throw MusyXError.truncated(at) }
            return (try u16(at)) << 16 | (try u16(at + 2))
        }
        func s16(_ at: Int) throws -> Int16 { Int16(bitPattern: UInt16(try u16(at))) }

        var samples = [Sample]()
        var at = 0
        while at + Self.entrySize <= bytes.count {
            let id = try u16(at)
            if id == 0xFFFF { break }
            let countWord = try u32(at + 0x10)
            let params = try u32(at + 0x1C)
            samples.append(Sample(
                id: id,
                offset: try u32(at + 0x04),
                basePitch: Int(bytes[at + 0x0C]),
                sampleRate: try u16(at + 0x0E),
                sampleCount: countWord & 0xFF_FFFF,
                format: countWord >> 24,
                loopStart: try u32(at + 0x14),
                loopLength: try u32(at + 0x18),
                predictorScale: Int(bytes[min(params + 2, bytes.count - 1)]),
                hist1: try s16(params + 6),
                hist2: try s16(params + 4),
                coefficients: try (0 ..< 16).map { try s16(params + 8 + $0 * 2) }
            ))
            at += Self.entrySize
        }
        self.samples = samples
    }

    /// One sample as 16-bit PCM.
    public static func decode(_ sample: Sample, samp: [UInt8]) throws -> [Int16] {
        guard sample.format == 0 else { throw MusyXError.unsupportedFormat(sample.id, sample.format) }
        guard sample.offset + sample.byteLength <= samp.count else {
            throw MusyXError.sampleOutOfRange(sample.id, end: sample.offset + sample.byteLength, size: samp.count)
        }
        let adpcm = Array(samp[sample.offset ..< sample.offset + sample.byteLength])
        return ISFDSPADPCM.decode(
            adpcm: adpcm,
            coefficients: sample.coefficients,
            sampleLimit: sample.sampleCount,
            history: (sample.hist1, sample.hist2)
        )
    }

    /// One sample as a mono 16-bit WAV.
    public static func wav(_ sample: Sample, samp: [UInt8]) throws -> [UInt8] {
        let pcm = try decode(sample, samp: samp)
        return try WAVFile(sampleRate: UInt32(sample.sampleRate), channelCount: 1, samples: pcm).encoded().rawBytes
    }
}

public enum MusyXError: Error, CustomStringConvertible {
    case truncated(Int)
    case unsupportedFormat(Int, Int)
    case sampleOutOfRange(Int, end: Int, size: Int)

    public var description: String {
        switch self {
        case .truncated(let at):
            return "MusyX sample directory ends inside an entry (at 0x\(String(at, radix: 16)))"
        case let .unsupportedFormat(id, format):
            return "MusyX sample \(id) is in format \(format); only DSP-ADPCM (0) decodes"
        case let .sampleOutOfRange(id, end, size):
            return "MusyX sample \(id) runs to byte \(end), past the end of its .samp (\(size) bytes)"
        }
    }
}
