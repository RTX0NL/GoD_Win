//
//  WiiEncryptedPartitionDataView.swift
//
//  Random-access read over a Wii partition's *encrypted* data, hashing and
//  encrypting each 2 MiB group on demand.
//
//  The mirror of `WiiDecryptedPartitionView`, which does the same for reads
//  going the other way. Both exist because the unit of work — one group, 64
//  clusters — is far larger than the unit of access, so the decoded bytes have
//  to be cached for consecutive reads inside one group.
//
//  Why a view at all: `WiiPartition.encrypt` used to build the whole
//  partition's encrypted bytes in memory, which for a Wii disc is about
//  4.7 GB, on top of the 4.4 GB of decrypted data it was built from and the
//  copies each wrapper made. `FileHandleAccess.write` pulls a `GoDReadable` in
//  8 MB windows, so composing views instead costs a couple of groups.
//
//  H3 is not produced here. It lives in the partition's unencrypted header,
//  ahead of the data it covers, so a sequential writer needs the whole table
//  before the first encrypted byte — `WiiCrypto.h3Table` does that in its own
//  SHA-only pass.
//

import GoDFoundation

public final class WiiEncryptedPartitionDataView: GoDReadable {

    public let byteOrder: ByteOrder = .big
    public let length: Int

    private let decrypted: GoDReadable
    private let titleKey: [UInt8]

    /// Encrypted groups, most recently used last. A group is 2 MiB, so the
    /// default keeps 8 MB — enough that the 8 MB windows a file copy uses
    /// never ask for a group twice.
    private var cache: [(group: Int, bytes: [UInt8])] = []
    private let maxCachedGroups: Int

    /// - Parameters:
    ///   - decryptedUserData: the partition's plaintext payload, itself
    ///     usually a lazy source. Read one group at a time and zero-padded at
    ///     the end.
    ///   - titleKey: 16-byte decrypted title key.
    public init(
        decryptedUserData: GoDReadable,
        titleKey: [UInt8],
        maxCachedGroups: Int = 4
    ) {
        self.decrypted = decryptedUserData
        self.titleKey = titleKey
        self.length = WiiCrypto.encryptedLength(forDecryptedLength: decryptedUserData.length)
        self.maxCachedGroups = max(1, maxCachedGroups)
    }

    public func read(atAddress address: UInt, length readLength: UInt) -> GoDData? {
        let start = Int(address)
        let end = start + Int(readLength)
        guard start >= 0, end <= self.length, readLength > 0 else { return nil }

        let groupSize = WiiCrypto.clustersPerGroup * WiiCrypto.clusterSize
        var out = [UInt8]()
        out.reserveCapacity(Int(readLength))
        var cursor = start
        while cursor < end {
            let groupIndex = cursor / groupSize
            let offsetInGroup = cursor % groupSize
            guard let group = encryptedGroup(groupIndex) else { return nil }
            let count = min(groupSize - offsetInGroup, end - cursor)
            guard offsetInGroup + count <= group.count else { return nil }
            out.append(contentsOf: group[offsetInGroup..<(offsetInGroup + count)])
            cursor += count
        }
        return GoDData(byteStream: out, byteOrder: .big)
    }

    private func encryptedGroup(_ index: Int) -> [UInt8]? {
        if let hit = cache.firstIndex(where: { $0.group == index }) {
            let entry = cache.remove(at: hit)
            cache.append(entry)
            return entry.bytes
        }
        let window = WiiCrypto.decryptedGroup(index, of: decrypted)
        let bytes = WiiCrypto.encryptGroup(
            userData: window,
            hashes: WiiCrypto.groupHashes(forUserData: window),
            titleKey: titleKey
        )
        cache.append((group: index, bytes: bytes))
        while cache.count > maxCachedGroups { cache.removeFirst() }
        return bytes
    }
}
