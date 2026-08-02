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
            case .array(.label, let count):
                // Label arrays: the JSON decoder records per-element
                // names under `name[i]` keys in labelValues. Resolve
                // each to an address and write the pointer slots.
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

    // MARK: - JSON → StructData

    /// Decode a JSON dictionary representing a single struct instance
    /// into a `StructData`. Walks the definition's properties; for each,
    /// pulls the matching value out of the JSON object and writes it
    /// into the StructData via the typed setter that matches its
    /// declared kind. Label-typed fields land in `labelValues` so the
    /// existing `importStruct(structData:labelTable:byteOrder:)` step
    /// resolves them to addresses.
    ///
    /// Floats serialized as `"NaN"`/`"Infinity"`/`"-Infinity"` (the
    /// sentinel form `RelDisassembly` emits to keep `JSONSerialization`
    /// from throwing on invalid IEEE-754) are restored to their
    /// non-finite values here. Missing keys leave the default zero
    /// bytes alone — the StructData is initialized zeroed.
    public func decodeStruct(
        from json: [String: Any],
        definition: StructDefinition,
        byteOrder: ByteOrder
    ) -> StructData {
        let result = StructData(definition: definition, byteOrder: byteOrder)
        for property in definition.properties {
            guard let raw = json[property.name] else { continue }
            apply(value: raw, to: result, property: property)
        }
        return result
    }

    /// Decode a JSON document holding a table of structs. Both the
    /// `RelDisassembly` shape (`{"type", "count", "entries"}`) and the
    /// `DolDisassembly` shape (`{"structType", "entries"}`) are
    /// recognized — both share a flat `entries` array of dicts.
    /// Returns the decoded entries plus their labels (`_label` field
    /// when present, e.g. on DOL-emitted dumps).
    public func decodeTable(
        from json: [String: Any],
        definition: StructDefinition,
        byteOrder: ByteOrder
    ) -> [LabeledData] {
        guard let entries = json["entries"] as? [[String: Any]] else { return [] }
        return entries.map { entryJSON in
            let label = entryJSON["_label"] as? String
            let structData = decodeStruct(from: entryJSON, definition: definition, byteOrder: byteOrder)
            return LabeledData(label: label, data: structData)
        }
    }

    /// Convenience: parse JSON bytes and decode a table in one step.
    /// Returns `nil` if the bytes don't decode as a JSON object.
    public func decodeTable(
        jsonBytes: GoDData,
        definition: StructDefinition,
        byteOrder: ByteOrder
    ) -> [LabeledData]? {
        guard let obj = try? JSONSerialization.jsonObject(with: jsonBytes.rawBytes.foundationData) as? [String: Any] else {
            return nil
        }
        return decodeTable(from: obj, definition: definition, byteOrder: byteOrder)
    }

    // MARK: - JSON value → StructData field

    private func apply(
        value: Any,
        to structData: StructData,
        property: StructDefinition.Property
    ) {
        switch property.type {
        case .padding:
            return

        case .label:
            if let name = value as? String, !name.isEmpty {
                structData.setLabel(property.name, to: name)
            }

        case .primitive(.void):
            return

        case .primitive(.integer):
            if let v = readInt(from: value) {
                structData.set(property.name, to: v)
            }

        case .primitive(.float), .primitive(.lossless_float):
            if let v = readFloat(from: value) {
                structData.set(property.name, to: v)
            }

        case .primitive(.double), .primitive(.lossless_double):
            if let v = readDouble(from: value) {
                structData.set(property.name, to: v)
            }

        case .primitive(.boolean):
            if let v = value as? Bool {
                structData.set(property.name, to: v)
            } else if let v = readInt(from: value) {
                structData.set(property.name, to: v != 0)
            }

        case .primitive(.character(let format)):
            if let s = value as? String {
                structData.set(property.name, to: s, format: format)
            }

        case .enumeration(let def):
            // String form (case name) takes precedence; fall back to
            // raw integer when callers have hand-edited a numeric value
            // for a case the enum doesn't name.
            if let name = value as? String,
               let match = try? def.get(name) {
                structData.set(property.name, to: match)
            } else if let v = readInt(from: value) {
                structData.set(property.name, to: v)
            }

        case .array(let elementType, let count):
            applyArray(
                value: value,
                to: structData,
                property: property,
                elementType: elementType,
                count: count
            )

        case .subStruct(let nestedDef):
            // Sub-structs are nested objects in the JSON. Decode as a
            // standalone struct, then write its raw bytes back into the
            // parent at the sub-struct field's offset.
            guard let nestedJSON = value as? [String: Any] else { return }
            let nested = decodeStruct(from: nestedJSON, definition: nestedDef, byteOrder: structData.byteOrder)
            structData.set(property.name, to: nested.data)
        }
    }

    private func applyArray(
        value: Any,
        to structData: StructData,
        property: StructDefinition.Property,
        elementType: StructProperty,
        count: Int
    ) {
        // Character arrays serialize as a single string, not a JSON array.
        if case .primitive(.character(let format)) = elementType,
           let s = value as? String {
            structData.set(property.name, to: s, format: format)
            return
        }
        guard let arr = value as? [Any] else { return }
        guard let baseOffset = structData.definition.offset(for: property.name) else { return }
        let stride = elementType.length
        let buffer = structData.data
        for (i, element) in arr.enumerated() where i < count {
            let elementOffset = baseOffset + i * stride
            guard let bytes = encodeArrayElement(element, type: elementType, byteOrder: structData.byteOrder) else { continue }
            buffer.write(bytes, atAddress: elementOffset)
        }
    }

    private func encodeArrayElement(
        _ value: Any,
        type: StructProperty,
        byteOrder: ByteOrder
    ) -> GoDData? {
        switch type {
        case .primitive(.integer):
            guard let v = readInt(from: value) else { return nil }
            return v.rawData(byteOrder: byteOrder)
        case .primitive(.float):
            guard let v = readFloat(from: value) else { return nil }
            return v.rawData(byteOrder: byteOrder)
        case .primitive(.double):
            guard let v = readDouble(from: value) else { return nil }
            return v.rawData(byteOrder: byteOrder)
        case .primitive(.boolean):
            if let b = value as? Bool { return b.rawData(byteOrder: byteOrder) }
            if let i = readInt(from: value) { return (i != 0).rawData(byteOrder: byteOrder) }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Number coercion

    private func readInt(from value: Any) -> Int? {
        if let v = value as? Int { return v }
        if let v = value as? Int64 { return Int(v) }
        if let v = value as? UInt32 { return Int(v) }
        if let v = value as? UInt64 { return Int(bitPattern: UInt(v)) }
        if let v = value as? Double { return Int(v) }
        if let v = value as? NSNumber { return v.intValue }
        if let v = value as? Bool { return v ? 1 : 0 }
        return nil
    }

    private func readFloat(from value: Any) -> Float? {
        if let v = value as? Float { return v }
        if let v = value as? Double { return Float(v) }
        if let v = value as? Int { return Float(v) }
        if let v = value as? NSNumber { return v.floatValue }
        if let s = value as? String { return parseSpecialFloat(s) }
        return nil
    }

    private func readDouble(from value: Any) -> Double? {
        if let v = value as? Double { return v }
        if let v = value as? Float { return Double(v) }
        if let v = value as? Int { return Double(v) }
        if let v = value as? NSNumber { return v.doubleValue }
        if let s = value as? String,
           let f = parseSpecialFloat(s) { return Double(f) }
        return nil
    }

    /// Round-trips the `"NaN"` / `"Infinity"` / `"-Infinity"` sentinels
    /// `RelDisassembly`'s sanitiser emits when a struct field's raw
    /// bytes don't form a finite IEEE-754 value. Without this the
    /// build-side decoder would throw away those bits and write zero.
    private func parseSpecialFloat(_ s: String) -> Float? {
        switch s {
        case "NaN", "nan": return .nan
        case "Infinity", "inf", "+Infinity": return .infinity
        case "-Infinity", "-inf": return -.infinity
        default: return Float(s)
        }
    }
}

private extension Array where Element == UInt8 {
    var foundationData: Foundation.Data { Foundation.Data(self) }
}
