import XCTest
@testable import Wii
@testable import GoDFoundation

final class WiiCryptoTests: XCTestCase {

    // MARK: - Group encrypt/decrypt round-trip

    func testGroupEncryptDecryptRoundTrip() {
        let titleKey = [UInt8](repeating: 0x42, count: 16)
        let userData = GoDData(byteStream: (0..<0x7C00).map { UInt8($0 & 0xFF) }, byteOrder: .big)

        let emptyHashes = [[UInt8]](repeating: [UInt8](repeating: 0, count: 20), count: 8)
        let encrypted = WiiCrypto.encryptGroup(
            userData: userData,
            h1Hashes: emptyHashes,
            h2Hashes: emptyHashes,
            subgroupIndex: 0,
            groupIndex: 0,
            titleKey: titleKey
        )

        XCTAssertEqual(encrypted.length, 0x8000, "Encrypted group should be 0x8000 bytes")

        let (_, decryptedUserData) = WiiCrypto.decryptGroup(groupData: encrypted, titleKey: titleKey)
        XCTAssertEqual(decryptedUserData.rawBytes, userData.rawBytes, "Decrypt(Encrypt(data)) should return original")
    }

    func testGroupDecryptEncryptProducesSameEncryptedData() {
        let titleKey = [UInt8](repeating: 0x55, count: 16)
        let originalUserData = GoDData(byteStream: [UInt8](repeating: 0xBE, count: 0x7C00), byteOrder: .big)

        let emptyHashes = [[UInt8]](repeating: [UInt8](repeating: 0, count: 20), count: 8)
        let encrypted1 = WiiCrypto.encryptGroup(
            userData: originalUserData,
            h1Hashes: emptyHashes,
            h2Hashes: emptyHashes,
            subgroupIndex: 0,
            groupIndex: 0,
            titleKey: titleKey
        )

        let (_, decrypted) = WiiCrypto.decryptGroup(groupData: encrypted1, titleKey: titleKey)

        let encrypted2 = WiiCrypto.encryptGroup(
            userData: decrypted,
            h1Hashes: emptyHashes,
            h2Hashes: emptyHashes,
            subgroupIndex: 0,
            groupIndex: 0,
            titleKey: titleKey
        )

        XCTAssertEqual(encrypted1.rawBytes, encrypted2.rawBytes, "Re-encrypting decrypted data should produce identical ciphertext")
    }

    // MARK: - Title key decryption

    func testDecryptTitleKeyProducesConsistentResult() {
        // Build a minimal ticket-like data with known encrypted key and title ID
        let ticketData = GoDData(length: 0x2A4, byteOrder: .big)
        let commonKey = [UInt8](repeating: 0x11, count: 16)

        // Write a known encrypted title key at 0x1BF
        let fakeTitleKey = [UInt8](repeating: 0xAA, count: 16)
        for (i, byte) in fakeTitleKey.enumerated() {
            ticketData.write(UInt8(byte), atAddress: 0x1BF + i)
        }
        // Write title ID at 0x1DC (8 bytes, used as IV padded with zeros)
        for i in 0..<8 {
            ticketData.write(UInt8(i), atAddress: 0x1DC + i)
        }

        let decrypted1 = WiiCrypto.decryptTitleKey(ticketData: ticketData, commonKey: commonKey)
        let decrypted2 = WiiCrypto.decryptTitleKey(ticketData: ticketData, commonKey: commonKey)

        XCTAssertEqual(decrypted1.count, 16)
        XCTAssertEqual(decrypted1, decrypted2, "Same inputs should produce same title key")
    }

    func testDifferentCommonKeysProduceDifferentTitleKeys() {
        let ticketData = GoDData(length: 0x2A4, byteOrder: .big)
        for i in 0..<16 {
            ticketData.write(UInt8(0xCC), atAddress: 0x1BF + i)
        }

        let key1 = [UInt8](repeating: 0x11, count: 16)
        let key2 = [UInt8](repeating: 0x22, count: 16)

        let decrypted1 = WiiCrypto.decryptTitleKey(ticketData: ticketData, commonKey: key1)
        let decrypted2 = WiiCrypto.decryptTitleKey(ticketData: ticketData, commonKey: key2)

        XCTAssertNotEqual(decrypted1, decrypted2)
    }

    // MARK: - Hash chain

    func testH0HashDeterministic() {
        let block = GoDData(byteStream: [UInt8](repeating: 0x42, count: 0x7C00), byteOrder: .big)
        let h0a = WiiCrypto.calculateH0Hashes(subgroupBlocks: [block])
        let h0b = WiiCrypto.calculateH0Hashes(subgroupBlocks: [block])

        XCTAssertEqual(h0a.count, 1)
        XCTAssertEqual(h0a[0].count, 31, "Each block should produce 31 H0 hashes")
        XCTAssertEqual(h0a[0], h0b[0], "Same data should produce same H0 hashes")
    }

    func testH1HashOfH0() {
        let dummyH0 = (0..<31).map { _ in [UInt8](repeating: 0xAB, count: 20) }
        let h1 = WiiCrypto.calculateH1Hash(h0Hashes: dummyH0)
        XCTAssertEqual(h1.count, 20, "H1 hash should be 20 bytes (SHA-1)")

        // Same input → same output
        let h1b = WiiCrypto.calculateH1Hash(h0Hashes: dummyH0)
        XCTAssertEqual(h1, h1b)
    }

    func testH2HashOfH1() {
        let dummyH1 = (0..<8).map { _ in [UInt8](repeating: 0xCD, count: 20) }
        let h2 = WiiCrypto.calculateH2Hash(h1Hashes: dummyH1)
        XCTAssertEqual(h2.count, 20)
    }

    func testH3HashOfH2() {
        let dummyH2 = (0..<8).map { _ in [UInt8](repeating: 0xEF, count: 20) }
        let h3 = WiiCrypto.calculateH3Hash(h2Hashes: dummyH2)
        XCTAssertEqual(h3.count, 20)
    }

    func testHashChainDifferentDataProducesDifferentHashes() {
        let block1 = GoDData(byteStream: [UInt8](repeating: 0x00, count: 0x7C00), byteOrder: .big)
        let block2 = GoDData(byteStream: [UInt8](repeating: 0xFF, count: 0x7C00), byteOrder: .big)

        let h0a = WiiCrypto.calculateH0Hashes(subgroupBlocks: [block1])
        let h0b = WiiCrypto.calculateH0Hashes(subgroupBlocks: [block2])

        XCTAssertNotEqual(h0a[0][0], h0b[0][0], "Different data should produce different H0 hashes")
    }

    // MARK: - Fakesigning

    func testFakesignTicketProducesValidSignature() {
        let ticket = GoDData(length: 0x2A4, byteOrder: .big)
        // Fill with some data
        for i in 0..<0x2A4 {
            ticket.write(UInt8(i & 0xFF), atAddress: i)
        }

        let signed = WiiCrypto.fakesignTicket(ticket)
        let hash = SHA1.hash(signed)

        XCTAssertEqual(hash.rawBytes[0], 0x00, "Fakesigned ticket hash should start with 0x00")
    }

    func testFakesignTMDProducesValidSignature() {
        let tmd = GoDData(length: 0x208, byteOrder: .big)
        for i in 0..<0x208 {
            tmd.write(UInt8(i & 0xFF), atAddress: i)
        }

        let signed = WiiCrypto.fakesignTMD(tmd)
        let hash = SHA1.hash(signed)

        XCTAssertEqual(hash.rawBytes[0], 0x00, "Fakesigned TMD hash should start with 0x00")
    }
}
