//
//  WiiEncryptedPartitionDataViewTests.swift
//
//  The lazy encrypt path has to produce exactly what the whole-buffer one
//  did. `WiiCrypto.encryptPartitionData` is still there — it is the reference
//  these compare against, which is the only reason it was kept once the
//  rebuild stopped using it.
//
//  **Budget.** AES runs at roughly 0.25 MB/s in a debug build, so every
//  2 MB group encrypted here costs about eight seconds. These tests are built
//  around that: each one reuses a single reference encryption for as many
//  assertions as it can, the H3 check is SHA-only, and the multi-group case
//  leans on the fact that groups are independent — H0, H1 and H2 are all
//  computed within a group, and H3 is per group — so a second group can be
//  checked against a one-group reference instead of a two-group one.
//  Together that is about nine groups. A first draft that compared every
//  shape against its own full-size reference took five minutes.
//

import XCTest
import GoDFoundation
@testable import Wii

final class WiiEncryptedPartitionDataViewTests: XCTestCase {

    private let titleKey: [UInt8] = (0..<16).map { UInt8($0 &* 13 &+ 7) }
    private var groupUserSize: Int { WiiCrypto.clustersPerGroup * WiiCrypto.userDataPerCluster }
    private var groupSize: Int { WiiCrypto.clustersPerGroup * WiiCrypto.clusterSize }

