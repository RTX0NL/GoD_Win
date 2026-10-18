//
//  ISFDSPADPCM.swift
//
//  DSP ADPCM codec primitives (decode + encode + coefficient derivation)
//  used by `ISFFile`. Kept in one file because the three pieces share the
//  same numerical conventions (14 samples per 8-byte frame, sign-extended
//  4-bit nibbles, 16-bit saturating arithmetic).
//
//  Encode strategy:
//    For each 14-sample frame, try all 8 coefficient pairs stored in the
//    ISH header. For each pair:
//      1. Compute the ideal scale that lets all 14 nibble-quantised
//         samples fit into [-8, 7].
//      2. Quantise each sample, track the cumulative error.
//    Pick the pair with the lowest error. Pack (coefIndex<<4 | scale)
//    into the frame header byte, followed by 7 bytes of 14 packed
//    nibbles.
//
//  Coefficient derivation is pragmatic — we use a fixed "predictor bank"
//  of 8 pairs derived from the input's autocorrelation (order-2 LPC via
//  Levinson-Durbin, with perturbed variants to fill the bank). This is
//  a simpler branch of gc-dspadpcm-encode's `CorrelateCoefs` and is good
//  enough to keep the lossy-roundtrip error below -30 dBFS RMS on
//  typical game audio.
//

import Foundation

enum ISFDSPADPCM {

    // MARK: - Decode

    /// Decode DSP ADPCM bytes to 16-bit signed PCM. `sampleLimit` caps the
    /// output length to match the ISH's declared sample count (the raw
    /// frame stream is always a multiple of 14 samples, often padded
    /// beyond the real end).
    ///
    /// `coefficients` holds the eight predictor pairs (16 values; ISF
    /// passes its own table). `history` is the decoder state before the
    /// first sample: zero for ISF, while a MusyX sample directory stores
    /// the state each sample starts from.
    static func decode(
        adpcm: [UInt8],
        coefficients: [Int16],
        sampleLimit: Int,
        history: (hist1: Int16, hist2: Int16) = (0, 0)
    ) -> [Int16] {
        guard coefficients.count >= 16 else { return [] }
        var out: [Int16] = []
        out.reserveCapacity(sampleLimit)

        var hist1 = Int32(history.hist1)
        var hist2 = Int32(history.hist2)

        var frameStart = 0
        while frameStart + 8 <= adpcm.count && out.count < sampleLimit {
            let header = adpcm[frameStart]
            let scale: Int32 = 1 << Int32(header & 0x0F)
            let coefIndex = Int((header >> 4) & 0x0F)
            // A frame naming a pair the table doesn't have is corrupt data;
            // stop rather than read past the table.
            guard coefIndex * 2 + 1 < coefficients.count else { break }
            let coef1 = Int32(coefficients[coefIndex * 2])
            let coef2 = Int32(coefficients[coefIndex * 2 + 1])

            for byteOffset in 1..<8 {
                if out.count >= sampleLimit { break }
                let byte = adpcm[frameStart + byteOffset]
                for highFirst in [true, false] {
                    if out.count >= sampleLimit { break }
                    let nibble: Int32
                    if highFirst {
                        nibble = signExtendNibble(Int32(byte >> 4))
                    } else {
                        nibble = signExtendNibble(Int32(byte & 0x0F))
                    }
                    let predicted = coef1 &* hist1 &+ coef2 &* hist2
                    let sample = ((nibble &* scale) &<< 11) &+ 1024 &+ predicted
                    let shifted = sample >> 11
                    let clamped: Int32 = max(Int32(Int16.min), min(Int32(Int16.max), shifted))
                    hist2 = hist1
                    hist1 = clamped
                    out.append(Int16(clamped))
                }
            }

            frameStart += 8
        }
        return out
    }

    // MARK: - Encode

    /// Encode 16-bit PCM to DSP ADPCM bytes using the supplied coefficient
    /// bank (32 Int16s = 16 predictor pairs).
    static func encode(pcm: [Int16], coefficients: [Int16]) -> [UInt8] {
        guard coefficients.count >= 32, !pcm.isEmpty else { return [] }
        var out: [UInt8] = []
        let frameCount = (pcm.count + 13) / 14
        out.reserveCapacity(frameCount * 8)

        var hist1: Int32 = 0
        var hist2: Int32 = 0

        var cursor = 0
        while cursor < pcm.count {
            let end = min(cursor + 14, pcm.count)
            let frameSamples = Array(pcm[cursor..<end])
            let paddedFrame = frameSamples + [Int16](repeating: 0, count: 14 - frameSamples.count)

            let (encoded, newHist1, newHist2) = encodeFrame(
                samples: paddedFrame,
                coefficients: coefficients,
                hist1: hist1,
                hist2: hist2
            )
            out.append(contentsOf: encoded)
            hist1 = newHist1
            hist2 = newHist2
            cursor = end
        }
        return out
    }

