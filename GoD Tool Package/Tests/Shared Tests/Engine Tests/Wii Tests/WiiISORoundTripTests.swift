//
//  WiiISORoundTripTests.swift
//  WiiTests
//
//  End-to-end cover for the Wii disc pipeline: decrypt a synthetic encrypted
//  disc (built by WiiDiscFixtures straight from the spec), then rebuild it with
//  WiiISO.encryptedData and decrypt the result again.
//
//  WiiCryptoTests covers the primitives in isolation; these tests cover the
//  composition — partition table walk, partition header, boot.bin/FST offset
//  shifts, hash-tree rebuild and the TMD content link.
//

import XCTest
import FixtureCatalog
@testable import Wii
@testable import Dolphin
@testable import GoDFoundation

final class WiiISORoundTripTests: XCTestCase {

    // MARK: - Shared fixtures

    /// A rebuild encrypts a whole 64-cluster group per partition (~2 MB of
    /// pure-Swift AES each), so the round trip is built once for the suite.
    private struct RoundTrip {
        let original: GoDData
        let expected: WiiDiscFixtures.Expected
        let rebuilt: GoDData
    }
    private static var sharedRoundTrip: RoundTrip?

    private func engines() throws -> (WiiEngine, DolphinEngine) {
        (try WiiEngine.defaults(), try DolphinEngine.defaults())
    }

    private func roundTrip() throws -> RoundTrip {
        if let cached = Self.sharedRoundTrip { return cached }
        let (wiiEngine, dolphinEngine) = try engines()
        let (isoData, expected) = WiiDiscFixtures.disc(
            dolphinEngine: dolphinEngine,
            includeUpdatePartition: true
        )
        let iso = try WiiISO(
            data: isoData,
            commonKey: WiiDiscFixtures.commonKey,
            wiiEngine: wiiEngine,
            dolphinEngine: dolphinEngine
        )
        let rebuilt = try iso.encryptedData(commonKey: WiiDiscFixtures.commonKey)
        let result = RoundTrip(original: isoData, expected: expected, rebuilt: rebuilt)
        Self.sharedRoundTrip = result
        return result
    }

    // MARK: - Decrypt

    func testDecryptSyntheticDiscExtractsEveryFile() throws {
        let (wiiEngine, dolphinEngine) = try engines()
        let (isoData, expected) = WiiDiscFixtures.disc(dolphinEngine: dolphinEngine)

        let iso = try WiiISO(
            data: isoData,
            commonKey: WiiDiscFixtures.commonKey,
            wiiEngine: wiiEngine,
            dolphinEngine: dolphinEngine
        )

        XCTAssertEqual(iso.readFile(at: File("/disc_header.bin"))?.allData?.rawBytes, expected.discHeader)
        XCTAssertEqual(iso.readFile(at: File("/region_settings.bin"))?.allData?.rawBytes, expected.regionSettings)

        // Partition metadata is stored verbatim, at the partition root
        // rather than under /sys — see `WiiEngine.Data.PartitionFiles`.
        XCTAssertEqual(iso.readFile(at: File("/DATA/ticket.bin"))?.allData?.rawBytes, expected.ticket)
        XCTAssertEqual(iso.readFile(at: File("/DATA/tmd.bin"))?.allData?.rawBytes, expected.tmd)
        XCTAssertEqual(iso.readFile(at: File("/DATA/cert.bin"))?.allData?.rawBytes, expected.cert)
        XCTAssertEqual(iso.readFile(at: File("/DATA/h3.bin"))?.allData?.rawBytes, expected.h3)

        // System files come out of the decrypted payload.
        XCTAssertEqual(iso.readFile(at: File("/DATA/sys/boot.bin"))?.allData?.rawBytes, expected.boot)
        XCTAssertEqual(iso.readFile(at: File("/DATA/sys/bi2.bin"))?.allData?.rawBytes, expected.bi2)
        XCTAssertEqual(iso.readFile(at: File("/DATA/sys/apploader.img"))?.allData?.rawBytes, expected.apploader)
        XCTAssertEqual(iso.readFile(at: File("/DATA/sys/main.dol"))?.allData?.rawBytes, expected.dol)
        XCTAssertEqual(iso.readFile(at: File("/DATA/sys/fst.bin"))?.allData?.rawBytes, expected.fst)

        // User files, including a nested one, come out of the FST walk.
        for (path, bytes) in expected.files {
            XCTAssertEqual(
                iso.readFile(at: File("/DATA" + path))?.allData?.rawBytes, bytes,
                "user file \(path) should be extracted from the decrypted partition"
            )
        }
    }

