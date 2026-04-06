import GoDFoundation

/// Maps relocation pointer indices in a REL file to human-readable symbol names
/// and optionally links list symbols to their count symbols.
///
/// Each entry can be either a simple string name or an object with name + countIndex.
public struct RelSymbolIndex: Codable, Equatable {
    /// Maps pointer index (as string key) to symbol info
    public let symbols: [String: SymbolEntry]

    public init(symbols: [String: SymbolEntry] = [:]) {
        self.symbols = symbols
    }

    /// A symbol entry — either just a name, or a name with a linked count index
    public enum SymbolEntry: Codable, Equatable {
        case name(String)
        case withCount(name: String, countIndex: Int)

        public var symbolName: String {
            switch self {
            case .name(let n): return n
            case .withCount(let n, _): return n
            }
        }

        public var countIndex: Int? {
            switch self {
            case .name: return nil
            case .withCount(_, let i): return i
            }
        }

        // Custom Codable: decode as string or object
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let str = try? container.decode(String.self) {
                self = .name(str)
            } else {
                let obj = try SymbolObject.init(from: decoder)
                self = .withCount(name: obj.name, countIndex: obj.countIndex)
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .name(let n):
                var container = encoder.singleValueContainer()
                try container.encode(n)
            case .withCount(let n, let c):
                try SymbolObject(name: n, countIndex: c).encode(to: encoder)
            }
        }

        private struct SymbolObject: Codable {
            let name: String
            let countIndex: Int
        }
    }

    /// Look up a symbol name by its integer index
    public func name(for index: Int) -> String? {
        symbols[String(index)]?.symbolName
    }

    /// Look up the count index linked to a list symbol
    public func countIndex(for index: Int) -> Int? {
        symbols[String(index)]?.countIndex
    }

    /// All indices that have names, sorted
    public var namedIndices: [(index: Int, name: String, countIndex: Int?)] {
        symbols.compactMap { key, value in
            guard let index = Int(key) else { return nil }
            return (index: index, name: value.symbolName, countIndex: value.countIndex)
        }.sorted(by: { $0.index < $1.index })
    }

    /// Get all list symbols (those with a countIndex) and their count symbol names
    public var listSymbols: [(listIndex: Int, listName: String, countIndex: Int, countName: String)] {
        namedIndices.compactMap { entry in
            guard let ci = entry.countIndex,
                  let countName = name(for: ci) else { return nil }
            return (listIndex: entry.index, listName: entry.name, countIndex: ci, countName: countName)
        }
    }
}
