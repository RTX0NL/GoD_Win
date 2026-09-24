//
//  XDSaveCipher.swift
//
//  Pokémon XD save-slot cipher — Genius Sonority's additive
//  4-key stream cipher with diagonal nibble-rotation key advance.
//
//  Cross-checked against PKHeX (`GeniusCrypto.cs` + `XDCrypto.cs`,
//  https://github.com/kwsch/PKHeX/blob/master/PKHeX.Core/Saves/Encryption/),
//  which is the production-validated reference. The earlier port
//  done from `_memcard_{En,De}cryption__FPv.s` directly had two
//  layout errors that PKHeX corrected:
//    - Cipher region is `slot[0x10..0x27FD8]`, not `[0x08..0x27FD0]`.
//    - Keys live at `slot[0x08..0x10]` (separate plaintext field),
//      not derived from `slot[0..7]` (which is the 8-byte slot
//      header — magic + counter — and is *not* loaded into the
//      cipher state at function entry).
//  See `Documentation/File Formats/XD/XD Save Encryption.md` for the
//  long-form notes.
//
//  Self-inverse + tag-corruption tests live in
//  `Tests/Shared Tests/Engine Tests/XD Tests/XDSaveCipherTests.swift`.
//

import Foundation
import GoDFoundation

public enum XDSaveCipher {

    /// PKHeX's `GeniusCrypto.AdvanceKeys` — see the diagonal-rotation
    /// comment in that file. We use the same constants verbatim.
    public static let sboxBias: [UInt32] = [0x43, 0x29, 0x17, 0x13]

    public static let slotSize: Int = 0x28000

    /// Plaintext key seed (4 × u16 BE).
    public static let keyRange: Range<Int> = 0x08..<0x10
    /// Encrypted region — cipher loop covers exactly this range.
    public static let cipherRange: Range<Int> = 0x10..<0x27FD8
    /// Body checksum tag region — 4 × u32 stored as 8 × u16 BE inside
    /// `cipherRange`, in the disasm's quirky reversed order.
    public static let checksumRange: Range<Int> = 0x10..<0x20
    /// Byte length of the tag region, wherever it sits.
    public static let checksumLength: Int = checksumRange.count

    /// The tag region for a given offset, or `nil` when the save format
    /// has no checksum and none should be written.
    public static func checksumRegion(at offset: Int?) -> Range<Int>? {
        guard let offset else { return nil }
        return offset..<(offset + checksumLength)
    }
    /// Lane stride for the body checksum: 4 × `0x9FF4` halfword sums,
    /// each lane covering one quarter of `slot[0x08..0x27FD8)`.
    public static let checksumLaneSpan: Int = 0x9FF4
    /// Inclusive start of the body-checksum coverage range. Covers the
    /// 8 plaintext key-region bytes at the start *and* the cipher
    /// region, mirroring PKHeX's `int dt = 8`.
    public static let checksumCoverageStart: Int = 0x08

    public static let isAvailable: Bool = true

    // MARK: - Public API

    /// Encrypts a 0x28000-byte XD slot in place. Pipeline matches
    /// `XDCrypto.SetChecksums` + `EncryptSlot`:
    ///   1. Clear `slot[0x10..0x20]` (the saved-tag region).
    ///   2. Compute four lane sums over `slot[0x08..0x27FD8)`.
    ///   3. Write the sums back into `slot[0x10..0x20]` in PKHeX's
    ///      reversed order.
    ///   4. Encrypt `slot[0x10..0x27FD8)` using the keys at
    ///      `slot[0x08..0x10]`.
    public static func encrypt(slot: GoDData, checksumOffset: Int? = XDSaveSlot.checksumOffset) throws {
        var bytes = slot.rawBytes
        guard bytes.count >= slotSize else {
            throw XDSaveCipherError.slotTooShort(minimum: slotSize, actual: bytes.count)
        }

        // A `nil` offset means this save format has no checksum, so the
        // slot is encrypted as-is rather than having four sums written
        // at a guessed position.
        if let region = checksumRegion(at: checksumOffset) {
            try validate(region: region, in: bytes)
            clearChecksumRegion(&bytes, region)
            let sums = computeChecksum(&bytes)
            writeChecksum(&bytes, sums: sums, region)
        }
        cipherLoop(&bytes, direction: .encrypt)

        slot.write(GoDData(byteStream: bytes, byteOrder: .big), atAddress: 0)
    }

