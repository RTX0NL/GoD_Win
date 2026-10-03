//
//  ColoSaveCipher.swift
//
//  Pokémon Colosseum save-slot encryption — direct port of
//  PKHeX's `ColoCrypto.cs`
//  (https://github.com/kwsch/PKHeX/blob/master/PKHeX.Core/Saves/Encryption/ColoCrypto.cs).
//
//  Algorithm (per PKHeX's comment block):
//    Use the 20-byte SHA-1 hash stored in `slot[-20:]` as the seed
//    for an iterative XOR cascade over the body. The "at-rest" key
//    is the bitwise-NOT of the stored hash. For each 20-byte chunk
//    of `slot[0x18..-20]`:
//      Encrypt:  chunk ^= digest;  digest = SHA-1(encrypted chunk)
//      Decrypt:  next = SHA-1(encrypted chunk);  chunk ^= digest;
//                digest = next
//    Symmetric: encrypt(decrypt(x)) == x and decrypt(encrypt(x)) == x.
//
//  Header checksum (`SetChecksums`): clear `slot[0x0C..0x10]`, hash
//  the whole `slot[0..-40]` payload into `slot[-20:]`, then write a
//  4-byte header digest into `slot[0x0C..0x10]` computed by
//  subtracting eight u32 BE words from `slot[0..0x18]` (with
//  `slot[0x18..0x20]` XOR-ed against the freshly-computed payload
//  hash).
//
//  Slot layout (all big-endian, post-decrypt view):
//      0x00..0x04   magic (4 bytes)            — plaintext
//      0x04..0x08   save counter (u32 BE)      — plaintext
//      0x08..0x0C   ???                        — plaintext
//      0x0C..0x10   header checksum (i32 BE)   — plaintext
//      0x10..0x14   ???                        — plaintext
//      0x14..0x18   payload size (u32 BE)?     — plaintext
//      0x18..0x20   first encrypted chunk (also XOR-mixed into
//                   header checksum). Encrypted with the at-rest key.
//      0x20..-40    encrypted body (XOR cascade)
//      -40..-20     unused / second hash slot
//      -20..end     SHA-1 payload hash (key seed for the cipher)
//

import Foundation
import GoDFoundation

public enum ColoSaveCipher {

    /// PKHeX `ColoCrypto.SLOT_SIZE`. Each Colo save slot is 0x1E000
    /// bytes (NOT the 0x28000 that XD uses).
    public static let slotSize: Int = 0x1E000

    public static let digestSize: Int = 20

    /// First byte of the encrypted region. Matches PKHeX's
    /// `data[0x18..^sha1HashSize]`.
    public static let cipherStart: Int = 0x18

    /// Header checksum lives at `slot[0x0C..0x10]` as a signed BE u32.
    public static let headerChecksumOffset: Int = 0x0C

    /// Encrypts a slot in place. Computes the SHA-1 payload hash,
    /// writes header checksums, then runs the XOR cascade.
    public static func encrypt(slot: GoDData) throws {
        var bytes = slot.rawBytes
        guard bytes.count == slotSize else {
            throw ColoSaveCipherError.invalidSlotSize(expected: slotSize, actual: bytes.count)
        }

        setChecksums(&bytes)
        runCipher(&bytes, direction: .encrypt)

        slot.write(GoDData(byteStream: bytes, byteOrder: .big), atAddress: 0)
    }

    /// Decrypts a slot in place. Returns `(headerValid, bodyValid)`
    /// — same shape as PKHeX's `IsChecksumValid`.
    @discardableResult
    public static func decrypt(slot: GoDData) throws -> (headerValid: Bool, bodyValid: Bool) {
        var bytes = slot.rawBytes
        guard bytes.count == slotSize else {
            throw ColoSaveCipherError.invalidSlotSize(expected: slotSize, actual: bytes.count)
        }

        runCipher(&bytes, direction: .decrypt)
        let result = isChecksumValid(bytes)

        slot.write(GoDData(byteStream: bytes, byteOrder: .big), atAddress: 0)
        return result
    }

    // MARK: - Cipher core

    private enum Direction { case encrypt, decrypt }

    private static func runCipher(_ bytes: inout [UInt8], direction: Direction) {
        // The "at-rest" key is the bitwise-NOT of the stored hash at
        // slot[-20:]. PKHeX inverts in-place into a stack copy; we do
        // the same so we don't mutate the slot's stored hash.
        var digest = [UInt8](repeating: 0, count: digestSize)
        let hashStart = bytes.count - digestSize
        for i in 0..<digestSize {
            digest[i] = ~bytes[hashStart + i]
        }

        // Range covered by the cascade: slot[0x18..hashStart].
        var i = cipherStart
        while i + digestSize <= hashStart {
            switch direction {
            case .encrypt:
                for j in 0..<digestSize { bytes[i + j] ^= digest[j] }
                let chunk = Array(bytes[i..<(i + digestSize)])
                digest = SHA1.hash(chunk)
            case .decrypt:
                // Hash the ciphertext FIRST (saved for next loop),
                // then XOR with current digest to recover plaintext.
                let chunk = Array(bytes[i..<(i + digestSize)])
                let next = SHA1.hash(chunk)
                for j in 0..<digestSize { bytes[i + j] ^= digest[j] }
                digest = next
            }
            i += digestSize
        }
        // PKHeX comment: the last `(payloadLength % 20)` bytes —
        // 0x10 trailing bytes between the cascade end and the stored
        // hash — aren't part of the loop and are left untouched here
        // too. (`while span.Length >= sha1HashSize`).
    }

