import XCTest
@testable import Wii
@testable import GoDFoundation

final class WiiDecryptedPartitionViewTests: XCTestCase {

    /// Build a fake encrypted partition data block that the view can decrypt.
    /// Each group is encrypted with the given title key.
    private func buildEncryptedData(groupCount: Int, titleKey: [UInt8]) -> (data: GoDData, plainUserData: [[UInt8]]) {
        let groupSize = 0x8000
        let userDataPerGroup = 0x7C00
        let emptyHashes = [[UInt8]](repeating: [UInt8](repeating: 0, count: 20), count: 8)

        var encryptedData = GoDData(byteOrder: .big)
        var plainBlocks = [[UInt8]]()

        for i in 0..<groupCount {
            // Each group has unique user data so we can verify correctness
            let pattern = UInt8(i & 0xFF)
            let userData = GoDData(byteStream: Array(repeating: Int(pattern), count: userDataPerGroup), byteOrder: .big)
            plainBlocks.append(userData.rawBytes)

            let encrypted = WiiCrypto.encryptGroup(
                userData: userData,
                h1Hashes: emptyHashes,
                h2Hashes: emptyHashes,
                subgroupIndex: i % 8,
                groupIndex: (i / 8) % 8,
                titleKey: titleKey
            )
            encryptedData.append(encrypted)
        }

        return (encryptedData, plainBlocks)
    }

    // MARK: - Basic reads

    func testReadWithinSingleGroup() {
        let titleKey = [UInt8](repeating: 0x42, count: 16)
        let (encrypted, plain) = buildEncryptedData(groupCount: 2, titleKey: titleKey)

        let view = WiiDecryptedPartitionView(
            encryptedData: encrypted,
            partitionDataStart: 0,
            dataSize: encrypted.length,
            titleKey: titleKey
        )

        guard let result = view.read(atAddress: 0, length: 16) else {
            XCTFail("Read should succeed"); return
        }
        XCTAssertEqual(result.rawBytes, Array(plain[0][0..<16]))
    }

    func testReadSpanningTwoGroups() {
        let titleKey = [UInt8](repeating: 0x42, count: 16)
        let (encrypted, plain) = buildEncryptedData(groupCount: 3, titleKey: titleKey)
        let userDataPerGroup = 0x7C00

        let view = WiiDecryptedPartitionView(
            encryptedData: encrypted,
            partitionDataStart: 0,
            dataSize: encrypted.length,
            titleKey: titleKey
        )

        // Read across group 0→1 boundary
        let start = userDataPerGroup - 8
        guard let result = view.read(atAddress: UInt(start), length: 16) else {
            XCTFail("Cross-group read should succeed"); return
        }
        let expected = Array(plain[0][start...]) + Array(plain[1][0..<8])
        XCTAssertEqual(result.rawBytes, expected)
    }

    // MARK: - Out-of-bounds

    func testReadBeyondLengthReturnsNil() {
        let titleKey = [UInt8](repeating: 0x42, count: 16)
        let (encrypted, _) = buildEncryptedData(groupCount: 1, titleKey: titleKey)

        let view = WiiDecryptedPartitionView(
            encryptedData: encrypted,
            partitionDataStart: 0,
            dataSize: encrypted.length,
            titleKey: titleKey
        )

        let result = view.read(atAddress: UInt(view.length), length: 1)
        XCTAssertNil(result, "Read past end should return nil")
    }

    func testReadZeroLengthReturnsNil() {
        let titleKey = [UInt8](repeating: 0x42, count: 16)
        let (encrypted, _) = buildEncryptedData(groupCount: 1, titleKey: titleKey)

        let view = WiiDecryptedPartitionView(
            encryptedData: encrypted,
            partitionDataStart: 0,
            dataSize: encrypted.length,
            titleKey: titleKey
        )

        let result = view.read(atAddress: 0, length: 0)
        XCTAssertNil(result, "Zero-length read should return nil")
    }

    // MARK: - Partition offset

    func testPartitionDataStartOffset() {
        let titleKey = [UInt8](repeating: 0x42, count: 16)
        let (encrypted, plain) = buildEncryptedData(groupCount: 1, titleKey: titleKey)

        // Prepend some padding before the encrypted data
        let padding = GoDData(length: 0x20000, byteOrder: .big)
        padding.append(encrypted)

        let view = WiiDecryptedPartitionView(
            encryptedData: padding,
            partitionDataStart: 0x20000,
            dataSize: encrypted.length,
            titleKey: titleKey
        )

        guard let result = view.read(atAddress: 0, length: 16) else {
            XCTFail("Read with offset should succeed"); return
        }
        XCTAssertEqual(result.rawBytes, Array(plain[0][0..<16]))
    }

    // MARK: - Cache behavior

    func testRepeatedReadsUseCachedData() {
        let titleKey = [UInt8](repeating: 0x42, count: 16)
        let (encrypted, _) = buildEncryptedData(groupCount: 2, titleKey: titleKey)

        let view = WiiDecryptedPartitionView(
            encryptedData: encrypted,
            partitionDataStart: 0,
            dataSize: encrypted.length,
            titleKey: titleKey
        )

        // Read same location twice — should return identical results
        let result1 = view.read(atAddress: 100, length: 64)
        let result2 = view.read(atAddress: 100, length: 64)
        XCTAssertEqual(result1?.rawBytes, result2?.rawBytes)
    }

    // MARK: - Length calculation

    func testLengthCalculation() {
        let titleKey = [UInt8](repeating: 0x42, count: 16)
        let groupCount = 5
        let (encrypted, _) = buildEncryptedData(groupCount: groupCount, titleKey: titleKey)

        let view = WiiDecryptedPartitionView(
            encryptedData: encrypted,
            partitionDataStart: 0,
            dataSize: encrypted.length,
            titleKey: titleKey
        )

        XCTAssertEqual(view.length, groupCount * 0x7C00)
    }
}