    func testDecryptRejectsNonWiiImage() throws {
        let (wiiEngine, dolphinEngine) = try engines()
        let (isoData, _) = WiiDiscFixtures.disc(dolphinEngine: dolphinEngine)
        // Clear the Wii magic word.
        isoData.write(UInt32(0), atAddress: WiiDiscFixtures.wiiMagicOffset)

        XCTAssertThrowsError(
            try WiiISO(
                data: isoData,
                commonKey: WiiDiscFixtures.commonKey,
                wiiEngine: wiiEngine,
                dolphinEngine: dolphinEngine
            )
        )
    }

    // MARK: - Round trip

    func testRebuiltDiscDecryptsBackToTheSameContents() throws {
        let trip = try roundTrip()
        let (wiiEngine, dolphinEngine) = try engines()

        let reparsed = try WiiISO(
            data: trip.rebuilt,
            commonKey: WiiDiscFixtures.commonKey,
            wiiEngine: wiiEngine,
            dolphinEngine: dolphinEngine
        )

        XCTAssertEqual(reparsed.readFile(at: File("/disc_header.bin"))?.allData?.rawBytes, trip.expected.discHeader)
        XCTAssertEqual(reparsed.readFile(at: File("/region_settings.bin"))?.allData?.rawBytes, trip.expected.regionSettings)

        // The ticket and cert chain are re-emitted verbatim; the TMD is
        // relinked to the rebuilt H3 table and fakesigned, so it changes.
        XCTAssertEqual(reparsed.readFile(at: File("/DATA/ticket.bin"))?.allData?.rawBytes, trip.expected.ticket)
        XCTAssertEqual(reparsed.readFile(at: File("/DATA/cert.bin"))?.allData?.rawBytes, trip.expected.cert)

        XCTAssertEqual(reparsed.readFile(at: File("/DATA/sys/bi2.bin"))?.allData?.rawBytes, trip.expected.bi2)
        XCTAssertEqual(reparsed.readFile(at: File("/DATA/sys/apploader.img"))?.allData?.rawBytes, trip.expected.apploader)
        XCTAssertEqual(reparsed.readFile(at: File("/DATA/sys/main.dol"))?.allData?.rawBytes, trip.expected.dol)

        for (path, bytes) in trip.expected.files {
            XCTAssertEqual(
                reparsed.readFile(at: File("/DATA" + path))?.allData?.rawBytes, bytes,
                "user file \(path) should survive the encrypt/decrypt round trip"
            )
        }

        // A non-DATA partition is carried through as an opaque decrypted blob.
        let updateBlob = try XCTUnwrap(trip.expected.updateBlob)
        let rebuiltBlob = try XCTUnwrap(
            reparsed.readFile(at: File("/UPDATE/sys/partition_data.bin"))?.allData?.rawBytes,
            "the UPDATE partition must survive a rebuild"
        )
        XCTAssertEqual(
            Array(rebuiltBlob.prefix(updateBlob.count)), updateBlob,
            "UPDATE partition payload should be preserved byte for byte"
        )
    }

    func testRebuiltDiscKeepsTheUnencryptedDiscRegion() throws {
        let trip = try roundTrip()

        let magic: UInt32 = trip.rebuilt.readSafely(atAddress: WiiDiscFixtures.wiiMagicOffset)
        XCTAssertEqual(magic, WiiDiscFixtures.wiiMagic, "rebuilt disc must keep the Wii magic word")

        let magic2: UInt32 = trip.rebuilt.readSafely(atAddress: WiiDiscFixtures.discMagic2Offset)
        XCTAssertEqual(
            magic2, WiiDiscFixtures.discMagic2,
            "rebuilt disc must carry the second magic word at 0x4FFFC"
        )

        let partitions = rawPartitions(of: trip.rebuilt)
        XCTAssertEqual(partitions.map(\.type), [0, 1], "both partitions should be listed in the table")
        XCTAssertTrue(
            partitions.allSatisfy { $0.offset % WiiDiscFixtures.clusterSize == 0 },
            "partitions must start on a cluster boundary"
        )
    }

