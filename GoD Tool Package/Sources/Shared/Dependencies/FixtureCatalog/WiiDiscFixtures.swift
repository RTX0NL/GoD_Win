//
//  WiiDiscFixtures.swift
//  FixtureCatalog
//
//  Builds a synthetic, encrypted Wii disc image for end-to-end tests.
//
//  The encoder here is written straight from the public Wii disc spec
//  (Wiibrew "Wii disc", Dolphin's VolumeWii) instead of calling WiiCrypto, and
//  lays the partition filesystem out with raw writes at the canonical offsets
//  rather than through the engine's struct definitions. Decrypting it with the
//  production code is therefore a cross-check rather than a round-trip against
//  ourselves. Only the AES-128-CBC and SHA-1 primitives are shared — those have
//  their own known-answer tests.
//
//  Sizes are deliberately tiny: a partition only needs whole 0x8000 clusters,
//  and the pure-Swift AES runs at ~4 s/MB in a debug build.
//

import Foundation
import GoDFoundation
import Dolphin

public enum WiiDiscFixtures {

    // MARK: - Disc geometry (spec constants, deliberately not read from the engine)

    public static let clusterSize = 0x8000
    public static let hashBlockSize = 0x400
    public static let userDataPerCluster = 0x7C00
    public static let h0PerCluster = 31
    public static let clustersPerSubgroup = 8
    public static let subgroupsPerGroup = 8
    public static let h3TableSize = 0x18000

    public static let h0TableOffset = 0x000
    public static let h1TableOffset = 0x280
    public static let h2TableOffset = 0x340
    public static let userIVOffset = 0x3D0

    public static let wiiMagic: UInt32 = 0x5D1C9EA3
    public static let wiiMagicOffset = 0x18
    /// Second magic word every retail Wii disc carries in its unencrypted region.
    public static let discMagic2: UInt32 = 0xC3F81A8E
    public static let discMagic2Offset = 0x4FFFC

    public static let partitionTableOffset = 0x40000
    public static let regionSettingsOffset = 0x4E000
    public static let firstPartitionOffset = 0x50000

    public static let ticketLength = 0x2A4
    public static let partitionHeaderOffset = 0x2A4
    public static let tmdOffsetInPartition = 0x2C0
    public static let tmdLength = 0x208
    public static let certLength = 0x40

    /// boot.bin field offsets (Wii stores all of these >> 2).
    public static let bootDolOffset = 0x420
    public static let bootFSTOffset = 0x424
    public static let bootFSTSize = 0x428
    public static let bootMaxFSTSize = 0x42C
    public static let bootUserDataOffset = 0x434
    public static let bootUserDataLength = 0x438
    public static let bootLength = 0x440

    // MARK: - Keys / identity

    public static let commonKey: [UInt8] = [
        0x0F, 0x1E, 0x2D, 0x3C, 0x4B, 0x5A, 0x69, 0x78,
        0x87, 0x96, 0xA5, 0xB4, 0xC3, 0xD2, 0xE1, 0xF0
    ]
    public static let titleKey: [UInt8] = [
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
        0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00
    ]
    /// Wii title ID: 00010001 + the four-character game ID.
    public static let titleID: [UInt8] = [0x00, 0x01, 0x00, 0x01, 0x52, 0x54, 0x45, 0x53]
    public static let gameID = "RTES"

