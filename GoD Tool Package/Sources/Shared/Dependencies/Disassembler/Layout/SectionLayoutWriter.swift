import GoDFoundation

/// Writes a SectionLayout to the sections.txt format
public struct SectionLayoutWriter {

    public init() {}

    public func write(_ layout: SectionLayout, symbolCount: Int? = nil) -> String {
        var lines = [String]()

        lines.append("# DOL Section Layout")
        lines.append("# Entry point: 0x\(hex(layout.entryPoint))")
        lines.append("# BSS: 0x\(hex(layout.bssAddress)) (\(layout.bssSize) bytes)")
        if let symbolCount {
            lines.append("# Symbols: \(symbolCount)")
        }
        lines.append("")

        for section in layout.textSections {
            let sizeStr = section.size.map { "(\($0) bytes)" } ?? ""
            lines.append("\(section.name): 0x\(hex(section.address)) \(sizeStr)")
        }
        for section in layout.dataSections {
            let sizeStr = section.size.map { "(\($0) bytes)" } ?? ""
            lines.append("\(section.name): 0x\(hex(section.address)) \(sizeStr)")
        }

        return lines.joined(separator: "\n")
    }

    private func hex(_ value: UInt32) -> String {
        String(value, radix: 16, uppercase: true)
    }
}
