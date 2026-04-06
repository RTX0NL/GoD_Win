import GoDFoundation

/// Master list of BSS (uninitialized data) entries.
/// Stored as a separate file from the type map. New entries are appended.
/// During assembly, addresses are assigned sequentially within the BSS range.
public struct BSSEntryList: Codable, Equatable {
    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public struct Entry: Codable, Equatable {
        /// Label name for this BSS variable
        public let label: String
        /// Size in bytes to reserve
        public let size: UInt32

        public init(label: String, size: UInt32) {
            self.label = label
            self.size = size
        }
    }

    /// Compute label addresses given a BSS base address.
    /// Entries are laid out sequentially with 4-byte alignment.
    public func assignAddresses(baseAddress: UInt32) -> [(label: String, address: UInt32, size: UInt32)] {
        var current = baseAddress
        var result = [(label: String, address: UInt32, size: UInt32)]()
        for entry in entries {
            // Align to 4 bytes
            let alignmentOffset = current % 4
            if alignmentOffset > 0 {
                current += 4 - alignmentOffset
            }
            result.append((label: entry.label, address: current, size: entry.size))
            current += entry.size
        }
        return result
    }

    /// Compute total BSS size needed to encompass all entries (from base address)
    public func totalSize(baseAddress: UInt32) -> UInt32 {
        let assigned = assignAddresses(baseAddress: baseAddress)
        guard let last = assigned.last else { return 0 }
        let end = last.address + last.size
        // Align total size to 4 bytes
        let alignmentOffset = end % 4
        let alignedEnd = alignmentOffset > 0 ? end + (4 - alignmentOffset) : end
        return alignedEnd - baseAddress
    }
}