    /// The common key as the hex text a project's key file holds.
    public static var commonKeyHex: String {
        commonKey.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - What a correct dump of the fixture must produce

    public struct Expected {
        public var discHeader: [UInt8] = []
        public var regionSettings: [UInt8] = []
        public var boot: [UInt8] = []
        public var bi2: [UInt8] = []
        public var apploader: [UInt8] = []
        public var dol: [UInt8] = []
        public var fst: [UInt8] = []
        /// Keyed by the path the dump is expected to use, e.g. "/files/a.bin".
        public var files: [String: [UInt8]] = [:]
        public var ticket: [UInt8] = []
        public var tmd: [UInt8] = []
        public var cert: [UInt8] = []
        public var h3: [UInt8] = []
        /// Raw decrypted payload of the UPDATE partition, when one was built.
        public var updateBlob: [UInt8]?
        /// Unshifted byte offsets the DATA payload was laid out at.
        public var dolOffset = 0
        public var fstOffset = 0
        public var userOffset = 0
    }

    // MARK: - Disc assembly

    /// Build a complete encrypted Wii disc image.
    /// - Parameter includeUpdatePartition: also emit a one-cluster UPDATE
    ///   partition, which a dump stores as an opaque decrypted blob.
    public static func disc(
        dolphinEngine: DolphinEngine,
        includeUpdatePartition: Bool = false
    ) -> (iso: GoDData, expected: Expected) {
        var (payload, expected) = dataPartitionPayload(dolphinEngine: dolphinEngine)

        let iso = GoDData(length: 0, byteOrder: .big)

        // Disc header: game ID, title, and the Wii magic word.
        let discHeader = GoDData(length: bootLength, byteOrder: .big)
        discHeader.write(gameID.data(format: .utf8), atAddress: 0)
        discHeader.write(wiiMagic, atAddress: wiiMagicOffset)
        discHeader.write("GoD Tool synthetic Wii disc".data(format: .utf8), atAddress: 0x20)
        iso.write(discHeader, atAddress: 0)
        expected.discHeader = discHeader.rawBytes

        // Region settings (0x20 bytes at 0x4E000): region code + age ratings.
        let regionSettings = GoDData(length: 0x20, byteOrder: .big)
        regionSettings.write(UInt32(1), atAddress: 0)   // 1 = NTSC-U
        iso.write(regionSettings, atAddress: regionSettingsOffset)
        expected.regionSettings = regionSettings.rawBytes

        iso.write(discMagic2, atAddress: discMagic2Offset)

        // Partition table: one table holding every partition, its entries
        // placed after the four (count, offset) slots.
        var partitions: [(type: Int, payload: [UInt8])] = [(type: 0, payload: payload)]
        if includeUpdatePartition {
            let updateBlob = (0..<userDataPerCluster).map { UInt8(($0 &* 7 &+ 3) & 0xFF) }
            partitions.append((type: 1, payload: updateBlob))
            expected.updateBlob = updateBlob
        }

        let entriesOffset = partitionTableOffset + 0x20
        iso.write(UInt32(partitions.count), atAddress: partitionTableOffset)
        iso.write(UInt32(entriesOffset >> 2), atAddress: partitionTableOffset + 4)

        var partitionOffset = firstPartitionOffset
        for (index, partition) in partitions.enumerated() {
            iso.write(UInt32(partitionOffset >> 2), atAddress: entriesOffset + index * 8)
            iso.write(UInt32(partition.type), atAddress: entriesOffset + index * 8 + 4)

            let built = partitionImage(payload: partition.payload)
            iso.write(built.image, atAddress: partitionOffset)
            partitionOffset += built.image.length

            if partition.type == 0 {
                expected.ticket = built.ticket
                expected.tmd = built.tmd
                expected.cert = built.cert
                expected.h3 = built.h3
            }
        }

        payload = []
        return (iso, expected)
    }

    /// Ticket + partition header + TMD + cert chain + H3 table + encrypted clusters.
    private static func partitionImage(
        payload: [UInt8]
    ) -> (image: GoDData, ticket: [UInt8], tmd: [UInt8], cert: [UInt8], h3: [UInt8]) {
        let (encrypted, h3Table) = encryptPayload(payload)

        let ticket = ticketData()
        let cert = (0..<certLength).map { UInt8(0xC0 | ($0 & 0x0F)) }
        let tmd = tmdData(contentSize: encrypted.count, contentHash: SHA1.hash(h3Table))

        let certOffset = (tmdOffsetInPartition + tmd.count).aligned(to: 0x20)
        let h3Offset = (certOffset + cert.count).aligned(to: 0x20)
        let dataOffset = (h3Offset + h3TableSize).aligned(to: clusterSize)

        let image = GoDData(length: 0, byteOrder: .big)
        image.write(GoDData(byteStream: ticket, byteOrder: .big), atAddress: 0)

        image.write(UInt32(tmd.count), atAddress: partitionHeaderOffset)
        image.write(UInt32(tmdOffsetInPartition >> 2), atAddress: partitionHeaderOffset + 0x04)
        image.write(UInt32(cert.count), atAddress: partitionHeaderOffset + 0x08)
        image.write(UInt32(certOffset >> 2), atAddress: partitionHeaderOffset + 0x0C)
        image.write(UInt32(h3Offset >> 2), atAddress: partitionHeaderOffset + 0x10)
        image.write(UInt32(dataOffset >> 2), atAddress: partitionHeaderOffset + 0x14)
        image.write(UInt32(encrypted.count >> 2), atAddress: partitionHeaderOffset + 0x18)

        image.write(GoDData(byteStream: tmd, byteOrder: .big), atAddress: tmdOffsetInPartition)
        image.write(GoDData(byteStream: cert, byteOrder: .big), atAddress: certOffset)
        image.write(GoDData(byteStream: h3Table, byteOrder: .big), atAddress: h3Offset)
        image.write(GoDData(byteStream: encrypted, byteOrder: .big), atAddress: dataOffset)

        return (image, ticket, tmd, cert, h3Table)
    }

    private static func ticketData() -> [UInt8] {
        let ticket = GoDData(length: ticketLength, byteOrder: .big)
        // Signature area: nonzero, so a fakesign is visible in a diff.
        for i in 0x04..<0x104 { ticket.write(UInt8((i &* 3) & 0xFF), atAddress: i) }
        ticket.write("Root-CA00000001-XS00000003".data(format: .utf8), atAddress: 0x140)

        var iv = titleID
        iv.append(contentsOf: [UInt8](repeating: 0, count: 8))
        let encryptedTitleKey = AES128CBC.encrypt(bytes: titleKey, key: commonKey, iv: iv)
        ticket.write(GoDData(byteStream: encryptedTitleKey, byteOrder: .big), atAddress: 0x1BF)
        ticket.write(GoDData(byteStream: titleID, byteOrder: .big), atAddress: 0x1DC)
        return ticket.rawBytes
    }

    private static func tmdData(contentSize: Int, contentHash: [UInt8]) -> [UInt8] {
        let tmd = GoDData(length: tmdLength, byteOrder: .big)
        for i in 0x04..<0x104 { tmd.write(UInt8((i &* 5) & 0xFF), atAddress: i) }
        tmd.write("Root-CA00000001-CP00000004".data(format: .utf8), atAddress: 0x140)
        tmd.write(GoDData(byteStream: titleID, byteOrder: .big), atAddress: 0x18C)
        tmd.write(UInt16(1), atAddress: 0x1DE)          // one content
        tmd.write(UInt32(0), atAddress: 0x1E4)          // content id
        tmd.write(UInt16(0), atAddress: 0x1E8)          // content index
        tmd.write(UInt16(1), atAddress: 0x1EA)          // type: normal
        tmd.write(UInt32(0), atAddress: 0x1EC)          // content size, high word
        tmd.write(UInt32(contentSize), atAddress: 0x1F0)
        tmd.write(GoDData(byteStream: contentHash, byteOrder: .big), atAddress: 0x1F4)
        return tmd.rawBytes
    }

    // MARK: - Cluster encryption (independent of WiiCrypto)

    /// Encrypt a decrypted partition payload into whole clusters and build the
    /// matching H3 table. The payload is zero-padded to a whole cluster; unlike
    /// the production writer this does *not* pad up to a whole 64-cluster group,
    /// which is what keeps the fixtures cheap.
    public static func encryptPayload(_ payload: [UInt8]) -> (encrypted: [UInt8], h3Table: [UInt8]) {
        var user = payload
        if user.count % userDataPerCluster != 0 || user.isEmpty {
            let clusters = max(1, (user.count + userDataPerCluster - 1) / userDataPerCluster)
            user.append(contentsOf: [UInt8](repeating: 0, count: clusters * userDataPerCluster - user.count))
        }
        let clusterCount = user.count / userDataPerCluster

        // H0: SHA-1 of each 0x400-byte chunk of a cluster's user data.
        var h0 = [[[UInt8]]]()
        for c in 0..<clusterCount {
            let base = c * userDataPerCluster
            h0.append((0..<h0PerCluster).map { i in
                SHA1.hash(Array(user[(base + i * 0x400)..<(base + (i + 1) * 0x400)]))
            })
        }
        // H1: SHA-1 of a cluster's 31 H0 hashes.
        let h1 = (0..<clusterCount).map { SHA1.hash(h0[$0].flatMap { $0 }) }
        // H2: SHA-1 of a subgroup's 8 H1 hashes (absent clusters count as zeros).
        let subgroupCount = (clusterCount + clustersPerSubgroup - 1) / clustersPerSubgroup
        let h2 = (0..<subgroupCount).map { sg in
            SHA1.hash(table(of: h1, base: sg * clustersPerSubgroup, count: clustersPerSubgroup).flatMap { $0 })
        }
        // H3: SHA-1 of a group's 8 H2 hashes.
        let groupCount = (subgroupCount + subgroupsPerGroup - 1) / subgroupsPerGroup
        let h3 = (0..<groupCount).map { g in
            SHA1.hash(table(of: h2, base: g * subgroupsPerGroup, count: subgroupsPerGroup).flatMap { $0 })
        }

        var h3Table = [UInt8](repeating: 0, count: h3TableSize)
        for g in 0..<groupCount {
            h3Table.replaceSubrange((g * 20)..<(g * 20 + 20), with: h3[g])
        }

        var encrypted = [UInt8]()
        encrypted.reserveCapacity(clusterCount * clusterSize)
        for c in 0..<clusterCount {
            let subgroup = c / clustersPerSubgroup
            let group = c / (clustersPerSubgroup * subgroupsPerGroup)

            var hashBlock = [UInt8](repeating: 0, count: hashBlockSize)
            for (i, hash) in h0[c].enumerated() {
                hashBlock.replaceSubrange((h0TableOffset + i * 20)..<(h0TableOffset + i * 20 + 20), with: hash)
            }
            let h1Slots = table(of: h1, base: subgroup * clustersPerSubgroup, count: clustersPerSubgroup)
            for (i, hash) in h1Slots.enumerated() {
                hashBlock.replaceSubrange((h1TableOffset + i * 20)..<(h1TableOffset + i * 20 + 20), with: hash)
            }
            let h2Slots = table(of: h2, base: group * subgroupsPerGroup, count: subgroupsPerGroup)
            for (i, hash) in h2Slots.enumerated() {
                hashBlock.replaceSubrange((h2TableOffset + i * 20)..<(h2TableOffset + i * 20 + 20), with: hash)
            }

            // The hash block is encrypted with a zero IV; the user data's IV is
            // taken from the *ciphertext* of that hash block at 0x3D0.
            let encryptedHashBlock = AES128CBC.encrypt(
                bytes: hashBlock,
                key: titleKey,
                iv: [UInt8](repeating: 0, count: 16)
            )
            let userIV = Array(encryptedHashBlock[userIVOffset..<(userIVOffset + 16)])
            let base = c * userDataPerCluster
            let encryptedUser = AES128CBC.encrypt(
                bytes: Array(user[base..<(base + userDataPerCluster)]),
                key: titleKey,
                iv: userIV
            )
            encrypted.append(contentsOf: encryptedHashBlock)
            encrypted.append(contentsOf: encryptedUser)
        }

        return (encrypted, h3Table)
    }

    /// `count` hashes starting at `base`, zero-filled past the end of `hashes`.
    private static func table(of hashes: [[UInt8]], base: Int, count: Int) -> [[UInt8]] {
        (0..<count).map { i in
            let index = base + i
            return index < hashes.count ? hashes[index] : [UInt8](repeating: 0, count: 20)
        }
    }

    // MARK: - DATA partition payload

    /// Lay out a minimal but complete game filesystem: boot.bin, bi2, apploader,
    /// DOL, FST and two user files (one of them nested). boot.bin offsets and FST
    /// file offsets are stored >> 2, as Wii discs do.
    private static func dataPartitionPayload(
        dolphinEngine: DolphinEngine
    ) -> (payload: [UInt8], expected: Expected) {
        let systemFiles = dolphinEngine.data.systemFiles
        let payload = GoDData(length: 0, byteOrder: .big)

        // bi2.bin
        let bi2 = GoDData(length: 0x2000, byteOrder: .big)
        bi2.write(UInt32(0), atAddress: 0)               // debug monitor size
        bi2.write(UInt32(0x01800000), atAddress: 4)      // simulated memory size
        bi2.write(UInt32(1), atAddress: 0x18)            // country code
        payload.write(bi2, atAddress: systemFiles.bi2DataOffset)

        // apploader.img: 0x20-byte header + 0x40 bytes of code, no trailer.
        let apploaderCode = (0..<0x40).map { UInt8(0xA0 | ($0 & 0x0F)) }
        let apploader = GoDData(length: 0x20, byteOrder: .big)
        apploader.write("2004/09/22".data(format: .utf8), atAddress: 0)
        apploader.write(UInt32(0x81200000), atAddress: 0x10)
        apploader.write(UInt32(apploaderCode.count), atAddress: 0x14)
        apploader.write(UInt32(0), atAddress: 0x18)      // trailer size
        apploader.append(GoDData(byteStream: apploaderCode, byteOrder: .big))
        payload.write(apploader, atAddress: systemFiles.apploaderOffset)

        // main.dol: 0x100-byte header plus a single text section.
        let dolText = (0..<0x100).map { UInt8(($0 &* 11) & 0xFF) }
        let dol = GoDData(length: 0x100, byteOrder: .big)
        dol.write(UInt32(0x100), atAddress: 0x00)        // text section 0 offset
        dol.write(UInt32(0x80003100), atAddress: 0x48)   // text section 0 RAM address
        dol.write(UInt32(dolText.count), atAddress: 0x90) // text section 0 size
        dol.write(UInt32(0x80003100), atAddress: 0xE0)   // entry point
        dol.append(GoDData(byteStream: dolText, byteOrder: .big))

        let dolAlignment = max(systemFiles.dolOffsetAlignment, 1)
        let dolOffset = (systemFiles.apploaderOffset + apploader.length).aligned(to: dolAlignment)
        payload.write(dol, atAddress: dolOffset)

        // FST: root, /files/a.bin, /files/sub, /files/sub/b.bin.
        let fileA = (0..<0x40).map { UInt8(($0 &* 3 &+ 1) & 0xFF) }
        let fileB = (0..<0x20).map { UInt8(($0 &* 5 &+ 2) & 0xFF) }

        let fstOffset = (dolOffset + dol.length).aligned(to: 4)
        let stringTable = GoDData(length: 0, byteOrder: .big)
        var nameOffsets = [String: Int]()
        for name in ["a.bin", "sub", "b.bin"] {
            nameOffsets[name] = stringTable.length
            stringTable.appendString(name, format: .utf8, includeTerminator: true)
        }
        let entryCount = 4
        let fstSize = entryCount * 12 + stringTable.length
        let userOffset = (fstOffset + fstSize).aligned(to: dolphinEngine.data.userFiles.userOffsetAlignment)

        /// An entry's first word packs the type byte and a 24-bit name offset.
        func typeAndName(isDirectory: Bool, nameOffset: Int) -> UInt32 {
            (isDirectory ? UInt32(0x01000000) : 0) | UInt32(nameOffset)
        }

        let fst = GoDData(length: entryCount * 12, byteOrder: .big)
        // Root.
        fst.write(typeAndName(isDirectory: true, nameOffset: 0), atAddress: 0)
        fst.write(UInt32(entryCount), atAddress: 8)
        // /files/a.bin
        fst.write(typeAndName(isDirectory: false, nameOffset: nameOffsets["a.bin"]!), atAddress: 12)
        fst.write(UInt32(userOffset >> 2), atAddress: 16)
        fst.write(UInt32(fileA.count), atAddress: 20)
        // /files/sub
        fst.write(typeAndName(isDirectory: true, nameOffset: nameOffsets["sub"]!), atAddress: 24)
        fst.write(UInt32(0), atAddress: 28)              // parent entry index
        fst.write(UInt32(4), atAddress: 32)              // first entry outside this folder
        // /files/sub/b.bin
        fst.write(typeAndName(isDirectory: false, nameOffset: nameOffsets["b.bin"]!), atAddress: 36)
        fst.write(UInt32((userOffset + fileA.count) >> 2), atAddress: 40)
        fst.write(UInt32(fileB.count), atAddress: 44)
        fst.append(stringTable)

        payload.write(fst, atAddress: fstOffset)
        payload.write(GoDData(byteStream: fileA, byteOrder: .big), atAddress: userOffset)
        payload.write(GoDData(byteStream: fileB, byteOrder: .big), atAddress: userOffset + fileA.count)

        // boot.bin last: it records the layout above, with offsets >> 2.
        let boot = GoDData(length: bootLength, byteOrder: .big)
        boot.write(gameID.data(format: .utf8), atAddress: 0)
        boot.write("01".data(format: .utf8), atAddress: 4)
        boot.write(wiiMagic, atAddress: wiiMagicOffset)
        boot.write("GoD Tool synthetic Wii disc".data(format: .utf8), atAddress: 0x20)
        boot.write(UInt32(dolOffset >> 2), atAddress: bootDolOffset)
        boot.write(UInt32(fstOffset >> 2), atAddress: bootFSTOffset)
        boot.write(UInt32(fstSize >> 2), atAddress: bootFSTSize)
        boot.write(UInt32(fstSize >> 2), atAddress: bootMaxFSTSize)
        boot.write(UInt32(userOffset >> 2), atAddress: bootUserDataOffset)
        boot.write(UInt32((fileA.count + fileB.count) >> 2), atAddress: bootUserDataLength)
        payload.write(boot, atAddress: systemFiles.bootDataOffset)

        var expected = Expected()
        expected.boot = boot.rawBytes
        expected.bi2 = bi2.rawBytes
        expected.apploader = apploader.rawBytes
        expected.dol = dol.rawBytes
        expected.fst = fst.rawBytes
        expected.files = ["/files/a.bin": fileA, "/files/sub/b.bin": fileB]
        expected.dolOffset = dolOffset
        expected.fstOffset = fstOffset
        expected.userOffset = userOffset

        return (payload.rawBytes, expected)
    }
}