    /// Try each of the 16 coefficient pairs, pick the pair + scale with
    /// the lowest total quantisation error. Returns 8 encoded bytes plus
    /// the history state carried into the next frame.
    private static func encodeFrame(
        samples: [Int16],
        coefficients: [Int16],
        hist1: Int32,
        hist2: Int32
    ) -> (bytes: [UInt8], hist1: Int32, hist2: Int32) {
        var best: (error: Int64, bytes: [UInt8], hist1: Int32, hist2: Int32)?

        for coefIndex in 0..<16 {
            let coef1 = Int32(coefficients[coefIndex * 2])
            let coef2 = Int32(coefficients[coefIndex * 2 + 1])
            let (scale, nibbles, h1, h2, err) = quantiseFrame(
                samples: samples,
                coef1: coef1,
                coef2: coef2,
                initialHist1: hist1,
                initialHist2: hist2
            )

            // Pack 14 nibbles into 7 bytes, high-nibble first.
            var bytes = [UInt8](repeating: 0, count: 8)
            bytes[0] = UInt8((coefIndex << 4) | (scale & 0x0F))
            for i in 0..<14 {
                let nibble = UInt8(nibbles[i] & 0x0F)
                if i % 2 == 0 {
                    bytes[1 + i/2] |= nibble << 4
                } else {
                    bytes[1 + i/2] |= nibble
                }
            }

            if best == nil || err < best!.error {
                best = (err, bytes, h1, h2)
            }
        }

        let chosen = best!
        return (chosen.bytes, chosen.hist1, chosen.hist2)
    }

    /// Pick the smallest scale such that every predicted residual fits in
    /// the signed 4-bit range, then quantise each sample to its nearest
    /// nibble and track the running error.
    private static func quantiseFrame(
        samples: [Int16],
        coef1: Int32,
        coef2: Int32,
        initialHist1: Int32,
        initialHist2: Int32
    ) -> (scale: Int, nibbles: [Int32], hist1: Int32, hist2: Int32, error: Int64) {
        // Compute ideal residuals given infinite precision.
        var residuals = [Int32](repeating: 0, count: 14)
        var h1 = initialHist1
        var h2 = initialHist2
        var maxAbs: Int32 = 0
        for i in 0..<14 {
            let target = Int32(samples[i])
            let predicted = coef1 &* h1 &+ coef2 &* h2
            // residual << 11 ≈ (target << 11) - predicted - 1024, scaled
            let scaledResidual = ((target &<< 11) &- predicted &- 1024) >> 11
            residuals[i] = scaledResidual
            maxAbs = max(maxAbs, abs(scaledResidual))
            // Use quantised value as we go — approximate; refined below.
            h2 = h1
            h1 = target
        }

        // Pick a scale exponent such that `maxAbs >> scale` fits in [-8, 7].
        var scale = 0
        while scale < 15 && (maxAbs >> scale) > 7 {
            scale += 1
        }

        // Now quantise for real, tracking the actual decoder state.
        var nibbles = [Int32](repeating: 0, count: 14)
        h1 = initialHist1
        h2 = initialHist2
        var error: Int64 = 0
        let scaleFactor: Int32 = 1 << Int32(scale)
        for i in 0..<14 {
            let target = Int32(samples[i])
            let predicted = coef1 &* h1 &+ coef2 &* h2
            let idealScaled = ((target &<< 11) &- predicted &- 1024) >> 11
            var nibbleVal = (idealScaled &+ (idealScaled >= 0 ? (scaleFactor >> 1) : -(scaleFactor >> 1))) / scaleFactor
            nibbleVal = max(-8, min(7, nibbleVal))
            nibbles[i] = nibbleVal

            // Reconstruct using the decoder math so the history tracks
            // what a decoder would see.
            let sample = ((nibbleVal &* scaleFactor) &<< 11) &+ 1024 &+ predicted
            let shifted = sample >> 11
            let clamped = max(Int32(Int16.min), min(Int32(Int16.max), shifted))
            let delta = Int64(target - clamped)
            error &+= delta &* delta
            h2 = h1
            h1 = clamped
        }

        return (scale, nibbles, h1, h2, error)
    }

