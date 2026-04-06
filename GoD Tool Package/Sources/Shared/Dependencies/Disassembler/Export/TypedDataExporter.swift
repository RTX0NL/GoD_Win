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
    /// - Returns: A StructData with labelValues populated
    public func exportStruct(
        data: GoDData,
        definition: StructDefinition,
        addressToLabel: [UInt32: String]
    ) -> StructData {
        let uint32Def = definition.uint32SubstitutedDefinition()
        let rawStruct = StructData(definition: uint32Def, data: data.copy)

        let labelStruct = StructData(definition: definition, data: data.copy)

        // Copy non-label field values and resolve label fields
        for property in definition.properties {
            switch property.type {
            case .label:
                // Read the raw uint32 address from the original data
                if let rawValue: Int = rawStruct.get(property.name) {
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
        addressToLabel: [UInt32: String]
    ) -> [LabeledData] {
        let entrySize = definition.length
        var entries = [LabeledData]()

        // Build offset → label lookup
        let labelLookup = Dictionary(entryLabels.map { ($0.offset, $0.name) }, uniquingKeysWith: { first, _ in first })

        for i in 0..<count {
            let offset = i * entrySize
            guard offset + entrySize <= data.length else { break }

            guard let entryData = data.read(atAddress: offset, length: entrySize) else { continue }

            let structData = exportStruct(
                data: entryData,
                definition: definition,
                addressToLabel: addressToLabel
            )

            let label = labelLookup[offset]
            entries.append(LabeledData(label: label, data: structData))
        }

        return entries
    }
}
