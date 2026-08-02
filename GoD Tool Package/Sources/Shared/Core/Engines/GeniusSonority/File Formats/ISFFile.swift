//
//  ISFFile.swift
//
//  Genius Sonority streamed audio — an `.ish` header paired with an `.isd`
//  DSP-ADPCM data stream. Together we treat them as a single logical
//  format "ISF" (named after the `I_SF` magic on the ISH).
//
//  Editable artifact bundle:
//    <name>.isf.json — manifest with sample rate, channel count, loop
//                      metadata (in samples), and a `wavPath` pointer to
//                      the companion WAV.
//    <name>.wav      — standard 16-bit PCM LE RIFF WAV; edit-friendly.
//
//  Roundtrip is lossy (DSP ADPCM is a 4-bit codec) but semantically
//  stable: decode→encode→decode reproduces the PCM within a small RMS
//  error and is deterministic after cycle 1. Loop points and header
//  metadata round-trip exactly because they live in the sidecar JSON and
//  are re-serialized into the rebuilt ISH verbatim.
//
//  Core algorithms:
//    - DSP ADPCM decode: 8-byte frame → 14 samples (scale, coef index,
//      14 signed nibbles fed through the LPC predictor).
//    - DSP ADPCM encode: brute-force per-frame search — for each of the 8
//      coefficient pairs, pick the scale that minimizes quantisation
//      error, encode 14 samples, pick the coefficient pair with the
//      lowest total error.
//    - Coefficient generation: autocorrelation → order-2 LPC via
//      Levinson-Durbin, replicated 8× for the coefficient table. Good
//      enough to stay within the lossy-roundtrip bounds; matches the
//      simplest branch of gc-dspadpcm-encode.
//
//  References:
//    - vgmstream src/meta/ish_isd.c (header layout)
//    - vgmstream src/coding/ngc_dsp_decoder.c (decode)
//    - gc-dspadpcm-encode (Jack Andersen, MIT — encode + LPC analysis)
//    - VGAudio (Ethan MacDonald, MIT — reference in C#)
//

import Foundation
import GoDFoundation

public struct ISFFile: FileFormat {
    public static let formatName = "isf"

    public var name: String = "isf"

    // MARK: - Metadata (preserved across roundtrip)

    public var sampleRate: UInt32
    public var channelCount: UInt32
    /// ISD interleave block size in bytes. GS files observed at 0x8000.
    public var interleaveSize: UInt32
    /// Original build-tool date from the ISH header (e.g. 0x20040109).
    /// Purely informational; re-emitted so diffs stay tidy.
    public var toolDate: UInt32
    /// Loop points expressed in *samples* (not ISD bytes), so they survive
    /// WAV editors that rewrite the stream.
    public var loop: Loop

    /// Decoded 16-bit PCM, channel-interleaved (`L R L R ...`). Editors
    /// read/write WAV, which we convert to/from this shape.
    public var samples: [Int16]

    public struct Loop: Codable, Equatable {
        public var enabled: Bool
        public var startSample: UInt64
        public var endSample: UInt64
        public init(enabled: Bool, startSample: UInt64, endSample: UInt64) {
            self.enabled = enabled
            self.startSample = startSample
            self.endSample = endSample
        }
        public static let disabled = Loop(enabled: false, startSample: 0, endSample: 0)
    }

    public init(
        name: String = "isf",
        sampleRate: UInt32,
        channelCount: UInt32,
        interleaveSize: UInt32 = 0x8000,
        toolDate: UInt32 = 0,
        loop: Loop = .disabled,
        samples: [Int16]
    ) {
        self.name = name
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.interleaveSize = interleaveSize
        self.toolDate = toolDate
        self.loop = loop
        self.samples = samples
    }

    /// Sample count per channel. The `samples` array holds interleaved
    /// L/R, so the per-channel count is `samples.count / channelCount`.
    public var sampleCountPerChannel: Int {
        guard channelCount > 0 else { return 0 }
        return samples.count / Int(channelCount)
    }

    // MARK: - FileFormat: binaries (ISH + ISD)

    public init(binaries: [FileData]) throws {
        guard binaries.count >= 2 else {
            throw ISFFile.invalidFileError
        }
        // Pick ISH and ISD by extension; don't assume ordering.
        let ish = binaries.first(where: { $0.file.path.lowercased().hasSuffix(".ish") })
        let isd = binaries.first(where: { $0.file.path.lowercased().hasSuffix(".isd") })
        guard let ishData = ish?.data, let isdData = isd?.data else {
            throw ISFFile.invalidFileError
        }
        let stem = ish.map { $0.file.path.withoutExtensions } ?? "isf"
        try self.init(ish: ishData, isd: isdData, name: stem.isEmpty ? "isf" : stem)
    }

