import Foundation
import GoDFoundation

/// Wii disc-specific cryptographic operations.
/// Handles title key decryption, data cluster encryption/decryption,
/// hash chain calculation, and ticket fakesigning.
public struct WiiCrypto {

    // MARK: - Cluster / hash-tree geometry

    /// Size of one encrypted cluster (aka "group" in some call sites): 0x8000 bytes.
    public static let clusterSize = 0x8000
    /// Size of a cluster's hash block prefix.
    public static let hashBlockSize = 0x400
    /// Size of a cluster's user (payload) data.
    public static let userDataPerCluster = 0x7C00
    /// Number of 0x400-byte H0 chunks per cluster (0x7C00 / 0x400 = 31).
    public static let h0PerCluster = 31
    public static let clustersPerSubgroup = 8
    public static let subgroupsPerGroup = 8
    public static let clustersPerGroup = 64
    public static let h3TableSize = 0x18000

    // Hash-block sub-table offsets (per Wiibrew "Wii disc").
    private static let h0Offset = 0x000   // 31 * 20 = 0x26C
    private static let h1Offset = 0x280   // 8 * 20 = 0xA0
    private static let h2Offset = 0x340   // 8 * 20 = 0xA0
    private static let userIVOffset = 0x3D0

    // MARK: - Title Key

    /// Decrypt the title key from a ticket using the Wii common key.
    /// - Parameters:
    ///   - ticketData: Raw ticket data (needs at least 0x1E4 bytes so the title ID at 0x1DC..0x1E4 is present)
    ///   - commonKey: 16-byte Wii common key
    /// - Returns: 16-byte decrypted title key, or nil if the ticket is truncated.
    public static func decryptTitleKey(ticketData: GoDData, commonKey: [UInt8]) -> [UInt8]? {
        // Encrypted title key at offset 0x1BF (16 bytes)
        guard let encryptedKey = ticketData.read(atAddress: 0x1BF, length: 16)?.rawBytes else {
            return nil
        }
        // IV is the title ID (8 bytes at offset 0x1DC) padded with 8 zero bytes
        guard var iv = ticketData.read(atAddress: 0x1DC, length: 8)?.rawBytes else {
            return nil
        }
        iv.append(contentsOf: [UInt8](repeating: 0, count: 8))

        return AES128CBC.decrypt(bytes: encryptedKey, key: commonKey, iv: iv)
    }

    // MARK: - Cluster Decryption

    /// Decrypt a single 0x8000-byte cluster.
    /// - Parameters:
    ///   - groupData: Exactly 0x8000 bytes of encrypted cluster data
    ///   - titleKey: 16-byte decrypted title key
    /// - Returns: Tuple of (decrypted hash block 0x400 bytes, decrypted user data 0x7C00 bytes),
    ///            or nil if the input is truncated.
    public static func decryptGroup(groupData: GoDData, titleKey: [UInt8]) -> (hashBlock: GoDData, userData: GoDData)? {
        let zeroIV = [UInt8](repeating: 0, count: 16)

        // IV for the user data comes from the ENCRYPTED (ciphertext) hash block at 0x3D0,
        // read BEFORE the hash block is decrypted.
        guard let dataIV = groupData.read(atAddress: userIVOffset, length: 16)?.rawBytes else {
            return nil
        }

        // Decrypt hash block (0x000-0x3FF) with IV = all zeros
        guard let encryptedHash = groupData.read(atAddress: 0, length: hashBlockSize) else {
            return nil
        }
        let decryptedHash = AES128CBC.decrypt(data: encryptedHash, key: titleKey, iv: zeroIV)

        // Decrypt user data (0x400-0x7FFF)
        guard let encryptedData = groupData.read(atAddress: UInt(hashBlockSize), length: UInt(userDataPerCluster)) else {
            return nil
        }
        let decryptedData = AES128CBC.decrypt(data: encryptedData, key: titleKey, iv: dataIV)

        return (hashBlock: decryptedHash, userData: decryptedData)
    }

    // MARK: - Cluster Encryption

