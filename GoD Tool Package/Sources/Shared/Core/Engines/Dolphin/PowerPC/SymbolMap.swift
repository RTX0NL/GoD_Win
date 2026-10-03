import Foundation

/// A symbol from a symbol map file
public struct PPCSymbol {
    public let name: String
    public let address: UInt32
    public let size: UInt32
    public let section: String?
    /// Source file path (e.g. "dbgMenuCamera.o" or "os.a __start.o")
    public let sourceFile: String?

    public init(name: String, address: UInt32, size: UInt32, section: String? = nil, sourceFile: String? = nil) {
        self.name = name
        self.address = address
        self.size = size
        self.section = section
        self.sourceFile = sourceFile
    }

    /// The object file name suitable for use as a folder name.
    /// Extracts the .o filename from paths like "os.a __start.o" or
    /// "fight.a C:\pxdvs\...\fightPokemon.o" → "fightPokemon"
    public var objectFileName: String? {
        guard let sf = sourceFile, !sf.isEmpty else { return nil }
        // Find the last .o file in the path
        let parts = sf.split(separator: " ")
        for part in parts.reversed() {
            let s = String(part)
            if s.hasSuffix(".o") {
                // Strip path separators and .o extension
                let filename = s.split(separator: "\\").last ?? s.split(separator: "/").last ?? Substring(s)
                return String(filename.dropLast(2)) // remove .o
            }
        }
        return nil
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
            return uniquified(parseDtkFormat(lines))
        }

        // Dolphin format: "80003100 000000e4 80003100  0 __start"
        return uniquified(parseDolphinFormat(lines))
    }

    /// CodeWarrior maps repeat local-literal names (`@3097`) at many
    /// different addresses. Duplicate names collide as label definitions
    /// and as chunk file names (later chunks silently overwrite earlier
    /// ones), so every repeat at a new address gets an address suffix.
    /// Comparison is case-INSENSITIVE: symbol names differing only in case
    /// (`GetDarkPokemonID` / `GetDarkpokemonID`) map to per-function files
    /// that overwrite each other on case-insensitive filesystems (macOS).
    private func uniquified(_ symbols: [PPCSymbol]) -> [PPCSymbol] {
        var firstAddressForName = [String: UInt32]()
        var result = [PPCSymbol]()
        result.reserveCapacity(symbols.count)
        for sym in symbols {
            let key = sym.name.lowercased()
            if let owner = firstAddressForName[key], owner != sym.address {
                let unique = "\(sym.name)_\(String(format: "%08X", sym.address))"
                result.append(PPCSymbol(
                    name: unique, address: sym.address, size: sym.size,
                    section: sym.section, sourceFile: sym.sourceFile
                ))
            } else {
                firstAddressForName[key] = sym.address
                result.append(sym)
            }
        }
        return result
    }

    public func buildLookup(_ symbols: [PPCSymbol]) -> [UInt32: String] {
        var lookup = [UInt32: String]()
        for symbol in symbols {
            lookup[symbol.address] = symbol.name
        }
        return lookup
    }

    /// Make a symbol name assembly-safe. Demangled C++ names can carry
    /// template syntax (`Replayable<0,9SaveFrame>`) whose commas, angle
    /// brackets, and spaces break operand splitting and label parsing on
    /// reassembly. Anything outside [A-Za-z0-9_$.] becomes '_', and a
    /// leading digit gets a '_' prefix so the name can't parse as a number.
    static func sanitizeName(_ name: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in name.unicodeScalars {
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", "_", "$", ".":
                out.append(scalar)
            default:
                out.append("_")
            }
        }
        var result = String(out)
        if let first = result.first, first.isNumber {
            result = "_" + result
        }
        return result
    }
}

// MARK: - Dolphin .map format

private extension SymbolMapParser {
    /// Parses Dolphin emulator .map format:
    /// ```
    /// 80003100 000000e4 80003100  0 __start\tos.a __start.o
    /// ```
    /// Fields: address size vaddr section_index name [TAB library]
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

            // Split on tab first to separate name from library info
            let tabParts = trimmed.split(separator: "\t", maxSplits: 1)
            let mainPart = String(tabParts[0])
            let sourceFile = tabParts.count > 1 ? String(tabParts[1]).trimmingCharacters(in: .whitespaces) : nil

            let parts = mainPart.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 5 else { continue }

            guard let address = UInt32(parts[0], radix: 16),
                  let size = UInt32(parts[1], radix: 16) else {
                continue
            }

            // parts[2] is vaddr (usually same as address), parts[3] is section index
            let name = SymbolMapParser.sanitizeName(String(parts[4]))
            symbols.append(PPCSymbol(name: name, address: address, size: size, section: currentSection, sourceFile: sourceFile))
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

            let mainParts = trimmed.split(separator: "=", maxSplits: 1)
            guard mainParts.count == 2 else { continue }

            let name = SymbolMapParser.sanitizeName(String(mainParts[0]).trimmingCharacters(in: .whitespaces))

            // Parse "section:0xADDRESS; // metadata"
            let valuePart = String(mainParts[1]).trimmingCharacters(in: .whitespaces)

            let commentSplit = valuePart.split(separator: ";", maxSplits: 1)
            guard let addressPart = commentSplit.first else { continue }

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

            if addressHex.hasPrefix("0x") || addressHex.hasPrefix("0X") {
                addressHex = String(addressHex.dropFirst(2))
            }

            guard let address = UInt32(addressHex, radix: 16) else { continue }

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