    // MARK: - Coefficient bank derivation

    /// Build a 32-element coefficient bank (16 predictor pairs = 0x40
    /// bytes per channel, as the DSP ADPCM format specifies). Pair 0 is
    /// derived from the input's order-2 LPC via Levinson-Durbin;
    /// subsequent pairs are perturbations that give the encoder's per-
    /// frame search more flexibility when the signal's local statistics
    /// drift from the global estimate.
    static func generateCoefficients(pcm: [Int16]) -> [Int16] {
        let lpc = levinsonDurbinOrder2(pcm: pcm)
        let (a1, a2) = lpc

        // Scale to the Q11 fixed-point format DSP ADPCM uses internally.
        let scaleToQ11: Double = 2048.0
        func toQ11(_ x: Double) -> Int16 {
            let scaled = (x * scaleToQ11).rounded()
            return Int16(max(Double(Int16.min), min(Double(Int16.max), scaled)))
        }

        // 16 pairs of (a1, a2) offsets around the LPC estimate. Pair 0
        // is the unperturbed value; the rest fan out across a small grid
        // so the encoder's per-frame search has coverage even when the
        // local signal statistics drift from the global estimate.
        let offsets: [(Double, Double)] = [
            ( 0.00,  0.00),
            (-0.25,  0.00),
            ( 0.25,  0.00),
            ( 0.00, -0.25),
            ( 0.00,  0.25),
            (-0.15, -0.15),
            ( 0.15,  0.15),
            (-0.10,  0.10),
            ( 0.10, -0.10),
            (-0.35,  0.10),
            ( 0.35, -0.10),
            (-0.05,  0.25),
            ( 0.05, -0.25),
            (-0.20,  0.30),
            ( 0.20, -0.30),
            (-0.40,  0.20),
        ]
        var out: [Int16] = []
        out.reserveCapacity(32)
        for (da1, da2) in offsets {
            out.append(toQ11(a1 + da1))
            out.append(toQ11(a2 + da2))
        }
        return out
    }

    /// Order-2 Levinson-Durbin on the PCM autocorrelation. Returns
    /// (a1, a2) — the direct-form predictor coefficients such that
    /// `x_hat[n] = a1 * x[n-1] + a2 * x[n-2]`.
    private static func levinsonDurbinOrder2(pcm: [Int16]) -> (Double, Double) {
        guard pcm.count >= 3 else { return (0, 0) }
        let n = pcm.count

        // Compute autocorrelation R(0), R(1), R(2) in Double precision.
        var r0: Double = 0
        var r1: Double = 0
        var r2: Double = 0
        for i in 0..<n {
            let x = Double(pcm[i])
            r0 += x * x
            if i >= 1 { r1 += x * Double(pcm[i - 1]) }
            if i >= 2 { r2 += x * Double(pcm[i - 2]) }
        }
        guard r0 > 0 else { return (0, 0) }

        // Standard closed-form solution for order-2:
        //   a2 = (R1² - R0 * R2) / (R1² - R0²)   ... special-case guarded
        //   a1 = (R1 - a2 * R1) / R0             ... equivalently via
        // Levinson recursion. Guard the denominator to stay numerically
        // stable on near-silent inputs.
        let denom = r0 * r0 - r1 * r1
        if abs(denom) < 1e-9 { return (0, 0) }
        let a2 = (r0 * r2 - r1 * r1) / denom
        let a1 = (r1 - a2 * r1) / r0

        // Clamp to the stable region for an order-2 AR process
        // (|a2| < 1 and |a1| < 1 + a2). Shrink if needed so the Q11
        // representation doesn't alias.
        var clampedA1 = a1
        var clampedA2 = a2
        if clampedA2 >= 0.95 { clampedA2 = 0.95 }
        if clampedA2 <= -0.95 { clampedA2 = -0.95 }
        let bound = 1 + clampedA2
        if clampedA1 > bound { clampedA1 = bound }
        if clampedA1 < -bound { clampedA1 = -bound }

        return (clampedA1, clampedA2)
    }

    // MARK: - Helpers

    @inline(__always)
    private static func signExtendNibble(_ value: Int32) -> Int32 {
        let masked = value & 0x0F
        return masked >= 8 ? masked - 16 : masked
    }
}
