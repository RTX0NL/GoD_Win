import Foundation

/// Writes a symbol list back out in the Dolphin `.map` format
/// `SymbolMapParser` reads.
///
/// This exists so an assembler can say where the symbols ended up. A DOL's
/// symbol map is keyed by address, and the type map that sits on top of it
/// names chunks by label, so a rebuild that changes a chunk's size leaves
/// every later symbol at an address the map no longer knows — the next
/// disassembly then types the wrong bytes. Re-emitting the map with the
/// addresses the assembly actually produced is what keeps the two in step.
///
/// The format is lossless for the maps this tool ships: in all three XD
/// builds every symbol's third column equals its first and every fourth
/// column is `0`, so `address size address 0 name[\tsource]` reproduces the
/// input line for line.
public struct SymbolMapWriter {

    public init() {}

    /// Render `symbols` as a `.map` file.
    ///
    /// Symbols are grouped under their section's `… section layout` header.
    /// Group order follows `sectionOrder` — pass the order the input map
    /// used, so a rewritten map keeps its original shape — and any section
    /// not named there is appended in alphabetical order. Within a group,
    /// symbols are sorted by address and then by name, which makes the
    /// output stable regardless of what order the caller collected them in.
    public func write(_ symbols: [PPCSymbol], sectionOrder: [String] = []) -> String {
        var groups = [String: [PPCSymbol]]()
        for symbol in symbols {
            groups[symbol.section ?? "", default: []].append(symbol)
        }

        var order = [String]()
        // A section-less group has no header to write, so it goes first
        // rather than wherever the input map happened to mention it.
        if groups[""] != nil { order.append("") }
        for section in sectionOrder where groups[section] != nil && !order.contains(section) {
            order.append(section)
        }
        for section in groups.keys.sorted() where !order.contains(section) {
            order.append(section)
        }

        var lines = [String]()
        for section in order {
            guard let group = groups[section] else { continue }
            if !section.isEmpty {
                if !lines.isEmpty { lines.append("") }
                lines.append("\(section) section layout")
            }
            for symbol in group.sorted(by: { ($0.address, $0.name) < ($1.address, $1.name) }) {
                lines.append(line(for: symbol))
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// `80003100 000000e4 80003100 0 __start\tos.a __start.o`
    private func line(for symbol: PPCSymbol) -> String {
        let address = hex(symbol.address)
        var line = "\(address) \(hex(symbol.size)) \(address) 0 \(symbol.name)"
        if let sourceFile = symbol.sourceFile, !sourceFile.isEmpty {
            line += "\t\(sourceFile)"
        }
        return line
    }

    private func hex(_ value: UInt32) -> String {
        let string = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 8 - string.count)) + string
    }
}