    func testRebuildIsNotPaddedToDiscCapacity() throws {
        let trip = try roundTrip()
        // Padding a rebuild out to the 4.7 GB disc capacity is the job of the
        // separate fillISO operation, not of the encrypt itself.
        XCTAssertLessThan(
            trip.rebuilt.length, 0x1000000,
            "a two-partition rebuild of a tiny disc should not be padded to disc capacity"
        )
    }

    // MARK: - Rebuilt hash tree / TMD

    func testRebuiltDiscHashTreeIsSelfConsistent() throws {
        let trip = try roundTrip()
        let partition = try XCTUnwrap(rawPartitions(of: trip.rebuilt).first { $0.type == 0 })

        let clusterCount = partition.data.count / WiiDiscFixtures.clusterSize
        XCTAssertEqual(
            clusterCount, WiiDiscFixtures.clustersPerSubgroup * WiiDiscFixtures.subgroupsPerGroup,
            "the writer pads partition data up to a whole 64-cluster group"
        )

        // Every cluster's stored H0 must be the SHA-1 of its own user data, and
        // its stored H1 slot the SHA-1 of those H0 hashes.
        var h1PerCluster = [Int: [UInt8]]()
        for cluster in [0, 1, 7, 8, 31, 63] {
            let (hashBlock, userData) = decryptCluster(partition.data, index: cluster)
            var h0 = [[UInt8]]()
            for chunk in 0..<WiiDiscFixtures.h0PerCluster {
                let hash = SHA1.hash(Array(userData[(chunk * 0x400)..<((chunk + 1) * 0x400)]))
                XCTAssertEqual(
                    hash, hashSlot(hashBlock, table: WiiDiscFixtures.h0TableOffset, index: chunk),
                    "cluster \(cluster) H0[\(chunk)] should hash its own user data"
                )
                h0.append(hash)
            }
            let h1 = SHA1.hash(h0.flatMap { $0 })
            XCTAssertEqual(
                h1,
                hashSlot(hashBlock, table: WiiDiscFixtures.h1TableOffset,
                         index: cluster % WiiDiscFixtures.clustersPerSubgroup),
                "cluster \(cluster) H1 slot should hash its own H0 table"
            )
            h1PerCluster[cluster] = h1
        }

        // H2[subgroup] = SHA-1 of that subgroup's 8 H1 hashes.
        let (subgroupZeroBlock, _) = decryptCluster(partition.data, index: 0)
        var subgroupZeroH1 = [[UInt8]]()
        for slot in 0..<WiiDiscFixtures.clustersPerSubgroup {
            subgroupZeroH1.append(hashSlot(subgroupZeroBlock, table: WiiDiscFixtures.h1TableOffset, index: slot))
        }
        XCTAssertEqual(
            SHA1.hash(subgroupZeroH1.flatMap { $0 }),
            hashSlot(subgroupZeroBlock, table: WiiDiscFixtures.h2TableOffset, index: 0),
            "H2[0] should hash subgroup 0's H1 table"
        )

        // H3[group] = SHA-1 of that group's 8 H2 hashes, and the H3 table is
        // what the TMD's content hash covers.
        var groupZeroH2 = [[UInt8]]()
        for subgroup in 0..<WiiDiscFixtures.subgroupsPerGroup {
            let (block, _) = decryptCluster(
                partition.data,
                index: subgroup * WiiDiscFixtures.clustersPerSubgroup
            )
            groupZeroH2.append(hashSlot(block, table: WiiDiscFixtures.h2TableOffset, index: subgroup))
        }
        XCTAssertEqual(
            SHA1.hash(groupZeroH2.flatMap { $0 }), Array(partition.h3[0..<20]),
            "H3[0] should hash group 0's H2 table"
        )
        XCTAssertEqual(
            SHA1.hash(partition.h3), Array(partition.tmd[0x1F4..<0x208]),
            "the TMD's content hash should cover the rebuilt H3 table"
        )
    }

