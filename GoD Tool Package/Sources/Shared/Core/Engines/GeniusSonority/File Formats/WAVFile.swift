//
//  WAVFile.swift
//
//  Minimal RIFF WAV reader/writer supporting 16-bit signed PCM —
//  exactly what `ISFFile` needs for its editable sidecar. Not a full WAV
//  library: no float, no 24-bit, no ADPCM inside WAV, no cue/smpl
//  chunks. Loop metadata lives in the paired `.isf.json` manifest
//  instead (more portable across audio editors, which routinely strip
//  `smpl` on export).
//

import Foundation
import GoDFoundation

struct WAVFile {
    let sampleRate: UInt32
    let channelCount: UInt32
    /// Interleaved 16-bit signed samples.
    let samples: [Int16]

    static func decode(bytes: GoDData) throws -> WAVFile {
        let data = bytes.copy
        data.setByteOrder(.little)
        let raw = data.rawBytes

        guard raw.count >= 44 else {
            throw FileFormatErrors.invalid(format: ISFFile.formatName)
        }
        // RIFF header
        guard raw[0] == 0x52, raw[1] == 0x49, raw[2] == 0x46, raw[3] == 0x46 else {
            throw FileFormatErrors.invalid(format: ISFFile.formatName)
        }
        guard raw[8] == 0x57, raw[9] == 0x41, raw[10] == 0x56, raw[11] == 0x45 else {
            throw FileFormatErrors.invalid(format: ISFFile.formatName)
        }

        // Walk the chunk list looking for fmt + data. Skip everything else
        // so editors that inject LIST/INFO/bext chunks don't trip us up.
        var cursor = 12
        var sampleRate: UInt32 = 0
        var channelCount: UInt16 = 0
        var bitsPerSample: UInt16 = 0
        var audioFormat: UInt16 = 0
        var samplesData: [UInt8]? = nil

        while cursor + 8 <= raw.count {
            let id = Array(raw[cursor..<cursor+4])
            let size = UInt32(raw[cursor+4])
                | (UInt32(raw[cursor+5]) << 8)
                | (UInt32(raw[cursor+6]) << 16)
                | (UInt32(raw[cursor+7]) << 24)
            cursor += 8
            let chunkEnd = cursor + Int(size)
            guard chunkEnd <= raw.count else { break }

            // "fmt "
            if id == [0x66, 0x6D, 0x74, 0x20] {
                audioFormat = UInt16(raw[cursor]) | (UInt16(raw[cursor+1]) << 8)
                channelCount = UInt16(raw[cursor+2]) | (UInt16(raw[cursor+3]) << 8)
                sampleRate = UInt32(raw[cursor+4])
                    | (UInt32(raw[cursor+5]) << 8)
                    | (UInt32(raw[cursor+6]) << 16)
                    | (UInt32(raw[cursor+7]) << 24)
                // bytesPerSecond @ cursor+8 (skip)
                // blockAlign @ cursor+12 (skip)
                bitsPerSample = UInt16(raw[cursor+14]) | (UInt16(raw[cursor+15]) << 8)
            }
            // "data"
            else if id == [0x64, 0x61, 0x74, 0x61] {
                samplesData = Array(raw[cursor..<chunkEnd])
            }

            cursor = chunkEnd
            // Chunks are word-aligned.
            if cursor % 2 != 0 { cursor += 1 }
        }

        guard audioFormat == 1 else {
            throw FileFormatErrors.failedToEncode(
                format: ISFFile.formatName,
                target: "unsupported WAV audio format \(audioFormat) (expected 1 = PCM)"
            )
        }
        guard bitsPerSample == 16 else {
            throw FileFormatErrors.failedToEncode(
                format: ISFFile.formatName,
                target: "unsupported WAV bit depth \(bitsPerSample) (expected 16)"
            )
        }
        guard let samplesBytes = samplesData else {
            throw FileFormatErrors.invalid(format: ISFFile.formatName)
        }

        var samples: [Int16] = []
        samples.reserveCapacity(samplesBytes.count / 2)
        var i = 0
        while i + 1 < samplesBytes.count {
            let lo = UInt16(samplesBytes[i])
            let hi = UInt16(samplesBytes[i + 1])
            let raw = (hi << 8) | lo
            samples.append(Int16(bitPattern: raw))
            i += 2
        }

        return WAVFile(sampleRate: sampleRate, channelCount: UInt32(channelCount), samples: samples)
    }

    func encoded() throws -> GoDData {
        let dataChunkSize = UInt32(samples.count * 2)
        let fileSize: UInt32 = 36 + dataChunkSize
        let byteRate = sampleRate * channelCount * 2
        let blockAlign = UInt16(channelCount * 2)

        let out = GoDData(byteOrder: .little)
        // RIFF header
        out.append(UInt8(0x52)); out.append(UInt8(0x49)); out.append(UInt8(0x46)); out.append(UInt8(0x46))
        out.append(fileSize)
        out.append(UInt8(0x57)); out.append(UInt8(0x41)); out.append(UInt8(0x56)); out.append(UInt8(0x45))
        // fmt chunk
        out.append(UInt8(0x66)); out.append(UInt8(0x6D)); out.append(UInt8(0x74)); out.append(UInt8(0x20))
        out.append(UInt32(16))          // PCM fmt size
        out.append(UInt16(1))           // PCM
        out.append(UInt16(channelCount))
        out.append(sampleRate)
        out.append(byteRate)
        out.append(blockAlign)
        out.append(UInt16(16))          // bits per sample
        // data chunk
        out.append(UInt8(0x64)); out.append(UInt8(0x61)); out.append(UInt8(0x74)); out.append(UInt8(0x61))
        out.append(dataChunkSize)
        for s in samples {
            out.append(UInt16(bitPattern: s))
        }
        return out
    }
}
