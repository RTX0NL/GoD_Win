import Foundation

/// A symbol from a symbol map file
public struct PPCSymbol {
    public let name: String
    public let address: UInt32
    public let size: UInt32
    public let section: String?

    public init(name: String, address: UInt32, size: UInt32, section: String? = nil) {
        self.name = name
        self.address = address
        self.size = size
        self.section = section
    }
}

/// Parses Dolphin and dtk symbol map formats
public struct SymbolMapParser {

    public init() {}

    /// Parse a symbol map file, auto-detecting format
    public func parse(_ text: String) -> [PPCSymbol] {
        let lines = text.components(separatedBy: .newlines)
        guard let firstContentLine = lines.first(where: { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }) else {
            return []
        }

        // dtk format: "name = section:0xADDRESS; // type:function size:0xSIZE"
        if firstContentLine.contains("=") && firstContentLine.contains(":0x") {
            return parseDtkFormat(lines)
        }

        // Dolphin format: "80003100 000000e4 80003100  0 __start"
        return parseDolphinFormat(lines)
    }

    /// Build a lookup table from address → symbol name
    public func buildLookup(_ symbols: [PPCSymbol]) -> [UInt32: String] {
        var lookup = [UInt32: String]()
        for symbol in symbols {
            lookup[symbol.address] = symbol.name
        }
        return lookup
    }
}

// MARK: - Dolphin .map format

private extension SymbolMapParser {
    /// Parses Dolphin emulator .map format:
    /// ```
    /// 80003100 000000e4 80003100  0 __start
    /// ```
    /// Fields: address size vaddr section_index name
    func parseDolphinFormat(_ lines: [String]) -> [PPCSymbol] {
        var symbols = [PPCSymbol]()
        var currentSection: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Section headers like ".text section layout"
            if trimmed.hasPrefix(".") && trimmed.contains("section") {
                currentSection = String(trimmed.split(separator: " ").first ?? "")
                continue
            }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 5 else { continue }

            guard let address = UInt32(parts[0], radix: 16),
                  let size = UInt32(parts[1], radix: 16) else {
                continue
            }

            // parts[2] is vaddr (usually same as address), parts[3] is section index
            let name = String(parts[4...].joined(separator: " "))
            symbols.append(PPCSymbol(name: name, address: address, size: size, section: currentSection))
        }
        return symbols
    }
}

// MARK: - dtk symbols.txt format

private extension SymbolMapParser {
    /// Parses dtk symbols.txt format:
    /// ```
    /// __start = .text:0x80003100; // type:function size:0xE4 scope:global
    /// ```
    func parseDtkFormat(_ lines: [String]) -> [PPCSymbol] {
        var symbols = [PPCSymbol]()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }

            // Split on "="
            let mainParts = trimmed.split(separator: "=", maxSplits: 1)
            guard mainParts.count == 2 else { continue }

            let name = String(mainParts[0]).trimmingCharacters(in: .whitespaces)

            // Parse "section:0xADDRESS; // metadata"
            let valuePart = String(mainParts[1]).trimmingCharacters(in: .whitespaces)

            // Split off comment
            let commentSplit = valuePart.split(separator: ";", maxSplits: 1)
            guard let addressPart = commentSplit.first else { continue }

            // Parse section:0xADDRESS
            let addrStr = String(addressPart).trimmingCharacters(in: .whitespaces)
            let colonParts = addrStr.split(separator: ":", maxSplits: 1)

            var section: String? = nil
            var addressHex: String

            if colonParts.count == 2 {
                section = String(colonParts[0])
                addressHex = String(colonParts[1])
            } else {
                addressHex = String(colonParts[0])
            }

            // Remove "0x" prefix
            if addressHex.hasPrefix("0x") || addressHex.hasPrefix("0X") {
                addressHex = String(addressHex.dropFirst(2))
            }

            guard let address = UInt32(addressHex, radix: 16) else { continue }

            // Parse metadata from comment
            var size: UInt32 = 0
            if commentSplit.count > 1 {
                let metadata = String(commentSplit[1])
                if let sizeRange = metadata.range(of: "size:0x") {
                    let afterSize = metadata[sizeRange.upperBound...]
                    let sizeHex = String(afterSize.prefix(while: { $0.isHexDigit }))
                    size = UInt32(sizeHex, radix: 16) ?? 0
                }
            }

            symbols.append(PPCSymbol(name: name, address: address, size: size, section: section))
        }
        return symbols
    }
}