    /// Encrypt a single cluster given its precomputed H1/H2 hash tables.
    /// - Parameters:
    ///   - userData: 0x7C00 bytes of plaintext user data
    ///   - h1Hashes: the 8 H1 hashes of this cluster's subgroup (each 20 bytes)
    ///   - h2Hashes: the 8 H2 hashes of this cluster's group (each 20 bytes)
    ///   - subgroupIndex: (unused; retained for source compatibility)
    ///   - groupIndex: (unused; retained for source compatibility)
    ///   - titleKey: 16-byte decrypted title key
    /// - Returns: 0x8000 bytes of encrypted cluster data
    public static func encryptGroup(
        userData: GoDData,
        h1Hashes: [[UInt8]],
        h2Hashes: [[UInt8]],
        subgroupIndex: Int,
        groupIndex: Int,
        titleKey: [UInt8]
    ) -> GoDData {
        let userBytes = userData.rawBytes
        var h0 = [[UInt8]]()
        h0.reserveCapacity(h0PerCluster)
        for i in 0..<h0PerCluster {
            let chunkStart = i * 0x400
            let chunkEnd = min(chunkStart + 0x400, userBytes.count)
            let chunk = chunkStart < userBytes.count ? Array(userBytes[chunkStart..<chunkEnd]) : [UInt8]()
            h0.append(SHA1.hash(chunk))
        }

        let clusterBytes = buildEncryptedCluster(
            userBytes: userBytes,
            h0Hashes: h0,
            h1Hashes: h1Hashes,
            h2Hashes: h2Hashes,
            titleKey: titleKey
        )
        return GoDData(byteStream: clusterBytes, byteOrder: .big)
    }

    /// Lay one cluster's hash tables into its 0x400-byte hash block.
    ///
    /// Separate from encryption because a format may need to *edit* the
    /// block between the two steps: WIA/RVZ carries hash exceptions, which
    /// override individual hashes after they are recomputed and before they
    /// are encrypted.
    public static func hashBlock(
        h0Hashes: [[UInt8]],
        h1Hashes: [[UInt8]],
        h2Hashes: [[UInt8]]
    ) -> [UInt8] {
        var block = [UInt8](repeating: 0, count: hashBlockSize)
        // H0 table @ 0x000: 31 entries of 20 bytes
        for i in 0..<min(h0Hashes.count, h0PerCluster) {
            for j in 0..<20 { block[h0Offset + i * 20 + j] = h0Hashes[i][j] }
        }
        // H1 table @ 0x280: 8 entries of 20 bytes
        for i in 0..<min(h1Hashes.count, clustersPerSubgroup) {
            for j in 0..<20 { block[h1Offset + i * 20 + j] = h1Hashes[i][j] }
        }
        // H2 table @ 0x340: 8 entries of 20 bytes
        for i in 0..<min(h2Hashes.count, subgroupsPerGroup) {
            for j in 0..<20 { block[h2Offset + i * 20 + j] = h2Hashes[i][j] }
        }
        return block
    }

    /// Encrypt one 0x8000-byte cluster from an already-built hash block.
    public static func encryptCluster(
        userBytes: [UInt8],
        hashBlock block: [UInt8],
        titleKey: [UInt8]
    ) -> [UInt8] {
        let zeroIV = [UInt8](repeating: 0, count: 16)
        // Encrypt hash block with IV = all zeros.
        let encryptedHash = AES128CBC.encrypt(bytes: block, key: titleKey, iv: zeroIV)

        // IV for user data is bytes 0x3D0-0x3DF of the ENCRYPTED (ciphertext) hash block.
        let dataIV = Array(encryptedHash[userIVOffset..<(userIVOffset + 16)])

        // User data may be shorter than a full cluster (final padded cluster is zero-filled to 0x7C00).
        var userPadded = userBytes
        if userPadded.count < userDataPerCluster {
            userPadded.append(contentsOf: [UInt8](repeating: 0, count: userDataPerCluster - userPadded.count))
        } else if userPadded.count > userDataPerCluster {
            userPadded = Array(userPadded[0..<userDataPerCluster])
        }
        let encryptedUser = AES128CBC.encrypt(bytes: userPadded, key: titleKey, iv: dataIV)

        return encryptedHash + encryptedUser
    }

    /// Build and encrypt one 0x8000-byte cluster from its user data and hash tables.
    private static func buildEncryptedCluster(
        userBytes: [UInt8],
        h0Hashes: [[UInt8]],
        h1Hashes: [[UInt8]],
        h2Hashes: [[UInt8]],
        titleKey: [UInt8]
    ) -> [UInt8] {
        encryptCluster(
            userBytes: userBytes,
            hashBlock: hashBlock(h0Hashes: h0Hashes, h1Hashes: h1Hashes, h2Hashes: h2Hashes),
            titleKey: titleKey
        )
    }

