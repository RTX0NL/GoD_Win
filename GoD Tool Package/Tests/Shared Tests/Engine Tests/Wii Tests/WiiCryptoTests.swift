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

        guard let (_, decryptedUserData) = WiiCrypto.decryptGroup(groupData: encrypted, titleKey: titleKey) else {
            XCTFail("Decrypt should succeed"); return
        }
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

        guard let (_, decrypted) = WiiCrypto.decryptGroup(groupData: encrypted1, titleKey: titleKey) else {
            XCTFail("Decrypt should succeed"); return
        }

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

        XCTAssertEqual(decrypted1?.count, 16)
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

    // MARK: - Truncated ticket handling

    func testDecryptTitleKeyReturnsNilForTruncatedTicket() {
        // Ticket shorter than 0x1E4 bytes cannot contain the title ID at 0x1DC..0x1E4.
        let shortTicket = GoDData(length: 0x100, byteOrder: .big)
        let commonKey = [UInt8](repeating: 0x11, count: 16)
        XCTAssertNil(WiiCrypto.decryptTitleKey(ticketData: shortTicket, commonKey: commonKey),
                     "Truncated ticket should yield nil rather than crash")
    }

    func testDecryptGroupReturnsNilForTruncatedCluster() {
        let titleKey = [UInt8](repeating: 0x42, count: 16)
        let shortCluster = GoDData(length: 0x100, byteOrder: .big)
        XCTAssertNil(WiiCrypto.decryptGroup(groupData: shortCluster, titleKey: titleKey),
                     "Truncated cluster should yield nil rather than crash")
    }

    // MARK: - Full hash-tree correctness (end-to-end, no real disc)

    /// Build a whole group (64 clusters) of deterministic user data, encrypt it via
    /// encryptPartitionData, then decrypt a sample of clusters and verify the full
    /// H0 -> H1 -> H2 -> H3 chain is internally consistent.
    func testEncryptPartitionDataHashTreeIsConsistent() {
        let titleKey = [UInt8](repeating: 0x7E, count: 16)
        let clusterCount = 64                       // exactly one group
        let userPerCluster = WiiCrypto.userDataPerCluster
        let totalUser = clusterCount * userPerCluster

        // Deterministic, per-byte varying data so every cluster/chunk differs.
        var user = [UInt8](repeating: 0, count: totalUser)
        for i in 0..<totalUser {
            user[i] = UInt8((i &* 31 &+ (i / 0x400) &* 7) & 0xFF)
        }

        let (encrypted, h3Table) = WiiCrypto.encryptPartitionData(decryptedUserData: user, titleKey: titleKey)

        XCTAssertEqual(encrypted.count, clusterCount * WiiCrypto.clusterSize, "One cluster per 0x8000")
        XCTAssertEqual(h3Table.count, WiiCrypto.h3TableSize)

        // Collect stored H1 (per cluster) and H2 (per subgroup) as we walk clusters.
        var storedH1PerCluster = [[UInt8]](repeating: [], count: clusterCount)

        // Verify a representative sample of clusters (first, mid, boundaries, last).
        let sampleClusters = [0, 1, 7, 8, 31, 32, 63]
        for c in sampleClusters {
            let clusterBytes = GoDData(
                byteStream: Array(encrypted[c * WiiCrypto.clusterSize ..< (c + 1) * WiiCrypto.clusterSize]).map(Int.init),
                byteOrder: .big
            )
            guard let (hashBlock, decUser) = WiiCrypto.decryptGroup(groupData: clusterBytes, titleKey: titleKey) else {
                XCTFail("Cluster \(c) should decrypt"); return
            }

            // (a) Decrypted user data matches the original plaintext for this cluster.
            XCTAssertEqual(decUser.rawBytes, Array(user[c * userPerCluster ..< (c + 1) * userPerCluster]),
                           "Cluster \(c) user data should round-trip")

            let hb = hashBlock.rawBytes

            // (a) Recomputed H0 equals the H0 stored in the decrypted hash block.
            var recomputedH0 = [[UInt8]]()
            for i in 0..<WiiCrypto.h0PerCluster {
                let chunk = Array(decUser.rawBytes[i * 0x400 ..< (i + 1) * 0x400])
                let h = SHA1.hash(chunk)
                recomputedH0.append(h)
                let storedH0 = Array(hb[i * 20 ..< i * 20 + 20])
                XCTAssertEqual(h, storedH0, "Cluster \(c) H0[\(i)] mismatch")
            }

            // (b) H1 = SHA1(concatenated stored H0). Confirm against the H1 stored in the block.
            let recomputedH1 = SHA1.hash(recomputedH0.flatMap { $0 })
            let subgroupSlot = c % WiiCrypto.clustersPerSubgroup
            let storedH1 = Array(hb[0x280 + subgroupSlot * 20 ..< 0x280 + subgroupSlot * 20 + 20])
            XCTAssertEqual(recomputedH1, storedH1, "Cluster \(c) H1 (self slot) mismatch")
            storedH1PerCluster[c] = recomputedH1
        }

        // (c) Verify H3[group 0] == SHA1(that group's 8 H2 values), where each H2 is taken
        //     from a decrypted cluster's stored H2 table (all clusters in a group share it).
        // Decrypt the first cluster of each of the 8 subgroups to read its stored H2 table.
        var groupH2 = [[UInt8]]()
        for sg in 0..<WiiCrypto.subgroupsPerGroup {
            let c = sg * WiiCrypto.clustersPerSubgroup
            let clusterBytes = GoDData(
                byteStream: Array(encrypted[c * WiiCrypto.clusterSize ..< (c + 1) * WiiCrypto.clusterSize]).map(Int.init),
                byteOrder: .big
            )
            guard let (hashBlock, _) = WiiCrypto.decryptGroup(groupData: clusterBytes, titleKey: titleKey) else {
                XCTFail("Cluster \(c) should decrypt"); return
            }
            let hb = hashBlock.rawBytes
            // This cluster's own H2 lives at slot sg within the 0x340 table.
            let storedH2 = Array(hb[0x340 + sg * 20 ..< 0x340 + sg * 20 + 20])
            groupH2.append(storedH2)
        }
        let recomputedH3 = SHA1.hash(groupH2.flatMap { $0 })
        let storedH3 = Array(h3Table[0..<20])
        XCTAssertEqual(recomputedH3, storedH3, "H3[0] should equal SHA1 of group 0's 8 H2 values")
    }

    func testEncryptPartitionDataPadsToWholeGroups() {
        let titleKey = [UInt8](repeating: 0x01, count: 16)
        // Provide a single cluster's worth of data; expect padding up to a full 64-cluster group.
        let user = [UInt8](repeating: 0xAB, count: WiiCrypto.userDataPerCluster)
        let (encrypted, _) = WiiCrypto.encryptPartitionData(decryptedUserData: user, titleKey: titleKey)
        XCTAssertEqual(encrypted.count, WiiCrypto.clustersPerGroup * WiiCrypto.clusterSize,
                       "Should pad up to a whole 64-cluster group")
    }
}