    private func payload(_ count: Int, seed: UInt8 = 3) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(count)
        var state = UInt32(seed) &* 2654435761 &+ 1
        for _ in 0..<count {
            state = state &* 1664525 &+ 1013904223
            out.append(UInt8(truncatingIfNeeded: state >> 16))
        }
        return out
    }

    private func view(over bytes: [UInt8]) -> WiiEncryptedPartitionDataView {
        WiiEncryptedPartitionDataView(
            decryptedUserData: GoDData(byteStream: bytes, byteOrder: .big),
            titleKey: titleKey
        )
    }

    private func readAll(_ view: WiiEncryptedPartitionDataView, window: Int) throws -> [UInt8] {
        var out = [UInt8]()
        var offset = 0
        while offset < view.length {
            let count = min(window, view.length - offset)
            let chunk = try XCTUnwrap(view.read(atAddress: offset, length: count))
            out.append(contentsOf: chunk.rawBytes)
            offset += count
        }
        return out
    }

    // MARK: - Equivalence with the whole-buffer path

    /// One group, and the window-independence check folded in against the same
    /// reference: whatever size a caller reads in, the bytes are the same. The
    /// 8 MB windows a file copy uses do not line up with the 2 MiB groups the
    /// view works in, which is the case that matters.
    func testMatchesTheWholeBufferEncryptAndIsIndependentOfWindowSize() throws {
        let bytes = payload(groupUserSize)
        let expected = WiiCrypto.encryptPartitionData(decryptedUserData: bytes, titleKey: titleKey)
        XCTAssertEqual(view(over: bytes).length, expected.encrypted.count)
        // Windows that divide a group, that don't, and that exceed it.
        for window in [groupSize, 0x7C00, groupSize + 1] {
            XCTAssertEqual(
                try readAll(view(over: bytes), window: window), expected.encrypted,
                "window \(window)"
            )
        }
    }

    /// A payload that stops partway through a group. The absent clusters hash
    /// as zeroes, and their hashes land in the hash blocks of the ones that
    /// exist — so a short group is not a truncated full one.
    func testMatchesTheWholeBufferEncryptForAPartialGroup() throws {
        let bytes = payload(groupUserSize / 3, seed: 5)
        let expected = WiiCrypto.encryptPartitionData(decryptedUserData: bytes, titleKey: titleKey)
        let view = self.view(over: bytes)
        XCTAssertEqual(view.length, groupSize, "a partial payload still occupies a whole group")
        XCTAssertEqual(try view.materialized().rawBytes, expected.encrypted)
    }

    /// Two groups, so a read crosses a group boundary and the cache holds more
    /// than one entry. Checked against a one-group reference over the second
    /// group's own payload, which is sound because groups are independent —
    /// and half the AES of a two-group reference.
    func testSecondGroupMatchesAOneGroupEncryptionOfItsOwnPayload() throws {
        let first = payload(groupUserSize, seed: 7)
        let second = payload(groupUserSize / 2, seed: 8)
        let view = self.view(over: first + second)
        XCTAssertEqual(view.length, 2 * groupSize)

        let reference = WiiCrypto.encryptPartitionData(decryptedUserData: second, titleKey: titleKey)
        let secondGroup = try XCTUnwrap(view.read(atAddress: groupSize, length: groupSize))
        XCTAssertEqual(secondGroup.rawBytes, reference.encrypted)

        // A read that straddles the boundary must stitch the two together.
        let straddling = try XCTUnwrap(view.read(atAddress: groupSize - 0x10, length: 0x20))
        XCTAssertEqual(Array(straddling.rawBytes.suffix(0x10)), Array(reference.encrypted.prefix(0x10)))
    }

    /// The H3 table from the SHA-only pass must equal what a per-group walk
    /// produces. It is what the TMD is signed over, so a difference here would
    /// make every rebuilt disc fail its own content hash.
    ///
    /// Compared against `groupHashes` directly rather than against
    /// `encryptPartitionData`, which would encrypt as a side effect.
    func testH3TableMatchesAPerGroupWalk() throws {
        for count in [groupUserSize / 4, groupUserSize, groupUserSize * 2 + 1] {
            let bytes = payload(count, seed: 11)
            let source = GoDData(byteStream: bytes, byteOrder: .big)
            let streamed = WiiCrypto.h3Table(forDecryptedUserData: source)

            var expected = [UInt8](repeating: 0, count: WiiCrypto.h3TableSize)
            for group in 0..<WiiCrypto.groupCount(forDecryptedLength: count) {
                let window = WiiCrypto.decryptedGroup(group, of: source)
                let h3 = WiiCrypto.groupHashes(forUserData: window).h3
                for j in 0..<20 { expected[group * 20 + j] = h3[j] }
            }
            XCTAssertEqual(streamed, expected, "payload of \(count) bytes")
        }
    }

    // MARK: - Bounds and geometry

    func testRejectsReadsOutsideItself() {
        let view = self.view(over: payload(groupUserSize))
        XCTAssertNil(view.read(atAddress: UInt(view.length), length: 1))
        XCTAssertNil(view.read(atAddress: UInt(view.length - 1), length: 2))
        XCTAssertNil(view.read(atAddress: 0, length: 0))
    }

    /// An empty payload still occupies one group, matching what the
    /// whole-buffer path has always produced. Length only — encrypting a group
    /// of zeroes twice to compare them is eight seconds for nothing the
    /// partial-group test doesn't already cover.
    func testEmptyPayloadOccupiesOneGroup() {
        XCTAssertEqual(view(over: []).length, groupSize)
        XCTAssertEqual(WiiCrypto.encryptedLength(forDecryptedLength: 0), groupSize)
        XCTAssertEqual(WiiCrypto.groupCount(forDecryptedLength: 0), 1)
    }

    func testGeometryHelpersAgreeWithTheGroupSize() {
        XCTAssertEqual(WiiCrypto.groupCount(forDecryptedLength: 1), 1)
        XCTAssertEqual(WiiCrypto.groupCount(forDecryptedLength: groupUserSize), 1)
        XCTAssertEqual(WiiCrypto.groupCount(forDecryptedLength: groupUserSize + 1), 2)
        XCTAssertEqual(WiiCrypto.encryptedLength(forDecryptedLength: groupUserSize + 1), 2 * groupSize)
    }

    /// A group shorter than the source claims is zero-padded, not truncated.
    func testDecryptedGroupPadsPastTheEndOfTheSource() {
        let bytes = payload(100, seed: 19)
        let window = WiiCrypto.decryptedGroup(0, of: GoDData(byteStream: bytes, byteOrder: .big))
        XCTAssertEqual(window.count, groupUserSize)
        XCTAssertEqual(Array(window.prefix(100)), bytes)
        XCTAssertEqual(Array(window.dropFirst(100)), [UInt8](repeating: 0, count: groupUserSize - 100))
        // A group past the end is all zeroes rather than nil.
        XCTAssertEqual(
            WiiCrypto.decryptedGroup(5, of: GoDData(byteStream: bytes, byteOrder: .big)),
            [UInt8](repeating: 0, count: groupUserSize)
        )
    }
}