    // MARK: - Group encryption

    /// Encrypt one 64-cluster group, applying hash overrides before
    /// encryption.
    ///
    /// H3 is deliberately not computed: on a real disc it lives in the
    /// partition's *unencrypted* header region, which a container like
    /// WIA/RVZ stores verbatim rather than stripping. Recomputing it here
    /// would overwrite the disc's own value with one derived from hashes the
    /// exceptions may have just changed.
    ///
    /// - Parameters:
    ///   - decryptedUserData: `clustersPerGroup × userDataPerCluster` bytes
    ///     (0x1F0000), zero-padded by the caller when the group is short.
    ///   - hashOverrides: `(offset, 20-byte hash)` pairs. `offset / 0x400`
    ///     selects the cluster and `offset % 0x400` the byte within its hash
    ///     block, which is how WIA/RVZ addresses a group's hash region.
    /// - Returns: `clustersPerGroup × clusterSize` bytes (0x200000).
    public static func encryptGroup(
        decryptedUserData: [UInt8],
        titleKey: [UInt8],
        hashOverrides: [(offset: Int, hash: [UInt8])] = []
    ) -> [UInt8] {
        encryptGroup(
            userData: decryptedUserData,
            hashes: groupHashes(forUserData: decryptedUserData),
            titleKey: titleKey,
            hashOverrides: hashOverrides
        )
    }

    /// The hash tables for one group of decrypted user data.
    ///
    /// Split out because three callers need different parts of the same walk:
    /// encrypting a group wants H0, H1 and H2, building a partition's H3 table
    /// wants only H3, and `encryptPartitionData` wants all of it. One function
    /// means they cannot disagree about how a hash is derived.
    public struct GroupHashes {
        /// 31 hashes per cluster, 64 clusters.
        public var h0: [[[UInt8]]]
        /// One per cluster: the hash of that cluster's H0 table.
        public var h1: [[UInt8]]
        /// One per subgroup of 8 clusters.
        public var h2: [[UInt8]]
        /// This group's H3 entry: the hash of its 8 H2.
        public var h3: [UInt8]
    }

    /// - Parameter userData: exactly `clustersPerGroup × userDataPerCluster`
    ///   bytes. A short final group is zero-padded by the caller, because the
    ///   hashes of the absent clusters still appear in the hash blocks of the
    ///   clusters that exist.
    public static func groupHashes(forUserData userData: [UInt8]) -> GroupHashes {
        var user = userData
        let groupUserSize = clustersPerGroup * userDataPerCluster
        if user.count < groupUserSize {
            user.append(contentsOf: [UInt8](repeating: 0, count: groupUserSize - user.count))
        } else if user.count > groupUserSize {
            user = Array(user[0..<groupUserSize])
        }

        var h0 = [[[UInt8]]](repeating: [], count: clustersPerGroup)
        for c in 0..<clustersPerGroup {
            let base = c * userDataPerCluster
            var hashes = [[UInt8]]()
            hashes.reserveCapacity(h0PerCluster)
            for i in 0..<h0PerCluster {
                let s = base + i * 0x400
                hashes.append(SHA1.hash(Array(user[s..<(s + 0x400)])))
            }
            h0[c] = hashes
        }
        let h1 = (0..<clustersPerGroup).map { SHA1.hash(h0[$0].flatMap { $0 }) }
        let h2 = (0..<subgroupsPerGroup).map { sg -> [UInt8] in
            var concat = [UInt8]()
            concat.reserveCapacity(clustersPerSubgroup * 20)
            for k in 0..<clustersPerSubgroup {
                concat.append(contentsOf: h1[sg * clustersPerSubgroup + k])
            }
            return SHA1.hash(concat)
        }
        return GroupHashes(h0: h0, h1: h1, h2: h2, h3: SHA1.hash(h2.flatMap { $0 }))
    }

    /// Groups a decrypted payload occupies once padded out.
    ///
    /// Empty data still occupies one group, matching what the whole-payload
    /// encrypt has always produced.
    public static func groupCount(forDecryptedLength length: Int) -> Int {
        let groupUserSize = clustersPerGroup * userDataPerCluster
        guard length > 0 else { return 1 }
        return (length + groupUserSize - 1) / groupUserSize
    }

