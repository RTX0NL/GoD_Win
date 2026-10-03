//
//  ISFFile.swift
//
//  Genius Sonority streamed audio — an `.ish` header paired with an `.isd`
//  DSP-ADPCM data stream. Together we treat them as a single logical
//  format "ISF" (named after the `I_SF` magic on the ISH).
//
//  Editable artifact bundle:
//    <name>.isf.json — the stream's control points as seconds, the two
//                      packer fields the audio doesn't imply
//                      (`interleaveSize`, `creationDate`), and a `wavPath`
//                      pointer to the companion WAV. Sample rate and
//                      channel count are *not* here: the WAV says both.
//    <name>.wav      — standard 16-bit PCM LE RIFF WAV; edit-friendly.
//
//  Both halves are rebuilt from scratch from the WAV and the manifest —
//  nothing of the original header is consulted. The ADPCM body is lossy (a
//  4-bit codec); the 0x40-byte header comes back byte-identical except the
//  content length at 0x10, which is derived from the stream this build
//  encodes and so describes it rather than the original (see below).
//
//  Control points are **nibble addresses** into one channel's ADPCM
//  stream, not byte offsets into the ISD. A frame is 8 bytes = 16
//  nibbles, of which the first 2 are the frame header, so the first
//  sample sits at nibble 2 — the value 477 of 477 non-looping real
//  headers carry at 0x20.
//
//  The game's own stream setup pins both the unit and the field roles.
//  `GSsndStreamPreFunc` hands the FSYS loader `stream + 0x40` as the
//  buffer to read the ISH into, so the words at `stream + 0x5C / 0x60 /
//  0x64 / 0x68` are ISH 0x1C / 0x20 / 0x24 / 0x28. `GSsndStreamPostFunc`
//  then reads 0x20 and 0x24 as the loop start and end when the flag is
//  set and 0x28 as the end when it is clear, and converts 0x28 through
//  `_sndStreamNibble_HeaderON2OFF` — a multiply by 14/16 — regardless.
//  (Inferring the roles from field values alone gets 0x24 and 0x28 the
//  wrong way round, because a looping track's authored loop end sits
//  past its 0x28.)
//
//  Measured on 565 real ISH headers spanning 71 sample rates: 0x28 is
//  non-zero on 565/565, 0x2C..0x3F is zero on 565/565, and all 1,695
//  control words are exactly representable as sample positions and so as
//  seconds at 6 decimal places. The only address that cannot survive the
//  manifest is one landing on a frame's two header nibbles, which names no
//  sample; none of the 1,695 does, and such a value resolves to its
//  frame's first sample rather than failing the dump.
//
//  `0x10` is the exception to carrying metadata, because it is a property
//  of the ADPCM rather than an authored choice: the games' packer stops
//  mid-frame where this encoder emits whole frames, making their value
//  0-13 bytes smaller on 464 of the 565. Replaying theirs would describe a
//  stream this build didn't write.
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
    /// `0x04` — the packer's build date, hex-coded as `0xYYYYMMDD`
    /// (`0x20040109` on all 565 real headers, the only value in existence
    /// on the three games' discs). Purely informational; re-emitted so
    /// diffs stay tidy. The manifest writes it as an ISO 8601 date — see
    /// `isoDate(forCreationDate:)`.
    public var creationDate: UInt32
    /// `0x1C`, `0x20` and `0x24` — the loop flag and the loop's start and
    /// end, as nibble addresses.
    public var loop: Loop
    /// `0x28` — the stream's end, as a nibble address. The game converts
    /// this one to a sample total unconditionally, and uses it as the
    /// playback end when the loop flag is clear.
    public var streamEndNibble: UInt32

    /// Decoded 16-bit PCM, channel-interleaved (`L R L R ...`). Editors
    /// read/write WAV, which we convert to/from this shape.
    public var samples: [Int16]

    public struct Loop: Equatable {
        /// `0x1C` — zero means the stream plays through once.
        public var enabled: Bool
        /// `0x20` — nibble address the stream jumps back to.
        public var startNibble: UInt32
        /// `0x24` — nibble address the stream loops from.
        public var endNibble: UInt32
        public init(enabled: Bool, startNibble: UInt32, endNibble: UInt32) {
            self.enabled = enabled
            self.startNibble = startNibble
            self.endNibble = endNibble
        }
    }

    /// `streamEndNibble` and `loop` default to the games' own non-looping
    /// convention for the given PCM: the stream ends at its last sample,
    /// and a stream that doesn't loop carries loop start 2 (the first
    /// sample) and loop end equal to the stream end — which is what all
    /// 477 non-looping real headers hold.
    public init(
        name: String = "isf",
        sampleRate: UInt32,
        channelCount: UInt32,
        interleaveSize: UInt32 = 0x8000,
        creationDate: UInt32 = 0,
        loop: Loop? = nil,
        streamEndNibble: UInt32? = nil,
        samples: [Int16]
    ) {
        self.name = name
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.interleaveSize = interleaveSize
        self.creationDate = creationDate
        self.samples = samples

        let channels = max(1, Int(channelCount))
        let perChannel = samples.count / channels
        let end = streamEndNibble
            ?? ISFFile.nibble(forSample: max(0, perChannel - 1))
        self.streamEndNibble = end
        self.loop = loop ?? Loop(
            enabled: false,
            startNibble: UInt32(ISFFile.frameHeaderNibbles),
            endNibble: end
        )
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

        let creationDate: UInt32 = ishData.readSafely(atAddress: 0x04)
        let sampleRate: UInt32 = ishData.readSafely(atAddress: 0x08)
        let sampleCount: UInt32 = ishData.readSafely(atAddress: 0x0C)
        // 0x10 is the stream's content length. It is a property of the
        // ADPCM, not an authored choice, so it is re-derived on write from
        // the stream actually encoded rather than read here.
        let channelCount: UInt32 = ishData.readSafely(atAddress: 0x14)
        let interleaveSize: UInt32 = ishData.readSafely(atAddress: 0x18)
        let loopFlag: UInt32 = ishData.readSafely(atAddress: 0x1C)
        let loopStartNibble: UInt32 = ishData.readSafely(atAddress: 0x20)
        let loopEndNibble: UInt32 = ishData.readSafely(atAddress: 0x24)
        let streamEndNibble: UInt32 = ishData.readSafely(atAddress: 0x28)

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

        self.init(
            name: name,
            sampleRate: sampleRate,
            channelCount: channelCount,
            interleaveSize: interleaveSize,
            creationDate: creationDate,
            loop: Loop(
                enabled: loopFlag != 0,
                startNibble: loopStartNibble,
                endNibble: loopEndNibble
            ),
            streamEndNibble: streamEndNibble,
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

        // 0x10 describes the ADPCM this build encoded, before the ISD is
        // padded out to whole interleave blocks. Deriving it is what makes
        // it right for *our* stream: the games' own value is 0-13 bytes
        // smaller on 464 of 565 real headers because their packer stopped
        // mid-frame where we emit whole frames.
        let contentSize = UInt32(perChannelADPCM.reduce(0) { $0 + $1.count })

        // Build ISH.
        let ish = GoDData(byteOrder: .big)
        // 0x00 magic
        ish.append(UInt8(0x49)); ish.append(UInt8(0x5F))
        ish.append(UInt8(0x53)); ish.append(UInt8(0x46))
        // 0x04 creationDate
        ish.append(creationDate)
        // 0x08 sampleRate
        ish.append(sampleRate)
        // 0x0C sampleCount — per-channel
        ish.append(UInt32(perChannelPCM.first?.count ?? 0))
        // 0x10 content length — not the (block-padded) ISD length.
        ish.append(contentSize)
        // 0x14 channelCount
        ish.append(channelCount)
        // 0x18 interleaveSize
        ish.append(interleaveSize)
        // 0x1C loopFlag
        ish.append(UInt32(loop.enabled ? 1 : 0))
        // 0x20 loop start, 0x24 loop end, 0x28 stream end — all nibble
        // addresses, all carried verbatim.
        ish.append(loop.startNibble)
        ish.append(loop.endNibble)
        ish.append(streamEndNibble)
        // 0x2C..0x3F reserved — zero on all 565 real headers measured.
        for _ in 0x2C..<0x40 { ish.append(UInt8(0)) }
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

        // The WAV is the audio, so it is the authority on rate and channel
        // count; the manifest carries neither. Duplicating them would only
        // create a pair that can disagree — and swapping in a WAV at another
        // rate is an ordinary edit, not an error to refuse.
        let wav = try WAVFile.decode(bytes: wavBytes)
        let rate = wav.sampleRate

        self.init(
            name: stem.isEmpty ? "isf" : stem,
            sampleRate: rate,
            channelCount: wav.channelCount,
            interleaveSize: dto.interleaveSize,
            creationDate: ISFFile.creationDate(forISODate: dto.creationDate),
            loop: Loop(
                enabled: dto.loop.enabled,
                startNibble: ISFFile.nibble(forSeconds: dto.loop.startSeconds, sampleRate: rate),
                endNibble: ISFFile.nibble(forSeconds: dto.loop.endSeconds, sampleRate: rate)
            ),
            streamEndNibble: ISFFile.nibble(
                forSeconds: dto.streamEndSeconds, sampleRate: rate
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
                interleaveSize: interleaveSize,
                creationDate: ISFFile.isoDate(forCreationDate: creationDate),
                loop: DTO.LoopDTO(
                    enabled: loop.enabled,
                    startSeconds: ISFFile.seconds(forNibble: loop.startNibble, sampleRate: sampleRate),
                    endSeconds: ISFFile.seconds(forNibble: loop.endNibble, sampleRate: sampleRate)
                ),
                streamEndSeconds: ISFFile.seconds(forNibble: streamEndNibble, sampleRate: sampleRate),
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

    /// Everything the rebuild needs that the WAV cannot say.
    ///
    /// Sample rate and channel count are deliberately absent: the WAV
    /// header carries both, so repeating them here would only create a
    /// second source of truth that can fall out of step with the audio.
    private struct DTO: Codable {
        let interleaveSize: UInt32
        /// ISO 8601 (`2004-01-09`), or `0x`-prefixed hex when the stored
        /// word isn't a date.
        let creationDate: String
        let loop: LoopDTO
        /// Where the stream ends, in seconds.
        let streamEndSeconds: Double
        /// Path of the WAV sidecar, relative to this JSON's parent folder.
        let wavPath: String

        struct LoopDTO: Codable {
            let enabled: Bool
            let startSeconds: Double
            let endSeconds: Double
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

    // MARK: - Nibble address ↔ sample ↔ seconds

    /// Bytes in one DSP ADPCM frame.
    static let bytesPerFrame = 8
    /// Nibbles in one frame — two per byte.
    static let nibblesPerFrame = 16
    /// Nibbles at the head of each frame taken by the frame header byte
    /// (scale and coefficient index), which carry no sample.
    static let frameHeaderNibbles = 2
    /// Samples one frame decodes to.
    static let samplesPerFrame = 14

    /// Decimal places the manifest writes seconds at. Recovering the
    /// sample needs better than `0.5 / sampleRate` — 1.13e-5 s at the
    /// corpus's highest rate of 44.1 kHz — and six places give 5e-7, a
    /// 22x margin. Four places are not enough: 863 of the corpus's 1,695
    /// control words come back wrong, drifting up to 1.86 samples, and
    /// three places drift up to 19.5.
    static let secondsPrecision = 6

    /// The sample a nibble address points at.
    ///
    /// A frame's two header nibbles name no sample, so an address landing on
    /// one resolves to that frame's first sample — the nearest thing it can
    /// mean. Nothing in the 565-header corpus does (every control word has
    /// `nibble % 16 >= 2`), and such an address is the only one that doesn't
    /// survive a round trip through a sample position.
    static func sample(forNibble nibble: UInt32) -> Int {
        let (frame, position) = Int(nibble).quotientAndRemainder(dividingBy: nibblesPerFrame)
        return frame * samplesPerFrame + max(0, position - frameHeaderNibbles)
    }

    /// The nibble address of a sample. Inverse of `sample(forNibble:)` on
    /// every address that names a sample.
    static func nibble(forSample sample: Int) -> UInt32 {
        let (frame, position) = max(0, sample).quotientAndRemainder(dividingBy: samplesPerFrame)
        return UInt32(frame * nibblesPerFrame + position + frameHeaderNibbles)
    }

    static func seconds(forNibble nibble: UInt32, sampleRate: UInt32) -> Double {
        guard sampleRate > 0 else { return 0 }
        let scale = pow(10.0, Double(secondsPrecision))
        return (Double(sample(forNibble: nibble)) / Double(sampleRate) * scale).rounded() / scale
    }

    // MARK: - Creation date

    //  The word at 0x04 is a date with its digits written in hex —
    //  `0x20040109` is 2004-01-09 — which is the only encoding that
    //  survives contact with the value. Unix epoch seconds would put it in
    //  January 1987, seconds since 2000 in January 2017, a DOS/FAT
    //  date+time pair at month 0, and the GameCube's own `OSTime` ticks 13
    //  seconds past midnight on 2000-01-01. The year 2004 is where it has
    //  to be: between Colosseum's Japanese release (2003-11-21) and XD's
    //  (2005-08-04), and just before the 2004/05/21 SDK apploader on XD's
    //  own disc.
    //
    //  Month-before-day follows the platform: that apploader stores its
    //  date as ASCII `YYYY/MM/DD`, and its `21` can only be a day, so
    //  Nintendo's convention on the same disc is unambiguous. It is also
    //  the only field order that leaves the packed word sortable, which is
    //  the point of packing a date into one integer. Strictly, a single
    //  observed value cannot *prove* month before day — every ISH on every
    //  disc carries `0x20040109` — so this rests on the convention rather
    //  than on a second data point.

    /// `0x20040109` → `"2004-01-09"`.
    ///
    /// A word that isn't a valid hex-coded date is written as a
    /// `0x`-prefixed literal instead, so it still round-trips. Same rule
    /// the typed-table exporters use for a value their spelling can't
    /// carry.
    static func isoDate(forCreationDate word: UInt32) -> String {
        let digits = String(format: "%08X", word)
        guard !digits.contains(where: { !$0.isNumber }),
              let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.suffix(2)),
              (1...12).contains(month), (1...31).contains(day) else {
            return String(format: "0x%08X", word)
        }
        return "\(digits.prefix(4))-\(digits.dropFirst(4).prefix(2))-\(digits.suffix(2))"
    }

    /// Inverse of `isoDate(forCreationDate:)`, accepting either spelling.
    static func creationDate(forISODate text: String) -> UInt32 {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("0x") {
            return UInt32(trimmed.dropFirst(2), radix: 16) ?? 0
        }
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = UInt32(parts[0]), let month = UInt32(parts[1]), let day = UInt32(parts[2]),
              year <= 9999, month <= 99, day <= 99 else {
            return 0
        }
        // Back to hex-coded digits: each field keeps its decimal spelling.
        return UInt32(String(format: "%04u%02u%02u", year, month, day), radix: 16) ?? 0
    }

    /// Seconds back to a nibble address, rounding to the *nearest* sample
    /// so the manifest's printed precision is all that has to be right —
    /// a hand-typed `0.5334` lands on the same sample as `0.533425`.
    static func nibble(forSeconds seconds: Double, sampleRate: UInt32) -> UInt32 {
        nibble(forSample: Int((seconds * Double(sampleRate)).rounded()))
    }
}
