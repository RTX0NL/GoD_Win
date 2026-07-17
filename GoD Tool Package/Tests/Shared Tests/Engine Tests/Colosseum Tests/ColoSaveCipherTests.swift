import XCTest
@testable import Colosseum
@testable import GoDFoundation

/// Internal-consistency tests for `ColoSaveCipher`. Same approach as
/// `XDSaveCipherTests`: covers round-trip symmetry, header checksum,
/// body checksum, and corruption detection. Without a real Colo `.gci`
/// fixture (task #12) we can't prove byte-for-byte compatibility with
/// the actual game's output, but PKHeX's algorithm is the
/// production-validated reference and these tests verify our port is
/// internally consistent with it.
final class ColoSaveCipherTests: XCTestCase {

    private func makePlaintextSlot(seed: UInt64 = 0xABCDEF01_23456789) -> GoDData {
        var bytes = [UInt8](repeating: 0, count: ColoSaveCipher.slotSize)

        // A made-up plaintext slot. The cipher only cares that the
        // header checksum + payload SHA-1 are recomputed by setChecksums
        // before encryption, so any byte pattern in slot[0..end-20] is
        // fine; we just need something non-zero so the cascade
        // diverges visibly.
        bytes[0] = 0x47; bytes[1] = 0x43; bytes[2] = 0x36; bytes[3] = 0x45  // "GC6E"
        // Save counter (BE u32)
        bytes[4] = 0x00; bytes[5] = 0x00; bytes[6] = 0x12; bytes[7] = 0x34
        // Header checksum field (slot[0x0C..0x10]) starts zero — set
        // by setChecksums.
        var rng = seed
        for i in 0x10..<bytes.count {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            bytes[i] = UInt8(truncatingIfNeeded: rng >> 56)
        }
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    func testEncryptDecryptRoundTrip() throws {
        // Need a slot that already has valid checksums before encrypt.
        let plain = makePlaintextSlot()
        var prepBytes = plain.rawBytes
        ColoSaveCipher.setChecksums(&prepBytes)
        let plainPrepared = GoDData(byteStream: prepBytes, byteOrder: .big)
        let originalBytes = plainPrepared.rawBytes

        let working = GoDData(byteStream: originalBytes, byteOrder: .big)
        try ColoSaveCipher.encrypt(slot: working)
        XCTAssertNotEqual(working.rawBytes, originalBytes,
                          "encrypt produced no change")

        let result = try ColoSaveCipher.decrypt(slot: working)
        XCTAssertTrue(result.headerValid, "header checksum invalid after round-trip")
        XCTAssertTrue(result.bodyValid, "body SHA-1 invalid after round-trip")
        XCTAssertEqual(working.rawBytes, originalBytes,
                       "decrypt(encrypt(X)) != X")
    }

    func testCorruptionFailsBodyCheck() throws {
        let plain = makePlaintextSlot()
        var prepBytes = plain.rawBytes
        ColoSaveCipher.setChecksums(&prepBytes)
        let prepared = GoDData(byteStream: prepBytes, byteOrder: .big)

        let working = GoDData(byteStream: prepared.rawBytes, byteOrder: .big)
        try ColoSaveCipher.encrypt(slot: working)

        var corrupted = working.rawBytes
        corrupted[0x1000] ^= 0x01
        let corruptedSlot = GoDData(byteStream: corrupted, byteOrder: .big)

        let result = try ColoSaveCipher.decrypt(slot: corruptedSlot)
        XCTAssertFalse(result.bodyValid,
                       "single-byte corruption in payload should fail SHA-1 check")
    }

    func testHeaderBytesUntouchedByCipher() throws {
        // Cipher region starts at slot[0x18]. The first 0x18 bytes
        // (which include the header checksum) must round-trip through
        // encrypt unchanged.
        let plain = makePlaintextSlot()
        var prepBytes = plain.rawBytes
        ColoSaveCipher.setChecksums(&prepBytes)
        let prepared = GoDData(byteStream: prepBytes, byteOrder: .big)

        let working = GoDData(byteStream: prepared.rawBytes, byteOrder: .big)
        let originalHead = Array(prepared.rawBytes.prefix(0x18))
        try ColoSaveCipher.encrypt(slot: working)
        XCTAssertEqual(Array(working.rawBytes.prefix(0x18)), originalHead,
                       "encrypt should not touch slot[0..0x18)")
    }

    func testDeterminism() throws {
        // Same plaintext + same setChecksums = same ciphertext.
        let plainA = makePlaintextSlot()
        var bytesA = plainA.rawBytes
        ColoSaveCipher.setChecksums(&bytesA)
        let a = GoDData(byteStream: bytesA, byteOrder: .big)

        let plainB = makePlaintextSlot()
        var bytesB = plainB.rawBytes
        ColoSaveCipher.setChecksums(&bytesB)
        let b = GoDData(byteStream: bytesB, byteOrder: .big)

        try ColoSaveCipher.encrypt(slot: a)
        try ColoSaveCipher.encrypt(slot: b)
        XCTAssertEqual(a.rawBytes, b.rawBytes)
    }

    func testKeySensitivity() throws {
        // Two slots that differ by one byte in the payload should
        // produce different stored hashes after setChecksums, and
        // therefore different ciphertexts after encrypt.
        let plain = makePlaintextSlot()
        var bytesA = plain.rawBytes
        var bytesB = plain.rawBytes
        bytesB[0x500] ^= 0x01
        ColoSaveCipher.setChecksums(&bytesA)
        ColoSaveCipher.setChecksums(&bytesB)

        let a = GoDData(byteStream: bytesA, byteOrder: .big)
        let b = GoDData(byteStream: bytesB, byteOrder: .big)
        try ColoSaveCipher.encrypt(slot: a)
        try ColoSaveCipher.encrypt(slot: b)

        XCTAssertNotEqual(a.rawBytes, b.rawBytes,
                          "payload change should propagate to ciphertext")
    }
}
