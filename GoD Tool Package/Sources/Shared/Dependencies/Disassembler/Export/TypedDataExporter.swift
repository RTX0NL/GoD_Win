import GoDFoundation
import Structs

/// Exports typed struct data to JSON using the two-step export process:
/// 1. Read binary using uint32-substituted definition (label fields as raw addresses)
/// 2. Create StructData with real definition, copy non-label fields, resolve label names
public struct TypedDataExporter {

    public init() {}

    /// Export a single struct instance from binary data.
    ///
    /// - Parameters:
    ///   - data: Raw bytes for this struct
    ///   - definition: The struct definition (may contain label fields)
    ///   - byteOrder: Byte order for reading
    ///   - addressToLabel: Reverse lookup for resolving pointer addresses to label names
    ///   - pointerLabels: Relocation-driven pointer names, keyed by byte
    ///     offset within `data`. Pass this for a REL: the word stored at a
    ///     relocation site carries no address (the relocation does), so a
    ///     `.label` field resolves through this map and, where the map has
    ///     no entry, is a null pointer and gets no name — unless the stored
    ///     word is non-zero, in which case it is kept as an `lbl_XXXXXXXX`
    ///     literal so nothing is lost. `nil` means a DOL, where the stored
    ///     word *is* the address and `addressToLabel` names it.
    /// - Returns: A StructData with labelValues populated
    public func exportStruct(
        data: GoDData,
        definition: StructDefinition,
        addressToLabel: [UInt32: String],
        pointerLabels: [Int: String]? = nil
    ) -> StructData {
        let uint32Def = definition.uint32SubstitutedDefinition()
        let rawStruct = StructData(definition: uint32Def, data: data.copy)

        let labelStruct = StructData(definition: definition, data: data.copy)

        // Copy non-label field values and resolve label fields
        for property in definition.properties {
            switch property.type {
            case .label:
                if let pointerLabels {
                    if let offset = definition.offset(for: property.name),
                       let labelName = pointerLabels[offset] {
                        labelStruct.labelValues[property.name] = labelName
                    } else if let rawValue: Int = rawStruct.get(property.name), rawValue != 0 {
                        // Not relocated, yet not zero: the slot holds a value
                        // rather than a pointer. Keep it as a literal so the
                        // bytes survive the round trip (`lbl_XXXXXXXX` rebuilds
                        // as that word when it names no symbol).
                        labelStruct.labelValues[property.name] = "lbl_\(String(format: "%08X", UInt32(rawValue)))"
                    }
                } else if let rawValue: Int = rawStruct.get(property.name) {
                    // Read the raw uint32 address from the original data
                    let address = UInt32(rawValue)
                    if let labelName = addressToLabel[address] {
                        labelStruct.labelValues[property.name] = labelName
                    } else {
                        // No known label — use auto-generated name
                        labelStruct.labelValues[property.name] = "lbl_\(String(format: "%08X", address))"
                    }
                }
            case .padding:
                break
            default:
                // Non-label fields: data is already shared via the copy
                break
            }
        }

        return labelStruct
    }

    /// Export a table of struct entries from binary data.
    ///
    /// - Parameters:
    ///   - data: Raw bytes for the entire table
    ///   - definition: The struct definition for each entry
    ///   - count: Number of entries
    ///   - entryLabels: Ordered list of (offset, labelName) for entries that have labels
    ///   - byteOrder: Byte order for reading
    ///   - addressToLabel: Reverse lookup for resolving pointer addresses to label names
    /// - Returns: Array of LabeledData for each entry
    public func exportTable(
        data: GoDData,
        definition: StructDefinition,
        count: Int,
        entryLabels: [(offset: Int, name: String)],
        addressToLabel: [UInt32: String],
        pointerLabels: [Int: String]? = nil
    ) -> [LabeledData] {
        let entrySize = definition.length
        var entries = [LabeledData]()

        // Build offset → label lookup
        let labelLookup = Dictionary(entryLabels.map { ($0.offset, $0.name) }, uniquingKeysWith: { first, _ in first })

        for i in 0..<count {
            let offset = i * entrySize
            guard offset + entrySize <= data.length else { break }

            guard let entryData = data.read(atAddress: offset, length: entrySize) else { continue }

            // `pointerLabels` is keyed from the table start; each entry
            // sees only its own slice, rebased to its first byte.
            let entryPointerLabels: [Int: String]? = pointerLabels.map { table in
                table.reduce(into: [Int: String]()) { acc, pair in
                    if pair.key >= offset, pair.key < offset + entrySize {
                        acc[pair.key - offset] = pair.value
                    }
                }
            }

            let structData = exportStruct(
                data: entryData,
                definition: definition,
                addressToLabel: addressToLabel,
                pointerLabels: entryPointerLabels
            )

            let label = labelLookup[offset]
            entries.append(LabeledData(label: label, data: structData))
        }

        return entries
    }
}