    // MARK: - Checksums

    /// Mirrors `ColoCrypto.SetChecksums`. Mutates `bytes` to:
    ///   1. clear the 4-byte header checksum at slot[0x0C..0x10]
    ///   2. write the SHA-1 of slot[0..-40] into slot[-20:]
    ///   3. compute and write the new header checksum into slot[0x0C].
    public static func setChecksums(_ bytes: inout [UInt8]) {
        for off in headerChecksumOffset..<(headerChecksumOffset + 4) {
            bytes[off] = 0
        }

        // Compute SHA-1 of payload (everything except the trailing
        // 40 bytes — 20 hash slot + 20 unused/secondary slot).
        let payloadEnd = bytes.count - (2 * digestSize)
        let payloadHash = SHA1.hash(Array(bytes[0..<payloadEnd]))

        let hashStart = bytes.count - digestSize
        for j in 0..<digestSize {
            bytes[hashStart + j] = payloadHash[j]
        }

        let header = Array(bytes[0..<0x20])
        let newHC = computeHeaderChecksum(header: header, hash: payloadHash)
        writeI32BE(newHC, into: &bytes, at: headerChecksumOffset)
    }

    /// Returns `(headerValid, bodyValid)` without mutating the slot.
    public static func isChecksumValid(_ bytes: [UInt8]) -> (headerValid: Bool, bodyValid: Bool) {
        var working = bytes
        let oldHC = readI32BE(working, at: headerChecksumOffset)
        for off in headerChecksumOffset..<(headerChecksumOffset + 4) {
            working[off] = 0
        }
        let payloadEnd = working.count - (2 * digestSize)
        let currentHash = SHA1.hash(Array(working[0..<payloadEnd]))
        let header = Array(working[0..<0x20])
        let newHC = computeHeaderChecksum(header: header, hash: currentHash)

        let storedHash = Array(bytes[(bytes.count - digestSize)..<bytes.count])
        return (
            headerValid: newHC == oldHC,
            bodyValid: storedHash == currentHash
        )
    }

    /// Mirrors `ColoCrypto.ComputeHeaderChecksum`. Header is the first
    /// 0x20 bytes of the slot; hash is the (newly computed) SHA-1 of
    /// the payload. Returns a signed Int32, written BE into the slot.
    private static func computeHeaderChecksum(header: [UInt8], hash: [UInt8]) -> Int32 {
        var result: Int32 = 0
        // result -= word[i] for i in 0,4,8,12,16,20 (six words from
        // slot[0..0x18])
        var i = 0
        while i < 0x18 {
            result = result &- readI32BE(header, at: i)
            i += 4
        }
        // The remaining two words at slot[0x18..0x20] are XOR-ed
        // against ~hash[0..8] before being subtracted.
        let h0 = readI32BE(hash, at: 0)
        let h4 = readI32BE(hash, at: 4)
        let w0 = readI32BE(header, at: 0x18)
        let w1 = readI32BE(header, at: 0x1C)
        result = result &- (w0 ^ ~h0)
        result = result &- (w1 ^ ~h4)
        return result
    }

    @inline(__always)
    private static func readI32BE(_ bytes: [UInt8], at offset: Int) -> Int32 {
        let u: UInt32 = (UInt32(bytes[offset])     << 24)
                      | (UInt32(bytes[offset + 1]) << 16)
                      | (UInt32(bytes[offset + 2]) << 8)
                      |  UInt32(bytes[offset + 3])
        return Int32(bitPattern: u)
    }

    @inline(__always)
    private static func writeI32BE(_ value: Int32, into bytes: inout [UInt8], at offset: Int) {
        let u = UInt32(bitPattern: value)
        bytes[offset]     = UInt8((u >> 24) & 0xFF)
        bytes[offset + 1] = UInt8((u >> 16) & 0xFF)
        bytes[offset + 2] = UInt8((u >> 8) & 0xFF)
        bytes[offset + 3] = UInt8(u & 0xFF)
    }
}

public enum ColoSaveCipherError: Error, CustomStringConvertible {
    case invalidSlotSize(expected: Int, actual: Int)

    public var description: String {
        switch self {
        case let .invalidSlotSize(expected, actual):
            return "ColoSaveCipher: slot size \(actual) does not match expected \(expected) (0x1E000)"
        }
    }
}
