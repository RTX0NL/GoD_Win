//
//  RVZWiiRestoreTests.swift
//
//  The Wii half of a WIA/RVZ restore: `RVZImage` hands each 2 MiB group of
//  decrypted partition data to a `WiiPartitionRestorer`, and
//  `WiiRVZPartitionRestorer` rebuilds the hash tree and re-encrypts it.
//
//  Checked by decrypting the result and comparing, which is a real test
//  rather than a round trip against itself: the fixture writes the partition
//  payload, `WiiRVZPartitionRestorer` encrypts it, and `WiiCrypto.decryptGroup`
//  — the path a disc reader uses — takes it apart again.
//

import XCTest
import GoDFoundation
import Dolphin
import FixtureCatalog
@testable import Wii

final class RVZWiiRestoreTests: XCTestCase {

    private let titleKey: [UInt8] = (0..<16).map { UInt8($0 &* 11 &+ 3) }
    private let firstSector: UInt32 = 0x1F04

    private func pattern(_ count: Int, seed: UInt8) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(count)
        var state = UInt32(seed) &* 2654435761 &+ 1
        for _ in 0..<count {
            state = state &* 1664525 &+ 1013904223
            out.append(UInt8(truncatingIfNeeded: state >> 16))
        }
        return out
    }

    private func image(sectors: Int, exceptions: [Int: [WIAExceptionList.Exception]] = [:]) -> RVZFixtures.Image {
        var spec = RVZFixtures.Image()
        spec.chunkSize = 0x2_0000
        spec.discType = .wii
        spec.elideZeroGroups = false
        var header = [UInt8](repeating: 0, count: 0x80)
        for (i, b) in Array("RTSTE0".utf8).enumerated() { header[i] = b }
        header[0x18] = 0x5D; header[0x19] = 0x1C; header[0x1A] = 0x9E; header[0x1B] = 0xA3
        spec.discHeader = header
        spec.isoSize = UInt64((Int(firstSector) + sectors) * WiiCrypto.clusterSize)
        spec.rawRegions = [RVZFixtures.RawRegion(discOffset: 0x80, data: pattern(0x8000, seed: 2))]
        spec.partitions = [
            RVZFixtures.Partition(
                titleKey: titleKey,
                firstSector: firstSector,
                managementSectors: UInt32(sectors),
                dataSectors: 0,
                decryptedData: pattern(sectors * WiiCrypto.userDataPerCluster, seed: 6),
                exceptionsByChunk: exceptions
            ),
        ]
        return spec
    }

    /// Every cluster decrypts back to the payload the image carried.
    func testRestoredPartitionDecryptsToTheStoredPayload() throws {
        let sectors = 64
        let spec = image(sectors: sectors)
        let expected = spec.partitions[0].decryptedData
        let iso = try RVZImage(binary: RVZFixtures.build(spec))
            .restoreISO(partitionRestorer: WiiRVZPartitionRestorer())

        let base = UInt(firstSector) * UInt(WiiCrypto.clusterSize)
        var recovered = [UInt8]()
        for cluster in 0..<sectors {
            let offset = base + UInt(cluster * WiiCrypto.clusterSize)
            let encrypted = try XCTUnwrap(iso.read(atAddress: offset, length: UInt(WiiCrypto.clusterSize)))
            let decrypted = try XCTUnwrap(WiiCrypto.decryptGroup(groupData: encrypted, titleKey: titleKey))
            recovered.append(contentsOf: decrypted.userData.rawBytes)
        }
        XCTAssertEqual(recovered, expected)
    }

    /// The hash tree the restore builds is the one a disc reader expects:
    /// each cluster's H0 entries hash its own user data, and the H1 and H2
    /// tables chain upward.
    func testRestoredPartitionCarriesAConsistentHashTree() throws {
        let sectors = 64
        let spec = image(sectors: sectors)
        let iso = try RVZImage(binary: RVZFixtures.build(spec))
            .restoreISO(partitionRestorer: WiiRVZPartitionRestorer())

        let base = UInt(firstSector) * UInt(WiiCrypto.clusterSize)
        var hashBlocks: [[UInt8]] = []
        var userData: [[UInt8]] = []
        for cluster in 0..<sectors {
            let offset = base + UInt(cluster * WiiCrypto.clusterSize)
            let encrypted = try XCTUnwrap(iso.read(atAddress: offset, length: UInt(WiiCrypto.clusterSize)))
            let decrypted = try XCTUnwrap(WiiCrypto.decryptGroup(groupData: encrypted, titleKey: titleKey))
            hashBlocks.append(decrypted.hashBlock.rawBytes)
            userData.append(decrypted.userData.rawBytes)
        }

        // H0: 31 hashes of 0x400 bytes each.
        for cluster in 0..<sectors {
            for i in 0..<WiiCrypto.h0PerCluster {
                let chunk = Array(userData[cluster][(i * 0x400)..<((i + 1) * 0x400)])
                let stored = Array(hashBlocks[cluster][(i * 20)..<((i + 1) * 20)])
                XCTAssertEqual(SHA1.hash(chunk), stored, "H0 \(i) of cluster \(cluster)")
            }
        }
        // H1: each subgroup's 8 entries hash their cluster's H0 table.
        for cluster in 0..<sectors {
            let subgroup = cluster / WiiCrypto.clustersPerSubgroup
            for k in 0..<WiiCrypto.clustersPerSubgroup {
                let source = subgroup * WiiCrypto.clustersPerSubgroup + k
                let h0Table = Array(hashBlocks[source][0..<(WiiCrypto.h0PerCluster * 20)])
                let stored = Array(hashBlocks[cluster][(0x280 + k * 20)..<(0x280 + k * 20 + 20)])
                XCTAssertEqual(SHA1.hash(h0Table), stored, "H1 \(k) in cluster \(cluster)")
            }
        }
        // H2: the group's 8 entries hash each subgroup's H1 table.
        for subgroup in 0..<WiiCrypto.subgroupsPerGroup {
            let source = subgroup * WiiCrypto.clustersPerSubgroup
            let h1Table = Array(hashBlocks[source][0x280..<(0x280 + WiiCrypto.clustersPerSubgroup * 20)])
            let stored = Array(hashBlocks[0][(0x340 + subgroup * 20)..<(0x340 + subgroup * 20 + 20)])
            XCTAssertEqual(SHA1.hash(h1Table), stored, "H2 \(subgroup)")
        }
    }

    /// An exception replaces one recomputed hash. The point of the mechanism
    /// is that the replacement survives into the encrypted cluster, so a
    /// disc whose hashes disagree with its data round-trips unchanged.
    func testAHashExceptionOverridesTheRecomputedHash() throws {
        let marker = [UInt8](repeating: 0xC3, count: 20)
        // Chunk 0 with a 0x20000 chunk covers clusters 0-3; offset 0x420
        // lands in cluster 1's H0 table, entry 1.
        let spec = image(
            sectors: 64,
            exceptions: [0: [WIAExceptionList.Exception(offset: 0x0420, hash: marker)]]
        )
        let iso = try RVZImage(binary: RVZFixtures.build(spec))
            .restoreISO(partitionRestorer: WiiRVZPartitionRestorer())

        let offset = UInt(firstSector) * UInt(WiiCrypto.clusterSize) + UInt(WiiCrypto.clusterSize)
        let encrypted = try XCTUnwrap(iso.read(atAddress: offset, length: UInt(WiiCrypto.clusterSize)))
        let decrypted = try XCTUnwrap(WiiCrypto.decryptGroup(groupData: encrypted, titleKey: titleKey))
        let block = decrypted.hashBlock.rawBytes
        XCTAssertEqual(Array(block[0x20..<0x34]), marker, "the exception should have replaced H0 entry 1")
        // Its neighbours are still the hashes of the data.
        let firstChunk = Array(decrypted.userData.rawBytes[0..<0x400])
        XCTAssertEqual(Array(block[0..<20]), SHA1.hash(firstChunk))
    }

    /// A partition that ends partway through a group writes only the
    /// clusters it has, but hashes the group as though the rest were zeroes
    /// — those hashes are in the blocks of the clusters that do exist.
    func testAShortFinalGroupHashesAbsentClustersAsZeroes() throws {
        let sectors = 70
        let spec = image(sectors: sectors)
        let iso = try RVZImage(binary: RVZFixtures.build(spec))
            .restoreISO(partitionRestorer: WiiRVZPartitionRestorer())
        XCTAssertEqual(iso.length, (Int(firstSector) + sectors) * WiiCrypto.clusterSize)

        // Cluster 64 is the first of the short group; its H1 table covers
        // clusters 64-71, of which only 64-69 exist. Entry 7 must therefore
        // be the H1 of an all-zero cluster.
        let base = UInt(firstSector) * UInt(WiiCrypto.clusterSize)
        let encrypted = try XCTUnwrap(
            iso.read(atAddress: base + UInt(64 * WiiCrypto.clusterSize), length: UInt(WiiCrypto.clusterSize))
        )
        let decrypted = try XCTUnwrap(WiiCrypto.decryptGroup(groupData: encrypted, titleKey: titleKey))
        let block = decrypted.hashBlock.rawBytes

        let zeroChunk = [UInt8](repeating: 0, count: 0x400)
        let zeroH0 = SHA1.hash(zeroChunk)
        var zeroH0Table = [UInt8]()
        for _ in 0..<WiiCrypto.h0PerCluster { zeroH0Table.append(contentsOf: zeroH0) }
        XCTAssertEqual(Array(block[(0x280 + 7 * 20)..<(0x280 + 8 * 20)]), SHA1.hash(zeroH0Table))
    }
}
