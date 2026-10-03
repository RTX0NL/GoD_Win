import GoDFoundation
import Structs

/// Resolves the label fields of a decoded struct into pointer words.
///
/// A `StructData` decoded from JSON or a CSV row carries its `.label` fields
/// as names in `labelValues`, not as bytes. This is the step that turns them
/// into addresses through a `LabelTable` and writes the result into a buffer
/// whose label slots are plain `uint32`s — the form the assembler's `.byte`
/// rendering needs.
///
/// Decoding the JSON or CSV itself is `StructData(definition:json:)` and
/// `StructTableCSV.decode`. This type deliberately carries no parser of its
/// own: the one it used to have was a second, incomplete implementation
/// (it dropped arrays of enums and sub-structs) that nothing on the build
/// path ever called.
public struct TypedDataImporter {

    public init() {}

    /// Bytes for `structData` with every label resolved through `labelTable`.
    /// A label the table cannot resolve leaves its slot zero.
    public func importStruct(
        structData: StructData,
        labelTable: LabelTable,
        byteOrder: ByteOrder
    ) -> GoDData {
        let definition = structData.definition
        let uint32Def = definition.uint32SubstitutedDefinition()
        let output = StructData(definition: uint32Def, byteOrder: byteOrder)

        for property in definition.properties {
            switch property.type {
            case .label:
                if let labelName = structData.labelValues[property.name],
                   let address = labelTable.resolve(labelName) {
                    let value: Int = Int(address)
                    output.set(property.name, to: value)
                }
            case .array(.label, let count):
                // Label arrays: the decoder records per-element names under
                // `name[i]` keys in labelValues. Resolve each to an address
                // and write the pointer slots.
                guard let baseOffset = uint32Def.offset(for: property.name) else { break }
                for i in 0..<count {
                    if let labelName = structData.labelValues["\(property.name)[\(i)]"],
                       let address = labelTable.resolve(labelName) {
                        output.data.write(UInt32(address).rawData(byteOrder: byteOrder), atAddress: baseOffset + i * 4)
                    }
                }
            case .padding:
                break
            default:
                if let fieldData: GoDData = structData.get(property.name) {
                    output.set(property.name, to: fieldData)
                }
            }
        }

        return output.data
    }
}
