import XCTest
@testable import XD
@testable import GoDFoundation

/// Internal-consistency tests for `XDSaveCipher`.
///
/// We don't yet have a real Pokémon XD `.gci` fixture in the repo
/// (task #12), so these tests don't validate bit-for-bit
/// compatibility with the original game's output. What they DO catch
/// is any port-level error that breaks the cipher's symmetry: a
/// wrong PPC mask, a swapped operand, an off-by-one in the loop
/// bounds, etc. — anything that would prevent decrypt(encrypt(X))
/// from recovering X exactly.
final class XDSaveCipherTests: XCTestCase {

    /// Build a synthetic 0x28000-byte slot. Bytes 0..7 are the
    /// plaintext header / key seed; bytes 8.. are pseudo-random
    /// "payload" so any drift through the cipher shows up.
    private func makePlaintextSlot(seed: UInt64 = 0xC0FFEE00_BEEFCAFE) -> GoDData {
        var bytes = [UInt8](repeating: 0, count: XDSaveSlot.slotSize)
        // Plaintext slot header — magic + reserved + counter. Not
        // touched by the cipher (which starts at slot[0x10]); they're
        // here so XDSaveSlot can still parse them.
        bytes[0x00] = 0x01; bytes[0x01] = 0x01; bytes[0x02] = 0x01
        bytes[0x03] = 0x00
        bytes[0x04] = 0xDE; bytes[0x05] = 0xAD; bytes[0x06] = 0xBE; bytes[0x07] = 0xEF

        // Cipher keys at slot[0x08..0x10] — also plaintext, and form
        // the per-save key seed for the additive cipher.
        bytes[0x08] = 0xCA; bytes[0x09] = 0xFE
        bytes[0x0A] = 0xBA; bytes[0x0B] = 0xBE
        bytes[0x0C] = 0xF0; bytes[0x0D] = 0x0D
        bytes[0x0E] = 0xFA; bytes[0x0F] = 0xCE

        // slot[0x10..0x20] is the body-checksum region — encrypt
        // writes sums there, decrypt zeros them after reading. Any
        // valid plaintext has zeros there. Fill the rest of the
        // payload deterministically.
        var rng = seed
        for i in 0x20..<bytes.count {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            bytes[i] = UInt8(truncatingIfNeeded: rng >> 56)
        }
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    func testEncryptDecryptRoundTrip() throws {
        let original = makePlaintextSlot()
        let originalBytes = original.rawBytes

        let working = GoDData(byteStream: originalBytes, byteOrder: .big)
        try XDSaveCipher.encrypt(slot: working)

        // Encryption must change the bytes (or our cipher is a no-op).
        XCTAssertNotEqual(working.rawBytes, originalBytes,
                          "encrypt produced no change")

        let ok = try XDSaveCipher.decrypt(slot: working)
        XCTAssertTrue(ok, "decrypt running-sum tags did not match")

        // The cipher only touches slot[0x08..0x27FD0); the tail bytes
        // [0x27FD0..0x28000) are not in the loop's range, so the
        // round-trip should leave them untouched. Either way, the
        // whole slot should equal the original.
        XCTAssertEqual(working.rawBytes, originalBytes,
                       "decrypt(encrypt(X)) != X")
    }

    func testCipherChangesPayloadBytes() throws {
        // Sanity-check that encryption isn't a no-op for a region we
        // know it covers — the byte at slot[0x100] should change.
        let original = makePlaintextSlot()
        let workingBytes = original.rawBytes
        let working = GoDData(byteStream: workingBytes, byteOrder: .big)
        try XDSaveCipher.encrypt(slot: working)
        XCTAssertNotEqual(working.rawBytes[0x100], workingBytes[0x100])
    }

    func testPlaintextHeaderAndKeyAreNotEncrypted() throws {
        // The cipher region is slot[0x10..0x27FD8). slot[0..0x10) is
        // the plaintext slot header (magic + counter) followed by the
        // per-save key seed; both must round-trip through encrypt
        // unchanged.
        let original = makePlaintextSlot()
        let bytes = original.rawBytes
        let working = GoDData(byteStream: bytes, byteOrder: .big)
        try XDSaveCipher.encrypt(slot: working)
        XCTAssertEqual(Array(working.rawBytes.prefix(0x10)),
                       Array(bytes.prefix(0x10)),
                       "encrypt should not touch slot[0..0x10)")
    }

    func testKeySeedSensitivityViaKeyRegion() throws {
        // Two slots with identical payload but different bytes in the
        // key region (slot[0x08..0x10]) should produce different
        // ciphertexts.
        let a = makePlaintextSlot()
        var bBytes = a.rawBytes
        bBytes[0x0A] ^= 0x40   // perturb one key seed byte
        let b = GoDData(byteStream: bBytes, byteOrder: .big)

        try XDSaveCipher.encrypt(slot: a)
        try XDSaveCipher.encrypt(slot: b)

        XCTAssertNotEqual(a.rawBytes[0x100..<0x200],
                          b.rawBytes[0x100..<0x200],
                          "key seed change must propagate into ciphertext")
    }

    func testCorruptionFailsTagCheck() throws {
        let working = makePlaintextSlot()
        try XDSaveCipher.encrypt(slot: working)

        // Flip one byte deep in the encrypted payload — somewhere
        // outside the saved-tag region so we know we're testing the
        // running-sum path and not a header field.
        var corrupted = working.rawBytes
        corrupted[0x1000] ^= 0x01
        let corruptedSlot = GoDData(byteStream: corrupted, byteOrder: .big)

        let ok = try XDSaveCipher.decrypt(slot: corruptedSlot)
        XCTAssertFalse(ok,
                       "single-byte corruption should fail the running-sum tag check")
    }

    func testDeterminism() throws {
        // Same plaintext + same key seed → same ciphertext.
        let a = makePlaintextSlot()
        let b = makePlaintextSlot()
        try XDSaveCipher.encrypt(slot: a)
        try XDSaveCipher.encrypt(slot: b)
        XCTAssertEqual(a.rawBytes, b.rawBytes)
    }

    func testChecksumLanesPartitionCoverage() {
        // The four lanes should cover [0x08, 0x27FD8) exactly —
        // 4 × 0x9FF4 = 0x27FD0 bytes starting at 0x08.
        XCTAssertEqual(
            XDSaveCipher.checksumCoverageStart + 4 * XDSaveCipher.checksumLaneSpan,
            XDSaveCipher.cipherRange.upperBound,
            "checksum lane partition does not span [0x08, 0x27FD8)"
        )
    }
}