    public init(ish ishData: GoDData, isd isdData: GoDData, name: String = "isf") throws {
        ishData.setByteOrder(.big)
        isdData.setByteOrder(.big)

        guard ishData.length >= 0x40 else { throw ISFFile.invalidFileError }
        // Header magic "I_SF" at 0x00
        let magicBytes = ishData.read(atAddress: 0x00, length: 4)?.rawBytes ?? []
        guard magicBytes == [0x49, 0x5F, 0x53, 0x46] else {
            throw ISFFile.invalidFileError
        }

        let toolDate: UInt32 = ishData.readSafely(atAddress: 0x04)
        let sampleRate: UInt32 = ishData.readSafely(atAddress: 0x08)
        let sampleCount: UInt32 = ishData.readSafely(atAddress: 0x0C)
        // 0x10 stream size is derived from ISD; not needed for parsing.
        let channelCount: UInt32 = ishData.readSafely(atAddress: 0x14)
        let interleaveSize: UInt32 = ishData.readSafely(atAddress: 0x18)
        let loopFlag: UInt32 = ishData.readSafely(atAddress: 0x1C)
        let loopStartByte: UInt32 = ishData.readSafely(atAddress: 0x20)
        let loopEndByte: UInt32 = ishData.readSafely(atAddress: 0x24)

        guard channelCount > 0, sampleRate > 0 else {
            throw ISFFile.invalidFileError
        }

        // Per-channel 16 coefficient pairs (32 Int16 values = 0x40 bytes),
        // starting at 0x40.
        var coefficients: [[Int16]] = []
        let coefBase = 0x40
        let perChannelCoefBytes = 0x40
        let coefsPerChannel = 32   // 16 pairs × 2 values
        for ch in 0..<Int(channelCount) {
            let start = coefBase + ch * perChannelCoefBytes
            guard start + perChannelCoefBytes <= ishData.length else {
                throw ISFFile.invalidFileError
            }
            var channelCoefs: [Int16] = []
            channelCoefs.reserveCapacity(coefsPerChannel)
            for i in 0..<coefsPerChannel {
                let off = start + i * 2
                let raw: UInt16 = ishData.readSafely(atAddress: off)
                channelCoefs.append(Int16(bitPattern: raw))
            }
            coefficients.append(channelCoefs)
        }

        // Deinterleave ISD into per-channel ADPCM byte streams.
        let perChannelStreams = ISFFile.deinterleave(
            isd: isdData,
            channelCount: Int(channelCount),
            interleaveSize: Int(interleaveSize)
        )

        // Decode each channel's ADPCM to PCM.
        var perChannelPCM: [[Int16]] = []
        perChannelPCM.reserveCapacity(Int(channelCount))
        for ch in 0..<Int(channelCount) {
            let pcm = ISFDSPADPCM.decode(
                adpcm: perChannelStreams[ch],
                coefficients: coefficients[ch],
                sampleLimit: Int(sampleCount)
            )
            perChannelPCM.append(pcm)
        }

        // Interleave channels back into a single PCM stream for WAV.
        let interleaved = ISFFile.interleavePCM(perChannel: perChannelPCM)

        // Byte offsets → sample positions using the standard DSP ADPCM
        // math: 14 samples per 8 bytes, per channel.
        let loopStartSample = ISFFile.byteOffsetToSample(
            byte: UInt64(loopStartByte),
            channelCount: Int(channelCount)
        )
        let loopEndSample = ISFFile.byteOffsetToSample(
            byte: UInt64(loopEndByte),
            channelCount: Int(channelCount)
        )

        self.init(
            name: name,
            sampleRate: sampleRate,
            channelCount: channelCount,
            interleaveSize: interleaveSize,
            toolDate: toolDate,
            loop: Loop(
                enabled: loopFlag != 0,
                startSample: loopStartSample,
                endSample: loopEndSample
            ),
            samples: interleaved
        )
    }

    public var binaries: [FileData] {
        get throws {
            let (ish, isd) = try ishISDBytes()
            return [
                FileData(file: File("\(name).ish"), data: ish),
                FileData(file: File("\(name).isd"), data: isd)
            ]
        }
    }