    public static func encryptedLength(forDecryptedLength length: Int) -> Int {
        groupCount(forDecryptedLength: length) * clustersPerGroup * clusterSize
    }

    /// One group's worth of decrypted data, zero-padded if the source stops
    /// partway through.
    public static func decryptedGroup(_ index: Int, of data: GoDReadable) -> [UInt8] {
        let groupUserSize = clustersPerGroup * userDataPerCluster
        var window = [UInt8](repeating: 0, count: groupUserSize)
        let start = index * groupUserSize
        let available = min(groupUserSize, max(0, data.length - start))
        if available > 0, let chunk = data.read(atAddress: start, length: available) {
            window.replaceSubrange(0..<available, with: chunk.rawBytes)
        }
        return window
    }

    /// Build a partition's H3 table without encrypting anything.
    ///
    /// A separate pass because of where H3 lives: the partition's unencrypted
    /// header, *before* the data it covers. A sequential writer therefore
    /// needs the whole table before the first encrypted byte, which rules out
    /// producing it as a side effect of encrypting. This walk is SHA only —
    /// no AES — and lets the encryption itself stay lazy.
    public static func h3Table(forDecryptedUserData data: GoDReadable) -> [UInt8] {
        var table = [UInt8](repeating: 0, count: h3TableSize)
        for group in 0..<groupCount(forDecryptedLength: data.length) {
            let offset = group * 20
            guard offset + 20 <= h3TableSize else { break }
            let h3 = groupHashes(forUserData: decryptedGroup(group, of: data)).h3
            for j in 0..<20 { table[offset + j] = h3[j] }
        }
        return table
    }

    /// Encrypt one group from hashes already computed for it.
    ///
    /// The overrides are applied across the group's 64 hash blocks as one
    /// contiguous region, because that is how WIA/RVZ addresses them.
    public static func encryptGroup(
        userData: [UInt8],
        hashes: GroupHashes,
        titleKey: [UInt8],
        hashOverrides: [(offset: Int, hash: [UInt8])] = []
    ) -> [UInt8] {
        var user = userData
        let groupUserSize = clustersPerGroup * userDataPerCluster
        if user.count < groupUserSize {
            user.append(contentsOf: [UInt8](repeating: 0, count: groupUserSize - user.count))
        } else if user.count > groupUserSize {
            user = Array(user[0..<groupUserSize])
        }

        var blocks = [[UInt8]]()
        blocks.reserveCapacity(clustersPerGroup)
        for c in 0..<clustersPerGroup {
            let subgroup = c / clustersPerSubgroup
            let h1Table = (0..<clustersPerSubgroup).map { hashes.h1[subgroup * clustersPerSubgroup + $0] }
            blocks.append(hashBlock(h0Hashes: hashes.h0[c], h1Hashes: h1Table, h2Hashes: hashes.h2))
        }
        for override in hashOverrides {
            let cluster = override.offset / hashBlockSize
            let byte = override.offset % hashBlockSize
            guard cluster < clustersPerGroup, byte + 20 <= hashBlockSize else { continue }
            for j in 0..<min(20, override.hash.count) {
                blocks[cluster][byte + j] = override.hash[j]
            }
        }

        var out = [UInt8]()
        out.reserveCapacity(clustersPerGroup * clusterSize)
        for c in 0..<clustersPerGroup {
            let base = c * userDataPerCluster
            out.append(contentsOf: encryptCluster(
                userBytes: Array(user[base..<(base + userDataPerCluster)]),
                hashBlock: blocks[c],
                titleKey: titleKey
            ))
        }
        return out
    }

