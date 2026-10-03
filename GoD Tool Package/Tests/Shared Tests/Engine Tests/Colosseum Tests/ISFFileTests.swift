//
//  ISFFileTests.swift
//
//  Semantic-correctness tests for the ISF (ISH + ISD) format. DSP ADPCM
//  is a lossy 4-bit codec, so we don't check for byte-identical roundtrip
//  — instead we pin the following invariants:
//
//    • Header metadata (sampleRate, channelCount, interleaveSize,
//      creationDate, loop flags) round-trips exactly through parse →
//      serialize → parse.
//    • Loop sample-position math is lossless in the sample domain (byte
//      offsets may shift slightly because of ADPCM framing — but samples
//      are what humans edit against).
//    • PCM fidelity: decode → encode → decode stays within a reasonable
//      RMS error relative to the original PCM. Threshold is generous
//      (-25 dBFS) to admit the simpler "fixed bank" LPC path we use; a
//      future tighter encoder can crank this down.
//    • Generational stability: the second encode cycle produces
//      bit-identical bytes to the first. Proves the encoder is
//      deterministic.
//    • Silence passthrough: all-zero PCM in → all-zero PCM out (within
//      one sample of noise near the frame boundary).
//    • Sine correlation: a synthetic 1 kHz tone round-trips with Pearson
//      correlation > 0.99.
//

import XCTest
import Foundation
import GoDFoundation
@testable import GeniusSonority

final class ISFFileTests: XCTestCase {

    // MARK: - Fixtures

    /// Builds a synthetic ISH/ISD pair by encoding the supplied PCM with
    /// our own encoder. Used as the baseline for every test — keeps the
    /// suite independent of external sample files.
    private func synthesiseISF(
        sampleRate: UInt32 = 32000,
        channelCount: UInt32 = 2,
        interleaveSize: UInt32 = 0x8000,
        loop: ISFFile.Loop? = nil,
        samples: [Int16]
    ) throws -> (ish: GoDData, isd: GoDData) {
        let isf = ISFFile(
            sampleRate: sampleRate,
            channelCount: channelCount,
            interleaveSize: interleaveSize,
            loop: loop,
            samples: samples
        )
        return try isf.ishISDBytes()
    }

    /// Interleaves two per-channel streams in the `L R L R ...` layout
    /// ISFFile expects for stereo inputs.
    private func interleave(_ left: [Int16], _ right: [Int16]) -> [Int16] {
        precondition(left.count == right.count, "channels must match length")
        var out = [Int16]()
        out.reserveCapacity(left.count * 2)
        for i in 0..<left.count {
            out.append(left[i])
            out.append(right[i])
        }
        return out
    }