    /// Decrypts in place and returns `true` iff the four recomputed
    /// body sums match the saved tags, or `nil` when the save format
    /// declares no checksum and there was nothing to check. Pipeline
    /// matches `XDCrypto.DecryptSlot` + the `IsChecksumValid` body-tag
    /// check.
    @discardableResult
    public static func decrypt(slot: GoDData, checksumOffset: Int? = XDSaveSlot.checksumOffset) throws -> Bool? {
        var bytes = slot.rawBytes
        guard bytes.count >= slotSize else {
            throw XDSaveCipherError.slotTooShort(minimum: slotSize, actual: bytes.count)
        }

        cipherLoop(&bytes, direction: .decrypt)
        guard let region = checksumRegion(at: checksumOffset) else {
            // No checksum in this format: hand back the plaintext and
            // report "not checked" rather than a pass or a failure.
            slot.write(GoDData(byteStream: bytes, byteOrder: .big), atAddress: 0)
            return nil
        }
        try validate(region: region, in: bytes)
        let saved = readChecksum(bytes, region)
        clearChecksumRegion(&bytes, region)
        let recomputed = computeChecksum(&bytes)

        slot.write(GoDData(byteStream: bytes, byteOrder: .big), atAddress: 0)
        return saved == recomputed
    }

    // MARK: - Cipher loop

    private enum Direction { case encrypt, decrypt }

    private static func cipherLoop(_ bytes: inout [UInt8], direction: Direction) {
        // Load 4 × u16 BE keys from the plaintext key region.
        var keys: [UInt16] = (0..<4).map { i in
            (UInt16(bytes[keyRange.lowerBound + i * 2]) << 8)
                | UInt16(bytes[keyRange.lowerBound + i * 2 + 1])
        }

        var i = cipherRange.lowerBound
        while i < cipherRange.upperBound {
            for j in 0..<4 {
                let off = i + j * 2
                let cipherWord: UInt16 = (UInt16(bytes[off]) << 8)
                    | UInt16(bytes[off + 1])
                let updated: UInt16
                switch direction {
                case .encrypt: updated = cipherWord &+ keys[j]
                case .decrypt: updated = cipherWord &- keys[j]
                }
                bytes[off]     = UInt8((updated >> 8) & 0xFF)
                bytes[off + 1] = UInt8(updated & 0xFF)
            }
            advanceKeys(&keys)
            i += 8
        }
    }

    /// Diagonal nibble-rotation advance. Direct port of PKHeX's
    /// `GeniusCrypto.AdvanceKeys` — same constants, same shuffle
    /// pattern. Each `k_i = key[i] + sboxBias[i]` (32-bit add to avoid
    /// the u16 overflow that the original PPC code carefully sidesteps
    /// via the rotated/masked u32 paths), then the four nibble lanes
    /// of each `k_i` are scattered across the four new key halfwords:
    ///
    ///     newKey[3] high nibble ← k3 high nibble   (etc. on the diag)
    ///     newKey[3] mid-hi    ← k2 mid-hi          (down-left)
    ///     newKey[3] mid-lo    ← k1 mid-lo
    ///     newKey[3] low       ← k0 low
    ///
    /// Equivalent to a 4×4 nibble matrix transposed across the
    /// trailing diagonal.
    private static func advanceKeys(_ keys: inout [UInt16]) {
        let k0: UInt32 = UInt32(keys[0]) &+ sboxBias[0]
        let k1: UInt32 = UInt32(keys[1]) &+ sboxBias[1]
        let k2: UInt32 = UInt32(keys[2]) &+ sboxBias[2]
        let k3: UInt32 = UInt32(keys[3]) &+ sboxBias[3]

        keys[3] = UInt16(truncatingIfNeeded:
            ((k0 >> 12) & 0x000F)
            | ((k1 >> 8) & 0x00F0)
            | ((k2 >> 4) & 0x0F00)
            | ( k3       & 0xF000))
        keys[2] = UInt16(truncatingIfNeeded:
            ((k0 >> 8)  & 0x000F)
            | ((k1 >> 4) & 0x00F0)
            | ( k2       & 0x0F00)
            | ((k3 << 4) & 0xF000))
        keys[1] = UInt16(truncatingIfNeeded:
            ((k0 >> 4)  & 0x000F)
            | ( k1       & 0x00F0)
            | ((k2 << 4) & 0x0F00)
            | ((k3 << 8) & 0xF000))
        keys[0] = UInt16(truncatingIfNeeded:
            ( k0        & 0x000F)
            | ((k1 << 4) & 0x00F0)
            | ((k2 << 8) & 0x0F00)
            | ((k3 << 12) & 0xF000))
    }

    // MARK: - Body checksum