    /// Encrypt an entire partition's decrypted user data, building the full
    /// H0/H1/H2/H3 hash tree.
    ///
    /// Costs the size of the partition twice over, so the streaming path —
    /// `h3Table` plus `WiiEncryptedPartitionDataView` — is what a real rebuild
    /// uses. Kept for tests and small payloads, and still one hash pass: it
    /// shares `groupHashes` with everything else.
    ///
    /// - Returns: the concatenated encrypted clusters and a freshly-built H3
    ///   table (0x18000 bytes).
    public static func encryptPartitionData(
        decryptedUserData: [UInt8],
        titleKey: [UInt8]
    ) -> (encrypted: [UInt8], h3Table: [UInt8]) {
        let source = GoDData(byteStream: decryptedUserData, byteOrder: .big)
        let count = groupCount(forDecryptedLength: decryptedUserData.count)
        var encrypted = [UInt8]()
        encrypted.reserveCapacity(count * clustersPerGroup * clusterSize)
        var table = [UInt8](repeating: 0, count: h3TableSize)
        for group in 0..<count {
            let window = decryptedGroup(group, of: source)
            let hashes = groupHashes(forUserData: window)
            encrypted.append(contentsOf: encryptGroup(
                userData: window, hashes: hashes, titleKey: titleKey
            ))
            let offset = group * 20
            if offset + 20 <= h3TableSize {
                for j in 0..<20 { table[offset + j] = hashes.h3[j] }
            }
        }
        return (encrypted: encrypted, h3Table: table)
    }


    // MARK: - Hash Chain Calculation (standalone helpers)

    /// Calculate H0 hashes for a subgroup (8 clusters of user data).
    /// Each H0 hash is SHA-1 of the corresponding 0x400-byte section of user data.
    /// - Parameter subgroupBlocks: Array of user data blocks (each 0x7C00 bytes)
    /// - Returns: Array of arrays, each containing 31 H0 hashes (20 bytes each)
    public static func calculateH0Hashes(subgroupBlocks: [GoDData]) -> [[[UInt8]]] {
        subgroupBlocks.map { block in
            let bytes = block.rawBytes
            return (0..<h0PerCluster).map { i in
                let start = i * 0x400
                let end = min(start + 0x400, bytes.count)
                return SHA1.hash(start < bytes.count ? Array(bytes[start..<end]) : [UInt8]())
            }
        }
    }

    /// Calculate H1 hash for a cluster from its H0 hashes.
    /// H1 = SHA-1(all 31 H0 hashes concatenated = 620 bytes)
    public static func calculateH1Hash(h0Hashes: [[UInt8]]) -> [UInt8] {
        SHA1.hash(h0Hashes.flatMap { $0 })
    }

    /// Calculate H2 hash from 8 H1 hashes.
    /// H2 = SHA-1(8 H1 hashes concatenated = 160 bytes)
    public static func calculateH2Hash(h1Hashes: [[UInt8]]) -> [UInt8] {
        SHA1.hash(h1Hashes.flatMap { $0 })
    }

    /// Calculate H3 hash from 8 H2 hashes.
    /// H3 = SHA-1(8 H2 hashes concatenated = 160 bytes)
    public static func calculateH3Hash(h2Hashes: [[UInt8]]) -> [UInt8] {
        SHA1.hash(h2Hashes.flatMap { $0 })
    }

    // MARK: - Fakesigning

    /// Fakesign a ticket by brute-forcing a padding byte to make
    /// the SHA-1 hash of the ticket data start with 0x00.
    /// This is needed because the RSA signature won't be valid after modification.
    public static func fakesignTicket(_ ticketData: GoDData) -> GoDData {
        let result = GoDData(byteStream: ticketData.rawBytes, byteOrder: ticketData.byteOrder)
        // Zero out the RSA signature (offset 0x04, length 0x100)
        result.null(start: 0x04, length: 0x100)

        // Brute-force: try different values at a padding byte to get SHA-1 starting with 0x00
        // Use offset 0x248 (in the padding area near the end of the ticket)
        for attempt in 0..<65536 {
            result.write(UInt16(attempt), atAddress: 0x248)
            let hash = SHA1.hash(result)
            if hash.rawBytes[0] == 0x00 {
                return result
            }
        }

        // Fallback: return with zeroed signature (will work with most loaders)
        return result
    }

    /// Fakesign a TMD using the same approach as ticket fakesigning.
    public static func fakesignTMD(_ tmdData: GoDData) -> GoDData {
        let result = GoDData(byteStream: tmdData.rawBytes, byteOrder: tmdData.byteOrder)
        result.null(start: 0x04, length: 0x100)

        for attempt in 0..<65536 {
            result.write(UInt16(attempt), atAddress: 0x19A)
            let hash = SHA1.hash(result)
            if hash.rawBytes[0] == 0x00 {
                return result
            }
        }

        return result
    }
}
