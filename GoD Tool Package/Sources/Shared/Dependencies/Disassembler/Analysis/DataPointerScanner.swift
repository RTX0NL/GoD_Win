import GoDFoundation

/// Scans data section bytes for 4-byte values that look like pointers
/// to addresses within known section ranges.
///
/// Uses iterative cross-referencing to minimize false positives:
/// 1. Start with confirmed targets from text section relocation analysis
/// 2. Scan data for values matching confirmed targets
/// 3. Newly confirmed data labels may reveal more data-to-data refs
/// 4. Iterate until stable
public struct DataPointerScanner {

    public init() {}

    /// Scan a data section for pointer-like values.
    ///
    /// - Parameters:
    ///   - data: Raw bytes of the data section
    ///   - baseAddress: RAM address of the start of this data section
    ///   - confirmedTargets: Set of addresses already confirmed as relocation targets
    ///     (e.g. from text section relocation analysis)
    ///   - sectionRanges: All known section address ranges (text, data, BSS)
    /// - Returns: Map of byte offset within data → target address for confirmed pointers
    public func scan(
        data: [UInt8],
        baseAddress: UInt32,
        confirmedTargets: Set<UInt32>,
        sectionRanges: [(start: UInt32, end: UInt32)]
    ) -> [UInt32: UInt32] {
        var pointers = [UInt32: UInt32]()

        guard data.count >= 4 else { return pointers }

        // Scan all 4-byte aligned values
        var offset = 0
        while offset + 3 < data.count {
            let value = UInt32(data[offset]) << 24
                      | UInt32(data[offset + 1]) << 16
                      | UInt32(data[offset + 2]) << 8
                      | UInt32(data[offset + 3])

            if confirmedTargets.contains(value) || isInSectionRange(value, ranges: sectionRanges) {
                pointers[UInt32(offset)] = value
            }
            offset += 4
        }

        return pointers
    }

    /// Perform iterative cross-referencing across multiple data sections.
    ///
    /// - Parameters:
    ///   - dataSections: Array of (baseAddress, bytes) for each data section
    ///   - initialConfirmedTargets: Targets confirmed by text section relocation analysis
    ///   - sectionRanges: All section address ranges
    /// - Returns: Map of (sectionIndex, byteOffset) → target address
    public func scanAllSections(
        dataSections: [(baseAddress: UInt32, data: [UInt8])],
        initialConfirmedTargets: Set<UInt32>,
        sectionRanges: [(start: UInt32, end: UInt32)]
    ) -> [[UInt32: UInt32]] {
        var confirmed = initialConfirmedTargets
        var results = [[UInt32: UInt32]](repeating: [:], count: dataSections.count)

        var changed = true
        while changed {
            changed = false
            for (i, section) in dataSections.enumerated() {
                let newPointers = scan(
                    data: section.data,
                    baseAddress: section.baseAddress,
                    confirmedTargets: confirmed,
                    sectionRanges: sectionRanges
                )
                if newPointers != results[i] {
                    results[i] = newPointers
                    // Add newly discovered pointer target addresses to confirmed set
                    for (_, target) in newPointers {
                        if !confirmed.contains(target) {
                            confirmed.insert(target)
                            changed = true
                        }
                    }
                    // Also add the addresses of the pointers themselves as confirmed
                    // (they might be pointed to by other data)
                    for (offset, _) in newPointers {
                        let addr = section.baseAddress + offset
                        if !confirmed.contains(addr) {
                            confirmed.insert(addr)
                            changed = true
                        }
                    }
                }
            }
        }

        return results
    }

    private func isInSectionRange(_ address: UInt32, ranges: [(start: UInt32, end: UInt32)]) -> Bool {
        ranges.contains { address >= $0.start && address < $0.end }
    }
}
