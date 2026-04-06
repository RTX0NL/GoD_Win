import GoDFoundation

/// Cross-section symbol table for managing labels across all sections.
/// Collects labels during the address allocation pass and provides
/// lookup for label resolution during assembly.
public class LabelTable {

    private var labels = [String: UInt32]()

    public init() {}

    /// Number of labels in the table
    public var count: Int { labels.count }

    /// Add a label with its address. Does not overwrite existing entries.
    public func addLabel(_ name: String, address: UInt32) {
        if labels[name] == nil {
            labels[name] = address
        }
    }

    /// Add a label, overwriting any existing entry.
    public func setLabel(_ name: String, address: UInt32) {
        labels[name] = address
    }

    /// Look up a label's address by name.
    /// Also handles auto-generated `lbl_XXXXXXXX` patterns by extracting the hex value.
    public func resolve(_ name: String) -> UInt32? {
        if let address = labels[name] {
            return address
        }
        // Try to extract address from lbl_XXXXXXXX pattern
        if name.hasPrefix("lbl_"), name.count == 12 {
            let hex = String(name.dropFirst(4))
            return UInt32(hex, radix: 16)
        }
        return nil
    }

    /// Merge symbols into the table. Existing entries are not overwritten.
    public func mergeSymbols(_ symbols: [Symbol]) {
        for symbol in symbols {
            addLabel(symbol.name, address: symbol.address)
        }
    }

    /// Merge a dictionary of labels. Existing entries are not overwritten.
    public func mergeLabels(_ other: [String: UInt32]) {
        for (name, address) in other {
            addLabel(name, address: address)
        }
    }

    /// Get all labels as a dictionary
    public var allLabels: [String: UInt32] { labels }

    /// Get the label name for an address, if any
    public func labelFor(address: UInt32) -> String? {
        labels.first(where: { $0.value == address })?.key
    }

    /// Build a reverse lookup: address → label name
    public func buildAddressLookup() -> [UInt32: String] {
        Dictionary(labels.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
    }
}
