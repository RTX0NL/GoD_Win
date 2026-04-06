import GoDFoundation
import Structs

/// Imports typed struct data from JSON back to binary using the two-step import process:
/// 1. Decode JSON into StructData with real definition (label fields in labelValues dict)
/// 2. Create binary buffer using uint32-substituted definition
/// 3. Copy non-label field values, resolve label names to addresses
public struct TypedDataImporter {

    public init() {}

    /// Import a single struct from a StructData with label values.
    ///
    /// - Parameters:
    ///   - structData: The decoded StructData (with labelValues populated from JSON)
    ///   - labelTable: For resolving label names to addresses
    ///   - byteOrder: Byte order for the output binary
    /// - Returns: Raw binary bytes for this struct
    public func importStruct(
        structData: StructData,
        labelTable: LabelTable,
        byteOrder: ByteOrder
    ) -> GoDData {
        let definition = structData.definition
        let uint32Def = definition.uint32SubstitutedDefinition()
        let output = StructData(definition: uint32Def, byteOrder: byteOrder)

        // Copy all field data from source to output
        for property in definition.properties {
            switch property.type {
            case .label:
                // Resolve label name to address
                if let labelName = structData.labelValues[property.name],
                   let address = labelTable.resolve(labelName) {
                    let value: Int = Int(address)
                    output.set(property.name, to: value)
                }
            case .padding:
                break
            default:
                // Copy raw data for non-label fields
                if let fieldData: GoDData = structData.get(property.name) {
                    output.set(property.name, to: fieldData)
                }
            }
        }

        return output.data
    }

    /// Import a table of struct entries.
    ///
    /// - Parameters:
    ///   - entries: Array of LabeledData (decoded from JSON)
    ///   - definition: The struct definition for each entry
    ///   - labelTable: For resolving label names to addresses
    ///   - byteOrder: Byte order for the output binary
    /// - Returns: Concatenated raw binary bytes for the entire table
    public func importTable(
        entries: [LabeledData],
        definition: StructDefinition,
        labelTable: LabelTable,
        byteOrder: ByteOrder
    ) -> GoDData {
        let result = GoDData(length: 0, byteOrder: byteOrder)

        for entry in entries {
            let entryBytes = importStruct(
                structData: entry.data,
                labelTable: labelTable,
                byteOrder: byteOrder
            )
            result.append(entryBytes)
        }

        return result
    }
}