    /// Computes the four lane sums per PKHeX's `XDCrypto.SetChecksums`:
    /// each lane is the BE u16 sum over `0x9FF4` consecutive bytes
    /// starting at `slot[checksumCoverageStart + lane * 0x9FF4]`.
    public static func computeChecksum(_ bytes: inout [UInt8]) -> [UInt32] {
        var sums: [UInt32] = [0, 0, 0, 0]
        var dt = checksumCoverageStart
        for lane in 0..<4 {
            let end = dt + checksumLaneSpan
            var sum: UInt32 = 0
            var j = dt
            while j < end {
                sum = sum &+ ((UInt32(bytes[j]) << 8) | UInt32(bytes[j + 1]))
                j += 2
            }
            sums[lane] = sum
            dt = end
        }
        return sums
    }

    /// Clears `slot[0x10..0x20]` so the checksum loop doesn't include
    /// stale tag bytes — matches `XDCrypto.SetChecksums` line
    /// `data[0x10..0x20].Clear()`.
    private static func clearChecksumRegion(_ bytes: inout [UInt8], _ region: Range<Int>) {
        for i in region { bytes[i] = 0 }
    }

    /// A relocated tag region still has to sit inside the slot and
    /// inside the encrypted range, or the checksum would be written
    /// somewhere the game never reads back.
    private static func validate(region: Range<Int>, in bytes: [UInt8]) throws {
        guard region.lowerBound >= 0, region.upperBound <= bytes.count else {
            throw XDSaveCipherError.checksumRegionOutOfBounds(
                offset: region.lowerBound, length: region.count, slotLength: bytes.count
            )
        }
        guard cipherRange.contains(region.lowerBound),
              region.upperBound <= cipherRange.upperBound else {
            throw XDSaveCipherError.checksumRegionOutsideCipherRange(
                offset: region.lowerBound, length: region.count
            )
        }
    }

    /// Writes the 4 × u32 sums into `slot[0x10..0x20]` using PKHeX's
    /// reversed layout. Each sum becomes two halfwords stored as
    /// `[hi, lo]` pairs, but the lanes themselves are written in
    /// reverse order — so lane 3 lands at `slot[0x10..0x14]`, lane 0
    /// at `slot[0x1C..0x20]`.
    private static func writeChecksum(_ bytes: inout [UInt8], sums: [UInt32], _ region: Range<Int>) {
        // Build the 8-halfword vector in PKHeX's order:
        //   newchks = [hi0, lo0, hi1, lo1, hi2, lo2, hi3, lo3]
        // Then write reversed: dest[i] ← newchks[7 - i].
        var newchks = [UInt16](repeating: 0, count: 8)
        for i in 0..<4 {
            newchks[i * 2]     = UInt16((sums[i] >> 16) & 0xFFFF)
            newchks[i * 2 + 1] = UInt16(sums[i] & 0xFFFF)
        }
        for i in 0..<8 {
            let dest = region.lowerBound + i * 2
            let v = newchks[7 - i]
            bytes[dest]     = UInt8((v >> 8) & 0xFF)
            bytes[dest + 1] = UInt8(v & 0xFF)
        }
    }

    /// Inverse of `writeChecksum`.
    private static func readChecksum(_ bytes: [UInt8], _ region: Range<Int>) -> [UInt32] {
        var newchks = [UInt16](repeating: 0, count: 8)
        for i in 0..<8 {
            let src = region.lowerBound + i * 2
            newchks[7 - i] = (UInt16(bytes[src]) << 8) | UInt16(bytes[src + 1])
        }
        var sums: [UInt32] = [0, 0, 0, 0]
        for i in 0..<4 {
            let hi = UInt32(newchks[i * 2])
            let lo = UInt32(newchks[i * 2 + 1])
            sums[i] = (hi << 16) | lo
        }
        return sums
    }
}

public enum XDSaveCipherError: Error, CustomStringConvertible {
    case slotTooShort(minimum: Int, actual: Int)
    case checksumRegionOutOfBounds(offset: Int, length: Int, slotLength: Int)
    case checksumRegionOutsideCipherRange(offset: Int, length: Int)

    public var description: String {
        switch self {
        case let .slotTooShort(minimum, actual):
            return "XDSaveCipher: slot is \(actual) bytes, shorter than the required \(minimum) (0x28000) cipher range"
        case let .checksumRegionOutOfBounds(offset, length, slotLength):
            return """
                XDSaveCipher: the engine puts the checksum at \(String(format: "%#x", offset)) \
                (\(length) bytes), past the end of a \(slotLength)-byte slot
                """
        case let .checksumRegionOutsideCipherRange(offset, length):
            return """
                XDSaveCipher: the engine puts the checksum at \(String(format: "%#x", offset)) \
                (\(length) bytes), outside the encrypted range \
                \(String(format: "%#x", XDSaveCipher.cipherRange.lowerBound))..<\(String(format: "%#x", XDSaveCipher.cipherRange.upperBound)). \
                The game reads its tags from inside the cipher region, so a tag \
                written outside it would never be checked.
                """
        }
    }
}