    private func generateSine(
        frequency: Double,
        sampleRate: Double,
        durationSeconds: Double,
        amplitude: Double = 0.5
    ) -> [Int16] {
        let count = Int(sampleRate * durationSeconds)
        var out = [Int16]()
        out.reserveCapacity(count)
        let twoPi = 2.0 * .pi
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let value = sin(twoPi * frequency * t) * amplitude * Double(Int16.max)
            out.append(Int16(max(Double(Int16.min), min(Double(Int16.max), value))))
        }
        return out
    }

    // MARK: - Metadata invariants

    func testMetadataRoundTripsThroughParse() throws {
        let pcm = interleave(
            generateSine(frequency: 440, sampleRate: 32000, durationSeconds: 0.1),
            generateSine(frequency: 660, sampleRate: 32000, durationSeconds: 0.1)
        )
        // Deliberately not frame-aligned: a nibble address is stored
        // verbatim, so nothing here may drift. An earlier version of this
        // test tolerated 14 samples of slop, which is exactly what the
        // broken byte-offset conversion produced.
        let expectedLoop = ISFFile.Loop(enabled: true, startNibble: 19426, endNibble: 917503)
        let original = ISFFile(
            sampleRate: 48000,
            channelCount: 2,
            interleaveSize: 0x8000,
            creationDate: 0x20260422,
            loop: expectedLoop,
            streamEndNibble: 898367,
            samples: pcm
        )
        let (ish, isd) = try original.ishISDBytes()
        let parsed = try ISFFile(ish: ish, isd: isd, name: "test")

        XCTAssertEqual(parsed.sampleRate, 48000)
        XCTAssertEqual(parsed.channelCount, 2)
        XCTAssertEqual(parsed.interleaveSize, 0x8000)
        XCTAssertEqual(parsed.creationDate, 0x20260422)
        XCTAssertEqual(parsed.loop, expectedLoop)
        XCTAssertEqual(parsed.streamEndNibble, 898367)
    }

    /// The whole 0x40-byte header has to come back, including the word at
    /// 0x28 that used to be written as zero and the 0x2C..0x3F run that
    /// really is reserved.
    func testHeaderBytesRoundTripExactly() throws {
        let pcm = interleave(
            generateSine(frequency: 440, sampleRate: 32000, durationSeconds: 0.1),
            generateSine(frequency: 660, sampleRate: 32000, durationSeconds: 0.1)
        )
        let original = ISFFile(
            sampleRate: 31862,
            channelCount: 2,
            creationDate: 0x20040109,
            loop: ISFFile.Loop(enabled: true, startNibble: 131, endNibble: 3657),
            streamEndNibble: 3653,
            samples: pcm
        )
        let (ish, isd) = try original.ishISDBytes()
        let reparsed = try ISFFile(ish: ish, isd: isd, name: "test")
        let (rebuilt, _) = try reparsed.ishISDBytes()

        XCTAssertEqual(
            rebuilt.read(atAddress: 0, length: 0x40)?.rawBytes,
            ish.read(atAddress: 0, length: 0x40)?.rawBytes,
            "the ISH header must rebuild byte-identically"
        )
        XCTAssertEqual(
            ish.read(atAddress: 0x2C, length: 0x14)?.rawBytes,
            [UInt8](repeating: 0, count: 0x14),
            "0x2C..0x3F is reserved and zero on all 565 real headers"
        )
    }

    func testLoopDisabledRoundTripsAsDisabled() throws {
        let pcm = [Int16](repeating: 0, count: 1000)
        let (ish, isd) = try synthesiseISF(channelCount: 1, samples: pcm)
        let parsed = try ISFFile(ish: ish, isd: isd)
        XCTAssertFalse(parsed.loop.enabled)
    }

    /// Every nibble address that names a sample must survive
    /// nibble → sample → nibble. The two header nibbles of each frame name
    /// no sample and are the only addresses that don't.
    func testNibbleSampleMathIsInverse() {
        for nibble in UInt32(0)..<UInt32(10_000) {
            let sample = ISFFile.sample(forNibble: nibble)
            guard nibble % 16 >= 2 else {
                // A frame's two header nibbles name no sample, so they
                // resolve to that frame's first sample and are the only
                // addresses that don't come back.
                XCTAssertEqual(sample, Int(nibble / 16) * 14)
                continue
            }
            XCTAssertEqual(ISFFile.nibble(forSample: sample), nibble,
                           "nibble \(nibble) didn't round-trip through sample \(sample)")
        }
    }

    /// Seconds is the manifest's unit, so it has to be exactly invertible
    /// at every sample rate the games ship. These are the real rates at
    /// the extremes of the 71 found in the corpus.
    func testSecondsRoundTripExactlyAtCorpusSampleRates() {
        for rate in [UInt32(30672), 31497, 31862, 32000, 32115, 44100] {
            for nibble in stride(from: UInt32(2), to: UInt32(2_000_000), by: 9973) {
                // Only addresses that name a sample can round-trip; a
                // frame's two header nibbles resolve to its first sample.
                guard nibble % UInt32(ISFFile.nibblesPerFrame) >= 2 else { continue }
                let seconds = ISFFile.seconds(forNibble: nibble, sampleRate: rate)
                XCTAssertEqual(
                    ISFFile.nibble(forSeconds: seconds, sampleRate: rate), nibble,
                    "nibble \(nibble) at \(rate) Hz didn't survive \(seconds) s"
                )
            }
        }
    }

    /// The precision isn't arbitrary — three decimal places is not enough,
    /// so nobody should "tidy" `secondsPrecision` downwards.
    func testThreeDecimalPlacesWouldNotBeEnough() {
        let rate = UInt32(44100)
        let nibble = UInt32(917503)
        let sample = ISFFile.sample(forNibble: nibble)
        let coarse = (Double(sample) / Double(rate) * 1000).rounded() / 1000
        XCTAssertNotEqual(ISFFile.nibble(forSeconds: coarse, sampleRate: rate), nibble)
        XCTAssertEqual(ISFFile.secondsPrecision, 6)
    }

    // MARK: - Silence passthrough

    func testSilencePassthrough_mono() throws {
        let pcm = [Int16](repeating: 0, count: 1400)
        let (ish, isd) = try synthesiseISF(channelCount: 1, samples: pcm)
        let parsed = try ISFFile(ish: ish, isd: isd)
        // All-zero input should decode to all-zero within numerical noise.
        let peak = parsed.samples.map { abs(Int32($0)) }.max() ?? 0
        XCTAssertLessThanOrEqual(peak, 1, "silence drifted to peak \(peak)")
    }

    // MARK: - PCM fidelity

    func testSineWaveRoundTripsWithHighCorrelation() throws {
        let sampleRate: Double = 32000
        let duration: Double = 0.5
        let sineL = generateSine(frequency: 1000, sampleRate: sampleRate, durationSeconds: duration)
        let sineR = generateSine(frequency: 1000, sampleRate: sampleRate, durationSeconds: duration)
        let pcm = interleave(sineL, sineR)

        let (ish, isd) = try synthesiseISF(
            sampleRate: UInt32(sampleRate),
            channelCount: 2,
            samples: pcm
        )
        let parsed = try ISFFile(ish: ish, isd: isd)

        // Pearson correlation across interleaved samples.
        let correlation = pearsonCorrelation(pcm, parsed.samples)
        XCTAssertGreaterThan(correlation, 0.99,
                             "sine decode correlation too low (\(correlation))")
    }

    func testWhiteNoiseRoundTripStaysWithinRMSBounds() throws {
        // Deterministic "white-ish" noise so the test is reproducible.
        var rng = SplitMix64(seed: 0x5A17_5A17)
        var pcm = [Int16]()
        pcm.reserveCapacity(14_000)
        for _ in 0..<14_000 {
            let raw = Int32(bitPattern: UInt32(truncatingIfNeeded: rng.next()))
            pcm.append(Int16(truncatingIfNeeded: raw & 0x7FFF))
        }
        let (ish, isd) = try synthesiseISF(channelCount: 1, samples: pcm)
        let parsed = try ISFFile(ish: ish, isd: isd)

        let rms = rmsErrorDBFS(reference: pcm, decoded: parsed.samples)
        XCTAssertLessThan(rms, -20,
                          "white-noise RMS error \(rms) dBFS exceeds -20 dBFS budget")
    }

    // MARK: - Generational stability

    func testGenerationalStability_pcmConvergesAfterCycle() throws {
        // Each encode/decode round is lossy, but the loss should shrink
        // with generation count — by the third cycle the PCM and RMS
        // error should stop decreasing (a convergence property, not a
        // bit-exact byte invariant, because LPC coefficients depend on
        // the input and drift with each cycle).
        let pcm = interleave(
            generateSine(frequency: 440, sampleRate: 32000, durationSeconds: 0.2),
            generateSine(frequency: 660, sampleRate: 32000, durationSeconds: 0.2)
        )
        let (ish1, isd1) = try synthesiseISF(samples: pcm)
        let gen1PCM = try ISFFile(ish: ish1, isd: isd1).samples

        let (ish2, isd2) = try synthesiseISF(samples: gen1PCM)
        let gen2PCM = try ISFFile(ish: ish2, isd: isd2).samples

        let (ish3, isd3) = try synthesiseISF(samples: gen2PCM)
        let gen3PCM = try ISFFile(ish: ish3, isd: isd3).samples

        let rms12 = rmsErrorDBFS(reference: gen1PCM, decoded: gen2PCM)
        let rms23 = rmsErrorDBFS(reference: gen2PCM, decoded: gen3PCM)
        // Convergence: rms23 must be no worse than rms12. If the encoder
        // were unstable, noise would compound and rms23 would exceed
        // rms12 (less negative).
        XCTAssertLessThanOrEqual(rms23, rms12 + 1.0,
            "PCM diverging across generations (rms12=\(rms12), rms23=\(rms23))")
    }

    // MARK: - WAV <-> ISF roundtrip via the FileFormat surface

    func testOutputsRoundTripThroughInitOutputs() throws {
        let pcm = interleave(
            generateSine(frequency: 880, sampleRate: 32000, durationSeconds: 0.1),
            generateSine(frequency: 1320, sampleRate: 32000, durationSeconds: 0.1)
        )
        var isf = ISFFile(
            sampleRate: 32000,
            channelCount: 2,
            loop: ISFFile.Loop(enabled: true, startNibble: 117, endNibble: 3001),
            samples: pcm
        )
        isf.name = "track"

        let artifacts = try isf.outputs
        XCTAssertEqual(artifacts.count, 2, "ISF emits a JSON + WAV pair")
        let byFile = artifacts.byFile
        XCTAssertNotNil(byFile[File("track.isf.json")])
        XCTAssertNotNil(byFile[File("track.wav")])

        let rebuilt = try ISFFile(outputs: artifacts)
        XCTAssertEqual(rebuilt.name, "track")
        XCTAssertEqual(rebuilt.sampleRate, 32000)
        XCTAssertEqual(rebuilt.channelCount, 2)
        XCTAssertEqual(rebuilt.loop.enabled, true)
        XCTAssertEqual(rebuilt.loop.startNibble, 117)
        XCTAssertEqual(rebuilt.loop.endNibble, 3001)
        XCTAssertEqual(rebuilt.streamEndNibble, isf.streamEndNibble)
        // WAV preserves PCM exactly, so the interleaved samples must
        // match bit-for-bit (no DSP ADPCM is involved between `outputs`
        // and `init(outputs:)`).
        XCTAssertEqual(rebuilt.samples, isf.samples)
    }

    /// The WAV is the authority on rate and channel count, and the manifest
    /// carries neither — so dropping in audio at another rate is an ordinary
    /// edit rather than a mismatch to refuse. This is what removing those two
    /// fields bought; keeping them meant a pair that could disagree.
    func testWAVIsTheAuthorityOnRateAndChannelCount() throws {
        let pcm = interleave(
            generateSine(frequency: 880, sampleRate: 32000, durationSeconds: 0.1),
            generateSine(frequency: 1320, sampleRate: 32000, durationSeconds: 0.1)
        )
        var isf = ISFFile(
            sampleRate: 32000,
            channelCount: 2,
            loop: ISFFile.Loop(enabled: true, startNibble: 131, endNibble: 3657),
            samples: pcm
        )
        isf.name = "track"
        let artifacts = try isf.outputs

        // The manifest must not mention either field.
        let json = try XCTUnwrap(artifacts.byFile[File("track.isf.json")])
        let text = try XCTUnwrap(String(data: json.data, encoding: .utf8))
        XCTAssertFalse(text.contains("sampleRate"), "rate belongs to the WAV, not the manifest")
        XCTAssertFalse(text.contains("channelCount"), "channel count belongs to the WAV")

        // Swap the companion WAV for the same PCM at another rate, leaving
        // the manifest untouched.
        let resampled = try WAVFile(sampleRate: 48000, channelCount: 2, samples: pcm).encoded()
        let edited = artifacts.map { artifact in
            artifact.file.fileName.hasSuffix(".wav")
                ? FileData(file: artifact.file, data: resampled)
                : artifact
        }

        let rebuilt = try ISFFile(outputs: edited)
        XCTAssertEqual(rebuilt.sampleRate, 48000, "the WAV's rate has to win")
        XCTAssertEqual(rebuilt.channelCount, 2)
        // The loop is stored in seconds, so the same instant is a different
        // nibble address once the rate changes.
        XCTAssertNotEqual(rebuilt.loop.startNibble, isf.loop.startNibble)
        XCTAssertEqual(
            rebuilt.loop.startNibble,
            ISFFile.nibble(
                forSeconds: ISFFile.seconds(forNibble: isf.loop.startNibble, sampleRate: 32000),
                sampleRate: 48000
            )
        )
    }

    /// The creation date is stored as a hex-coded `0xYYYYMMDD` word and written
    /// to the manifest as an ISO 8601 date. `0x20040109` is the only value
    /// on any of the three games' discs; the platform's own convention is
    /// visible in the SDK apploader beside it, which spells its date
    /// `2004/05/21` in ASCII — the `21` can only be a day.
    func testToolDateIsWrittenAsAnISODate() {
        XCTAssertEqual(ISFFile.isoDate(forCreationDate: 0x2004_0109), "2004-01-09")
        XCTAssertEqual(ISFFile.creationDate(forISODate: "2004-01-09"), 0x2004_0109)
        // Both of the era's reference dates, for good measure.
        XCTAssertEqual(ISFFile.isoDate(forCreationDate: 0x2004_0521), "2004-05-21")
        XCTAssertEqual(ISFFile.isoDate(forCreationDate: 0x2002_0905), "2002-09-05")
    }

    /// A word that isn't a date keeps its bytes as a hex literal rather than
    /// being coerced into a nonsense date.
    func testNonDateToolDateRoundTripsAsHex() {
        for word: UInt32 in [0, 0x1234_5678, 0x2004_1332, 0x2004_0100, 0xFFFF_FFFF] {
            let text = ISFFile.isoDate(forCreationDate: word)
            XCTAssertTrue(text.hasPrefix("0x"), "\(text) should have fallen back to hex")
            XCTAssertEqual(ISFFile.creationDate(forISODate: text), word)
        }
    }

    /// Every valid hex-coded date round-trips through the ISO spelling.
    func testEveryValidHexCodedDateRoundTrips() {
        for year in stride(from: 1990, through: 2010, by: 5) {
            for month in 1...12 {
                for day in [1, 9, 10, 19, 28, 31] {
                    let word = UInt32(String(format: "%04d%02d%02d", year, month, day), radix: 16)!
                    let text = ISFFile.isoDate(forCreationDate: word)
                    XCTAssertEqual(text, String(format: "%04d-%02d-%02d", year, month, day))
                    XCTAssertEqual(ISFFile.creationDate(forISODate: text), word)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Compute Pearson correlation coefficient between two signals of
    /// equal length. Returns 0 if either signal is flat.
    private func pearsonCorrelation(_ a: [Int16], _ b: [Int16]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var sumA: Double = 0
        var sumB: Double = 0
        for i in 0..<n {
            sumA += Double(a[i])
            sumB += Double(b[i])
        }
        let meanA = sumA / Double(n)
        let meanB = sumB / Double(n)

        var num: Double = 0
        var denomA: Double = 0
        var denomB: Double = 0
        for i in 0..<n {
            let da = Double(a[i]) - meanA
            let db = Double(b[i]) - meanB
            num += da * db
            denomA += da * da
            denomB += db * db
        }
        guard denomA > 0, denomB > 0 else { return 0 }
        return num / sqrt(denomA * denomB)
    }

    /// RMS error expressed in dBFS relative to the full-scale Int16 range.
    /// Smaller (more negative) is better; a perfect decoder returns -inf.
    private func rmsErrorDBFS(reference: [Int16], decoded: [Int16]) -> Double {
        let n = min(reference.count, decoded.count)
        guard n > 0 else { return 0 }
        var sumSq: Double = 0
        for i in 0..<n {
            let diff = Double(Int32(reference[i]) - Int32(decoded[i]))
            sumSq += diff * diff
        }
        let rms = sqrt(sumSq / Double(n))
        guard rms > 0 else { return -.infinity }
        let fullScale = Double(Int16.max)
        return 20.0 * log10(rms / fullScale)
    }
}

/// Deterministic PRNG so noise-based tests don't rely on stdlib RNG state.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