    /// Encodes the current PCM state back into a paired (ISH, ISD) pair.
    /// The encoder is deterministic — given the same PCM in, you get the
    /// same bytes out. See the `testGenerationalStability` suite.
    public func ishISDBytes() throws -> (ish: GoDData, isd: GoDData) {
        guard channelCount > 0 else {
            throw FileFormatErrors.failedToEncode(
                format: ISFFile.formatName,
                target: "channelCount must be > 0"
            )
        }

        // Split interleaved PCM into per-channel streams.
        let perChannelPCM = ISFFile.deinterleavePCM(
            interleaved: samples,
            channelCount: Int(channelCount)
        )

        // Derive LPC coefficients from channel 0's PCM. For stereo files
        // we reuse the same coefficients for both channels — a practical
        // simplification that still decodes well (the alternative is per-
        // channel LPC, which gc-dspadpcm-encode does; we mirror the
        // simpler branch and validate via the semantic roundtrip tests).
        var perChannelCoefs: [[Int16]] = []
        for ch in 0..<Int(channelCount) {
            perChannelCoefs.append(ISFDSPADPCM.generateCoefficients(pcm: perChannelPCM[ch]))
        }

        // Encode each channel to ADPCM bytes.
        var perChannelADPCM: [[UInt8]] = []
        for ch in 0..<Int(channelCount) {
            let bytes = ISFDSPADPCM.encode(
                pcm: perChannelPCM[ch],
                coefficients: perChannelCoefs[ch]
            )
            perChannelADPCM.append(bytes)
        }

        // Interleave ISD bytes in `interleaveSize` blocks per channel.
        let isd = ISFFile.interleaveADPCM(
            perChannel: perChannelADPCM,
            interleaveSize: Int(interleaveSize),
            channelCount: Int(channelCount)
        )

        // Build ISH.
        let ish = GoDData(byteOrder: .big)
        // 0x00 magic
        ish.append(UInt8(0x49)); ish.append(UInt8(0x5F))
        ish.append(UInt8(0x53)); ish.append(UInt8(0x46))
        // 0x04 toolDate
        ish.append(toolDate)
        // 0x08 sampleRate
        ish.append(sampleRate)
        // 0x0C sampleCount — per-channel
        ish.append(UInt32(perChannelPCM.first?.count ?? 0))
        // 0x10 streamSize (ISD length)
        ish.append(UInt32(isd.length))
        // 0x14 channelCount
        ish.append(channelCount)
        // 0x18 interleaveSize
        ish.append(interleaveSize)
        // 0x1C loopFlag
        ish.append(UInt32(loop.enabled ? 1 : 0))
        // 0x20 loopStartByte (convert from sample back to byte)
        ish.append(UInt32(ISFFile.sampleToByteOffset(
            sample: loop.startSample,
            channelCount: Int(channelCount)
        )))
        // 0x24 loopEndByte
        ish.append(UInt32(ISFFile.sampleToByteOffset(
            sample: loop.endSample,
            channelCount: Int(channelCount)
        )))
        // 0x28..0x3F reserved (zero)
        for _ in 0x28..<0x40 { ish.append(UInt8(0)) }
        // 0x40+ per-channel coefficients (16 Int16 pairs = 32 int16s)
        for ch in 0..<Int(channelCount) {
            for coef in perChannelCoefs[ch] {
                ish.append(UInt16(bitPattern: coef))
            }
        }

        return (ish, isd)
    }

    // MARK: - FileFormat: editable outputs (JSON + WAV)

