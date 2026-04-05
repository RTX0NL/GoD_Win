import GoDFoundation

/// Provides random-access read of decrypted Wii partition user data
/// without decrypting the entire partition into memory.
/// Decrypts individual 0x8000-byte groups on demand and caches recently used groups.
public final class WiiDecryptedPartitionView: GoDReadable {
    public let byteOrder: ByteOrder = .big

    private let encryptedData: GoDData
    private let partitionDataStart: Int
    private let titleKey: [UInt8]
    private let groupSize: Int
    private let userDataPerGroup: Int

    /// Total size of decrypted user data in bytes.
    public let length: Int

    private var cache: [Int: GoDData] = [:]
    private let maxCacheSize = 64

    public init(
        encryptedData: GoDData,
        partitionDataStart: Int,
        dataSize: Int,
        titleKey: [UInt8],
        groupSize: Int = 0x8000,
        userDataPerGroup: Int = 0x7C00
    ) {
        self.encryptedData = encryptedData
        self.partitionDataStart = partitionDataStart
        self.titleKey = titleKey
        self.groupSize = groupSize
        self.userDataPerGroup = userDataPerGroup
        self.length = (dataSize / groupSize) * userDataPerGroup
    }

    public func read(atAddress address: UInt, length: UInt) -> GoDData? {
        let start = Int(address)
        let end = start + Int(length)
        guard start >= 0, end <= self.length, length > 0 else { return nil }

        let result = GoDData(length: Int(length), byteOrder: .big)
        var bytesWritten = 0
        var currentOffset = start

        while bytesWritten < Int(length) {
            let groupIndex = currentOffset / userDataPerGroup
            let offsetInGroup = currentOffset % userDataPerGroup
            let bytesAvailable = userDataPerGroup - offsetInGroup
            let bytesToCopy = min(bytesAvailable, Int(length) - bytesWritten)

            guard let groupData = decryptGroup(at: groupIndex),
                  let chunk = groupData.read(atAddress: offsetInGroup, length: bytesToCopy) else {
                return nil
            }
            result.write(chunk, atAddress: bytesWritten)

            bytesWritten += bytesToCopy
            currentOffset += bytesToCopy
        }
        return result
    }

    private func decryptGroup(at index: Int) -> GoDData? {
        if let cached = cache[index] { return cached }

        let encryptedOffset = partitionDataStart + index * groupSize
        guard let groupData = encryptedData.read(atAddress: encryptedOffset, length: groupSize) else {
            return nil
        }
        let (_, userData) = WiiCrypto.decryptGroup(groupData: groupData, titleKey: titleKey)

        if cache.count >= maxCacheSize {
            cache.removeAll()
        }
        cache[index] = userData
        return userData
    }
}