    func testRebuiltBootBinStoresShiftedOffsets() throws {
        let trip = try roundTrip()
        let partition = try XCTUnwrap(rawPartitions(of: trip.rebuilt).first { $0.type == 0 })

        // Decrypt enough of the payload to cover boot.bin, the DOL and the FST.
        var payload = [UInt8]()
        for cluster in 0..<4 {
            payload.append(contentsOf: decryptCluster(partition.data, index: cluster).userData)
        }

        func shiftedField(at offset: Int) -> Int {
            let word = (UInt32(payload[offset]) << 24) | (UInt32(payload[offset + 1]) << 16)
                | (UInt32(payload[offset + 2]) << 8) | UInt32(payload[offset + 3])
            return Int(word) * 4
        }

        let dolOffset = shiftedField(at: WiiDiscFixtures.bootDolOffset)
        let fstOffset = shiftedField(at: WiiDiscFixtures.bootFSTOffset)
        let fstSize = shiftedField(at: WiiDiscFixtures.bootFSTSize)
        let userOffset = shiftedField(at: WiiDiscFixtures.bootUserDataOffset)

        XCTAssertEqual(
            Array(payload[dolOffset..<(dolOffset + trip.expected.dol.count)]), trip.expected.dol,
            "boot.bin's main_executable_offset << 2 should point at the DOL"
        )
        XCTAssertGreaterThan(fstSize, 0)
        XCTAssertEqual(
            Array(payload[fstOffset..<(fstOffset + 4)]), [0x01, 0x00, 0x00, 0x00],
            "boot.bin's fst_offset << 2 should point at the FST root entry"
        )
        let fileA = try XCTUnwrap(trip.expected.files["/files/a.bin"])
        XCTAssertEqual(
            Array(payload[userOffset..<(userOffset + fileA.count)]), fileA,
            "boot.bin's user_data_offset << 2 should point at the first user file"
        )
    }

    // MARK: - Independent readers for the rebuilt image

    private struct RawPartition {
        var offset: Int
        var type: Int
        var tmd: [UInt8]
        var h3: [UInt8]
        var data: [UInt8]
    }

    /// Walk the partition table and headers of an encrypted image with plain
    /// reads, so the assertions don't depend on WiiISO's own parsing.
    private func rawPartitions(of iso: GoDData) -> [RawPartition] {
        func word(at offset: Int) -> Int {
            let value: UInt32 = iso.readSafely(atAddress: offset)
            return Int(value)
        }

        var result = [RawPartition]()
        for table in 0..<4 {
            let count = word(at: WiiDiscFixtures.partitionTableOffset + table * 8)
            guard count > 0 else { continue }
            let entriesOffset = word(at: WiiDiscFixtures.partitionTableOffset + table * 8 + 4) << 2
            for index in 0..<count {
                let offset = word(at: entriesOffset + index * 8) << 2
                let type = word(at: entriesOffset + index * 8 + 4)

                let header = WiiDiscFixtures.partitionHeaderOffset
                let tmdSize = word(at: offset + header)
                let tmdOffset = word(at: offset + header + 0x04) << 2
                let h3Offset = word(at: offset + header + 0x10) << 2
                let dataOffset = word(at: offset + header + 0x14) << 2
                let dataSize = word(at: offset + header + 0x18) << 2

                result.append(RawPartition(
                    offset: offset,
                    type: type,
                    tmd: iso.read(atAddress: offset + tmdOffset, length: tmdSize)?.rawBytes ?? [],
                    h3: iso.read(atAddress: offset + h3Offset, length: WiiDiscFixtures.h3TableSize)?.rawBytes ?? [],
                    data: iso.read(atAddress: offset + dataOffset, length: dataSize)?.rawBytes ?? []
                ))
            }
        }
        return result
    }

    /// Decrypt one cluster with AES-128-CBC directly: hash block with a zero IV,
    /// user data with the IV stored in the hash block's ciphertext at 0x3D0.
    private func decryptCluster(_ data: [UInt8], index: Int) -> (hashBlock: [UInt8], userData: [UInt8]) {
        let base = index * WiiDiscFixtures.clusterSize
        let cipherHashBlock = Array(data[base..<(base + WiiDiscFixtures.hashBlockSize)])
        let hashBlock = AES128CBC.decrypt(
            bytes: cipherHashBlock,
            key: WiiDiscFixtures.titleKey,
            iv: [UInt8](repeating: 0, count: 16)
        )
        let userIV = Array(cipherHashBlock[WiiDiscFixtures.userIVOffset..<(WiiDiscFixtures.userIVOffset + 16)])
        let userData = AES128CBC.decrypt(
            bytes: Array(data[(base + WiiDiscFixtures.hashBlockSize)..<(base + WiiDiscFixtures.clusterSize)]),
            key: WiiDiscFixtures.titleKey,
            iv: userIV
        )
        return (hashBlock, userData)
    }

    private func hashSlot(_ hashBlock: [UInt8], table: Int, index: Int) -> [UInt8] {
        Array(hashBlock[(table + index * 20)..<(table + index * 20 + 20)])
    }
}