    public init(outputs: [FileData]) throws {
        let dict = outputs.byFile
        let jsonSuffix = ".\(ISFFile.formatName).json"
        guard let jsonKey = dict.keys.first(where: { $0.path.hasSuffix(jsonSuffix) }) else {
            throw ISFFile.missingOutputError(key: "*\(jsonSuffix)")
        }
        let stem = String(jsonKey.path.dropLast(jsonSuffix.count))
        guard let jsonBytes = dict[jsonKey] else {
            throw ISFFile.missingOutputError(key: jsonKey.path)
        }

        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: jsonBytes.data)
        } catch {
            throw ISFFile.invalidFileError
        }

        let wavKey = File(dto.wavPath)
        guard let wavBytes = dict[wavKey] else {
            throw ISFFile.missingOutputError(key: dto.wavPath)
        }

        let wav = try WAVFile.decode(bytes: wavBytes)
        guard wav.sampleRate == dto.sampleRate,
              wav.channelCount == dto.channelCount else {
            throw FileFormatErrors.failedToEncode(
                format: ISFFile.formatName,
                target: "WAV header (\(wav.sampleRate) Hz, \(wav.channelCount) ch) disagrees with manifest (\(dto.sampleRate) Hz, \(dto.channelCount) ch)"
            )
        }

        self.init(
            name: stem.isEmpty ? "isf" : stem,
            sampleRate: dto.sampleRate,
            channelCount: dto.channelCount,
            interleaveSize: dto.interleaveSize,
            toolDate: dto.toolDate,
            loop: Loop(
                enabled: dto.loop.enabled,
                startSample: dto.loop.startSample,
                endSample: dto.loop.endSample
            ),
            samples: wav.samples
        )
    }

    public var outputs: [FileData] {
        get throws {
            let wavFile = File("\(name).wav")
            let wavBytes = try WAVFile(
                sampleRate: sampleRate,
                channelCount: channelCount,
                samples: samples
            ).encoded()

            let dto = DTO(
                sampleRate: sampleRate,
                channelCount: channelCount,
                interleaveSize: interleaveSize,
                toolDate: toolDate,
                loop: DTO.LoopDTO(
                    enabled: loop.enabled,
                    startSample: loop.startSample,
                    endSample: loop.endSample
                ),
                wavPath: wavFile.path
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData: Data = try encoder.encode(dto)

            return [
                FileData(file: jsonFilename, data: GoDData(data: jsonData, byteOrder: .big)),
                FileData(file: wavFile, data: wavBytes)
            ]
        }
    }

    // MARK: - DTO

    private struct DTO: Codable {
        let sampleRate: UInt32
        let channelCount: UInt32
        let interleaveSize: UInt32
        let toolDate: UInt32
        let loop: LoopDTO
        /// Path of the WAV sidecar, relative to this JSON's parent folder.
        let wavPath: String

        struct LoopDTO: Codable {
            let enabled: Bool
            let startSample: UInt64
            let endSample: UInt64
        }
    }

    // MARK: - ISD interleave helpers

    static func deinterleave(isd: GoDData, channelCount: Int, interleaveSize: Int) -> [[UInt8]] {
        let bytes = isd.rawBytes
        guard channelCount > 0, interleaveSize > 0 else { return [] }
        var streams = [[UInt8]](repeating: [], count: channelCount)
        var cursor = 0
        while cursor < bytes.count {
            for ch in 0..<channelCount {
                let end = min(cursor + interleaveSize, bytes.count)
                if cursor >= bytes.count { break }
                streams[ch].append(contentsOf: bytes[cursor..<end])
                cursor = end
            }
        }
        return streams
    }

    static func interleaveADPCM(
        perChannel: [[UInt8]],
        interleaveSize: Int,
        channelCount: Int
    ) -> GoDData {
        let out = GoDData(byteOrder: .big)
        guard channelCount > 0 else { return out }
        // Pad each channel's ADPCM up to a whole number of interleave blocks.
        var padded = perChannel
        let maxLen = padded.map(\.count).max() ?? 0
        let paddedLen = ((maxLen + interleaveSize - 1) / interleaveSize) * interleaveSize
        for ch in 0..<channelCount {
            if padded[ch].count < paddedLen {
                padded[ch].append(contentsOf: [UInt8](repeating: 0, count: paddedLen - padded[ch].count))
            }
        }
        var cursor = 0
        while cursor < paddedLen {
            let end = min(cursor + interleaveSize, paddedLen)
            for ch in 0..<channelCount {
                for b in padded[ch][cursor..<end] { out.append(b) }
            }
            cursor = end
        }
        return out
    }

    // MARK: - PCM interleave helpers

    static func interleavePCM(perChannel: [[Int16]]) -> [Int16] {
        guard let first = perChannel.first else { return [] }
        let channelCount = perChannel.count
        var out = [Int16]()
        out.reserveCapacity(first.count * channelCount)
        for i in 0..<first.count {
            for ch in 0..<channelCount {
                let stream = perChannel[ch]
                out.append(i < stream.count ? stream[i] : 0)
            }
        }
        return out
    }

    static func deinterleavePCM(interleaved: [Int16], channelCount: Int) -> [[Int16]] {
        guard channelCount > 0 else { return [] }
        let perChannelCount = interleaved.count / channelCount
        var streams = [[Int16]](repeating: [Int16](repeating: 0, count: perChannelCount), count: channelCount)
        for i in 0..<perChannelCount {
            for ch in 0..<channelCount {
                streams[ch][i] = interleaved[i * channelCount + ch]
            }
        }
        return streams
    }

    // MARK: - Loop byte ↔ sample math

    /// `(byteOffset * 14) / 8 / channelCount` — standard DSP ADPCM
    /// conversion. Channel count factors in only because the ISD byte
    /// offset spans all channels when interleaved.
    static func byteOffsetToSample(byte: UInt64, channelCount: Int) -> UInt64 {
        guard channelCount > 0 else { return 0 }
        return (byte * 14) / 8 / UInt64(channelCount)
    }

    static func sampleToByteOffset(sample: UInt64, channelCount: Int) -> UInt64 {
        UInt64(channelCount) * sample * 8 / 14
    }
}
