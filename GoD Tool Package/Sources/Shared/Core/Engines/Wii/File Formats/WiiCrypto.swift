import Foundation
import GoDFoundation

/// Wii disc-specific cryptographic operations.
/// Handles title key decryption, data group encryption/decryption,
/// hash chain calculation, and ticket fakesigning.
public struct WiiCrypto {

    // MARK: - Title Key

    /// Decrypt the title key from a ticket using the Wii common key.
    /// - Parameters:
    ///   - ticketData: Raw ticket data (at least 0x1D0 bytes)
    ///   - commonKey: 16-byte Wii common key
    /// - Returns: 16-byte decrypted title key
    public static func decryptTitleKey(ticketData: GoDData, commonKey: [UInt8]) -> [UInt8] {
        // Encrypted title key at offset 0x1BF (16 bytes)
        let encryptedKey = ticketData.read(atAddress: 0x1BF, length: 16)!.rawBytes
        // IV is the title ID (8 bytes at offset 0x1DC) padded with 8 zero bytes
        var iv = ticketData.read(atAddress: 0x1DC, length: 8)!.rawBytes
        iv.append(contentsOf: [UInt8](repeating: 0, count: 8))

        return AES128CBC.decrypt(bytes: encryptedKey, key: commonKey, iv: iv)
    }

    // MARK: - Data Group Decryption

    /// Decrypt a single 0x8000-byte data group.
    /// - Parameters:
    ///   - groupData: Exactly 0x8000 bytes of encrypted group data
    ///   - titleKey: 16-byte decrypted title key
    /// - Returns: Tuple of (decrypted hash block 0x400 bytes, decrypted user data 0x7C00 bytes)
    public static func decryptGroup(groupData: GoDData, titleKey: [UInt8]) -> (hashBlock: GoDData, userData: GoDData) {
        let zeroIV = [UInt8](repeating: 0, count: 16)

        // Decrypt hash block (0x000-0x3FF) with IV = all zeros
        let encryptedHash = groupData.read(atAddress: 0, length: 0x400)!
        let decryptedHash = AES128CBC.decrypt(data: encryptedHash, key: titleKey, iv: zeroIV)

        // IV for user data is bytes 0x3D0-0x3DF of the decrypted hash block
        let dataIV = decryptedHash.read(atAddress: 0x3D0, length: 16)!.rawBytes

        // Decrypt user data (0x400-0x7FFF)
        let encryptedData = groupData.read(atAddress: 0x400, length: 0x7C00)!
        let decryptedData = AES128CBC.decrypt(data: encryptedData, key: titleKey, iv: dataIV)

        return (hashBlock: decryptedHash, userData: decryptedData)
    }

    // MARK: - Data Group Encryption

    /// Encrypt a single data group with proper hash calculation.
    /// - Parameters:
    ///   - userData: 0x7C00 bytes of plaintext user data
    ///   - h1Hash: 20-byte H1 hash for this subgroup (written into hash block)
    ///   - h2Hash: 20-byte H2 hash for this group (written into hash block)
    ///   - subgroupIndex: Index of this block within its subgroup (0-7)
    ///   - groupIndex: Index of this subgroup within its group (0-7)
    ///   - titleKey: 16-byte decrypted title key
    /// - Returns: 0x8000 bytes of encrypted group data
    public static func encryptGroup(
        userData: GoDData,
        h1Hashes: [[UInt8]],
        h2Hashes: [[UInt8]],
        subgroupIndex: Int,
        groupIndex: Int,
        titleKey: [UInt8]
    ) -> GoDData {
        // Build hash block (0x400 bytes)
        var hashBlock = [UInt8](repeating: 0, count: 0x400)

        // H0 hashes (0x000-0x13F): 31 entries of 20 bytes each
        // Each H0 hash covers one 0x400-byte chunk of the user data
        let userBytes = userData.rawBytes
        for i in 0..<31 {
            let chunkStart = i * 0x400
            let chunkEnd = min(chunkStart + 0x400, userBytes.count)
            let chunk = Array(userBytes[chunkStart..<chunkEnd])
            let hash = SHA1.hash(chunk)
            for j in 0..<20 {
                hashBlock[i * 20 + j] = hash[j]
            }
        }

        // H1 hashes (0x140-0x19F): 8 entries of 20 bytes each
        for i in 0..<min(h1Hashes.count, 8) {
            for j in 0..<20 {
                hashBlock[0x140 + i * 20 + j] = h1Hashes[i][j]
            }
        }

        // H2 hashes (0x1A0-0x1EF): 8 entries of 20 bytes each
        for i in 0..<min(h2Hashes.count, 8) {
            for j in 0..<20 {
                hashBlock[0x1A0 + i * 20 + j] = h2Hashes[i][j]
            }
        }

        let hashData = GoDData(byteStream: hashBlock.map(Int.init), byteOrder: .big)

        // Encrypt hash block with IV = all zeros
        let zeroIV = [UInt8](repeating: 0, count: 16)
        let encryptedHash = AES128CBC.encrypt(data: hashData, key: titleKey, iv: zeroIV)

        // IV for user data is bytes 0x3D0-0x3DF of the plaintext hash block
        let dataIV = Array(hashBlock[0x3D0..<0x3E0])
        let encryptedData = AES128CBC.encrypt(data: userData, key: titleKey, iv: dataIV)

        // Combine: encrypted hash (0x400) + encrypted data (0x7C00) = 0x8000
        let result = GoDData(byteStream: [Int](repeating: 0, count: 0x8000), byteOrder: .big)
        result.write(encryptedHash, atAddress: 0)
        result.write(encryptedData, atAddress: 0x400)
        return result
    }

    // MARK: - Hash Chain Calculation

    /// Calculate H0 hashes for a subgroup (8 blocks of user data).
    /// Each H0 hash is SHA-1 of the corresponding 0x400-byte section of user data.
    /// - Parameter subgroupBlocks: Array of 8 user data blocks (each 0x7C00 bytes)
    /// - Returns: Array of 8 arrays, each containing 31 H0 hashes (20 bytes each)
    public static func calculateH0Hashes(subgroupBlocks: [GoDData]) -> [[[UInt8]]] {
        subgroupBlocks.map { block in
            let bytes = block.rawBytes
            return (0..<31).map { i in
                let start = i * 0x400
                let end = min(start + 0x400, bytes.count)
                return SHA1.hash(Array(bytes[start..<end]))
            }
        }
    }

    /// Calculate H1 hash for a block from its H0 hashes.
    /// H1 = SHA-1(all 31 H0 hashes concatenated = 620 bytes)
    public static func calculateH1Hash(h0Hashes: [[UInt8]]) -> [UInt8] {
        let concatenated = h0Hashes.flatMap { $0 }
        return SHA1.hash(concatenated)
    }

    /// Calculate H2 hash from 8 H1 hashes.
    /// H2 = SHA-1(8 H1 hashes concatenated = 160 bytes)
    public static func calculateH2Hash(h1Hashes: [[UInt8]]) -> [UInt8] {
        let concatenated = h1Hashes.flatMap { $0 }
        return SHA1.hash(concatenated)
    }

    /// Calculate H3 hash from 8 H2 hashes.
    /// H3 = SHA-1(8 H2 hashes concatenated = 160 bytes)
    public static func calculateH3Hash(h2Hashes: [[UInt8]]) -> [UInt8] {
        let concatenated = h2Hashes.flatMap { $0 }
        return SHA1.hash(concatenated)
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
