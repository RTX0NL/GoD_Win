import GoDFoundation

/// Parses a sections.txt format string into a SectionLayout
public struct SectionLayoutParser {

    public init() {}

    public func parse(_ text: String) -> SectionLayout {
        var layout = SectionLayout()

        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)

            // # Entry point: 0x80003154
            if s.hasPrefix("# Entry point:") {
                let hex = s.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
                if hex.hasPrefix("0x"), let val = UInt32(hex.dropFirst(2), radix: 16) {
                    layout.entryPoint = val
                }
                continue
            }

            // # BSS: 0x804205C0 (849860 bytes)
            if s.hasPrefix("# BSS:") {
                let parts = s.dropFirst(6).trimmingCharacters(in: .whitespaces).split(separator: " ")
                if let addrStr = parts.first, addrStr.hasPrefix("0x"),
                   let addr = UInt32(addrStr.dropFirst(2), radix: 16) {
                    layout.bssAddress = addr
                }
                if let sizeStr = parts.dropFirst().first?.replacingOccurrences(of: "(", with: ""),
                   let size = UInt32(sizeStr) {
                    layout.bssSize = size
                }
                continue
            }

            // Skip other comments
            if s.hasPrefix("#") { continue }

            // text0: 0x80003100 (9472 bytes)
            // data0: 0x80456200 (4096 bytes)
            if let info = parseSectionLine(s) {
                if s.hasPrefix("text") {
                    layout.textSections.append(info)
                } else if s.hasPrefix("data") {
                    layout.dataSections.append(info)
                }
            }
        }

        return layout
    }

    private func parseSectionLine(_ s: String) -> SectionLayout.SectionInfo? {
        let parts = s.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let rest = String(parts[1]).trimmingCharacters(in: .whitespaces)
        let tokens = rest.split(separator: " ")

        guard let addrStr = tokens.first,
              addrStr.hasPrefix("0x"),
              let addr = UInt32(addrStr.dropFirst(2), radix: 16) else {
            return nil
        }

        // Parse optional size: (1234 bytes)
        var size: UInt32? = nil
        if tokens.count >= 2 {
            let sizeStr = String(tokens[1]).replacingOccurrences(of: "(", with: "")
            size = UInt32(sizeStr)
        }

        return .init(name: name, address: addr, size: size)
    }
}
