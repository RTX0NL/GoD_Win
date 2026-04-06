import GoDFoundation

/// Produces .4byte/.byte assembly text for untyped data regions.
/// Inserts labels at symbol offsets and uses label names for confirmed pointer values.
public struct AssemblyTextExporter {

    public init() {}

    /// Format a data chunk as assembly text.
    ///
    /// - Parameters:
    ///   - data: Raw bytes
    ///   - baseAddress: RAM address of the start of this chunk
    ///   - labels: Byte offset → label name for symbols within this chunk
    ///   - pointers: Byte offset → target address for confirmed pointer values
    ///   - addressToLabel: Reverse lookup from address to label name (for pointer values)
    ///   - sectionName: Assembly section directive (e.g. ".data0")
    /// - Returns: Assembly text string
    public func format(
        data: [UInt8],
        baseAddress: UInt32,
        labels: [Int: String],
        pointers: [Int: UInt32],
        addressToLabel: [UInt32: String],
        sectionName: String
    ) -> String {
        var lines = [String]()
        lines.append(".section \(sectionName)")
        lines.append("")

        var offset = 0
        while offset + 3 < data.count {
            // Insert label if one exists at this offset
            if let label = labels[offset] {
                lines.append("")
                lines.append(".global \(label)")
                lines.append("\(label):")
            }

            let value = UInt32(data[offset]) << 24
                      | UInt32(data[offset + 1]) << 16
                      | UInt32(data[offset + 2]) << 8
                      | UInt32(data[offset + 3])

            if let targetAddr = pointers[offset], let targetLabel = addressToLabel[targetAddr] {
                lines.append("    .4byte \(targetLabel)")
            } else if let targetLabel = addressToLabel[value] {
                // Even if not in the pointers map, check if the value matches a known label
                lines.append("    .4byte \(targetLabel)")
            } else {
                lines.append("    .4byte 0x\(hex(value))")
            }
            offset += 4
        }

        // Trailing bytes (less than 4)
        while offset < data.count {
            if let label = labels[offset] {
                lines.append("")
                lines.append(".global \(label)")
                lines.append("\(label):")
            }
            lines.append("    .byte 0x\(hex(UInt32(data[offset]), width: 2))")
            offset += 1
        }

        return lines.joined(separator: "\n")
    }

    private func hex(_ value: UInt32, width: Int = 8) -> String {
        let str = String(value, radix: 16, uppercase: true)
        if str.count < width {
            return String(repeating: "0", count: width - str.count) + str
        }
        return str
    }
}
