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
    /// Clusters per subgroup.
    public static let clustersPerSubgroup = 8
    /// Subgroups per group.
    public static let subgroupsPerGroup = 8
    /// Clusters per group.
    public static let clustersPerGroup = 64
    /// Size of the H3 table.
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
        // Compute this cluster's 31 H0 hashes from its user data.
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
        return GoDData(byteStream: clusterBytes.map(Int.init), byteOrder: .big)
    }

    /// Build and encrypt one 0x8000-byte cluster from its user data and hash tables.
    private static func buildEncryptedCluster(
        userBytes: [UInt8],
        h0Hashes: [[UInt8]],
        h1Hashes: [[UInt8]],
        h2Hashes: [[UInt8]],
        titleKey: [UInt8]
    ) -> [UInt8] {
        // Build hash block (0x400 bytes)
        var hashBlock = [UInt8](repeating: 0, count: hashBlockSize)

        // H0 table @ 0x000: 31 entries of 20 bytes
        for i in 0..<min(h0Hashes.count, h0PerCluster) {
            for j in 0..<20 { hashBlock[h0Offset + i * 20 + j] = h0Hashes[i][j] }
        }
        // H1 table @ 0x280: 8 entries of 20 bytes
        for i in 0..<min(h1Hashes.count, clustersPerSubgroup) {
            for j in 0..<20 { hashBlock[h1Offset + i * 20 + j] = h1Hashes[i][j] }
        }
        // H2 table @ 0x340: 8 entries of 20 bytes
        for i in 0..<min(h2Hashes.count, subgroupsPerGroup) {
            for j in 0..<20 { hashBlock[h2Offset + i * 20 + j] = h2Hashes[i][j] }
        }

        let zeroIV = [UInt8](repeating: 0, count: 16)
        // Encrypt hash block with IV = all zeros.
        let encryptedHash = AES128CBC.encrypt(bytes: hashBlock, key: titleKey, iv: zeroIV)

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

    /// Encrypt an entire partition's decrypted user data, building the full H0/H1/H2/H3 hash tree.
    /// - Parameters:
    ///   - decryptedUserData: the concatenated plaintext user data (any length; zero-padded up to a whole number of 64-cluster groups)
    ///   - titleKey: 16-byte decrypted title key
    /// - Returns: the concatenated encrypted clusters and a freshly-built H3 table (0x18000 bytes).
    public static func encryptPartitionData(
        decryptedUserData: [UInt8],
        titleKey: [UInt8]
    ) -> (encrypted: [UInt8], h3Table: [UInt8]) {
        let groupUserSize = clustersPerGroup * userDataPerCluster

        // Pad up to a whole number of 64-cluster groups.
        var user = decryptedUserData
        let remainder = user.count % groupUserSize
        if remainder != 0 || user.isEmpty {
            let padTo = user.isEmpty ? groupUserSize : (user.count + (groupUserSize - remainder))
            user.append(contentsOf: [UInt8](repeating: 0, count: padTo - user.count))
        }

        let clusterCount = user.count / userDataPerCluster
        let groupCount = clusterCount / clustersPerGroup

        // 1) H0 per cluster (31 hashes each).
        var h0: [[[UInt8]]] = Array(repeating: [], count: clusterCount)
        for c in 0..<clusterCount {
            let base = c * userDataPerCluster
            var hashes = [[UInt8]]()
            hashes.reserveCapacity(h0PerCluster)
            for i in 0..<h0PerCluster {
                let s = base + i * 0x400
                hashes.append(SHA1.hash(Array(user[s..<(s + 0x400)])))
            }
            h0[c] = hashes
        }

        // 2) H1 per cluster = SHA1(concat of its 31 H0).
        var h1: [[UInt8]] = Array(repeating: [], count: clusterCount)
        for c in 0..<clusterCount {
            h1[c] = SHA1.hash(h0[c].flatMap { $0 })
        }

        // 3) H2 per subgroup = SHA1(concat of that subgroup's 8 H1).
        let subgroupCount = clusterCount / clustersPerSubgroup
        var h2: [[UInt8]] = Array(repeating: [], count: subgroupCount)
        for sg in 0..<subgroupCount {
            var concat = [UInt8]()
            concat.reserveCapacity(clustersPerSubgroup * 20)
            for k in 0..<clustersPerSubgroup {
                concat.append(contentsOf: h1[sg * clustersPerSubgroup + k])
            }
            h2[sg] = SHA1.hash(concat)
        }

        // 4) H3 per group = SHA1(concat of that group's 8 H2).
        var h3: [[UInt8]] = Array(repeating: [], count: groupCount)
        for g in 0..<groupCount {
            var concat = [UInt8]()
            concat.reserveCapacity(subgroupsPerGroup * 20)
            for k in 0..<subgroupsPerGroup {
                concat.append(contentsOf: h2[g * subgroupsPerGroup + k])
            }
            h3[g] = SHA1.hash(concat)
        }

        // Build the H3 table (0x18000, zero-filled, H3[g] at g*20).
        var h3Table = [UInt8](repeating: 0, count: h3TableSize)
        for g in 0..<groupCount {
            let off = g * 20
            for j in 0..<20 { h3Table[off + j] = h3[g][j] }
        }

        // 5) Encrypt each cluster with its subgroup's 8 H1 and its group's 8 H2.
        var encrypted = [UInt8]()
        encrypted.reserveCapacity(clusterCount * clusterSize)
        for c in 0..<clusterCount {
            let subgroup = c / clustersPerSubgroup
            let group = c / clustersPerGroup

            let sgBase = (subgroup) * clustersPerSubgroup
            let h1Table = (0..<clustersPerSubgroup).map { h1[sgBase + $0] }

            let gSgBase = group * subgroupsPerGroup
            let h2Table = (0..<subgroupsPerGroup).map { h2[gSgBase + $0] }

            let base = c * userDataPerCluster
            let userBytes = Array(user[base..<(base + userDataPerCluster)])

            let clusterBytes = buildEncryptedCluster(
                userBytes: userBytes,
                h0Hashes: h0[c],
                h1Hashes: h1Table,
                h2Hashes: h2Table,
                titleKey: titleKey
            )
            encrypted.append(contentsOf: clusterBytes)
        }

        return (encrypted: encrypted, h3Table: h3Table)
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
    /// - Parameter ticketData: Mutable ticket data
    /// - Returns: Fakesigned ticket data
    public static func fakesignTicket(_ ticketData: GoDData) -> GoDData {
        let result = GoDData(byteStream: ticketData.rawBytes.map(Int.init), byteOrder: ticketData.byteOrder)
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
        let result = GoDData(byteStream: tmdData.rawBytes.map(Int.init), byteOrder: tmdData.byteOrder)
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
