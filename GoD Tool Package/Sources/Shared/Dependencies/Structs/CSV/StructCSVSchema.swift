//
//  StructCSVSchema.swift
//
//  Flattens a StructDefinition into the ordered list of leaf columns a CSV
//  row carries. This is the single source of truth for both directions of
//  the codec — the encoder reads each column's bytes, the decoder writes
//  them — so a header and an offset can never disagree.
//

import Foundation
import GoDFoundation

/// One CSV column: a scalar leaf of the struct, at a known byte offset.
public struct StructCSVColumn: Equatable {

    /// The header text. Sub-struct fields are dotted paths
    /// (`stats.attack`); array elements are bracketed and **1-indexed**
    /// (`moves[1]`), because the file is meant to be read by a person.
    public let header: String

    /// The leaf's declared type. Character arrays keep their array type —
    /// a whole string is one column, not one column per character.
    public let type: StructProperty

    /// Byte offset of the leaf within an entry.
    public let offset: Int

    /// Key this leaf uses in `StructData.labelValues`, for `.label` leaves
    /// only. **0-indexed** for array elements (`ptrs[0]`), unlike `header`:
    /// that's the key `TypedDataImporter` resolves against, so it is a wire
    /// format rather than a display choice.
    public let labelKey: String?

    public init(header: String, type: StructProperty, offset: Int, labelKey: String? = nil) {
        self.header = header
        self.type = type
        self.offset = offset
        self.labelKey = labelKey
    }
}

public enum StructCSVSchema {

    /// The columns of `definition`, in declaration order.
    ///
    /// Omitted, because none of them is an editable value:
    ///   * padding — both the bare `.padding` type and the `.padding(length:)`
    ///     helper's `"padding"`-named byte array. Dropping the columns means
    ///     padding is rebuilt as zeroes, so a struct whose padding isn't zero
    ///     won't round-trip byte-identically; that's a signal the run isn't
    ///     padding and should be typed as a real field.
    ///   * `.primitive(.void)`, which occupies no bytes.
    public static func columns(of definition: StructDefinition) -> [StructCSVColumn] {
        var columns = [StructCSVColumn]()
        appendColumns(
            of: definition,
            atOffset: 0,
            headerPrefix: "",
            labelPrefix: "",
            into: &columns
        )
        return columns
    }

    private static func appendColumns(
        of definition: StructDefinition,
        atOffset baseOffset: Int,
        headerPrefix: String,
        labelPrefix: String,
        into columns: inout [StructCSVColumn]
    ) {
        var offset = baseOffset
        for property in definition.properties {
            // Mirrors the alignment walk in `StructData.encode` /
            // `StructData.populate`; the three have to agree on offsets.
            switch definition.alignmentStyle {
            case .none:
                break
            case .cStyle:
                let alignmentOffset = offset % property.type.alignment
                if alignmentOffset > 0 {
                    offset += property.type.alignment - alignmentOffset
                }
            }

            if property.name != StructDefinition.paddingPropertyName {
                appendColumns(
                    of: property.type,
                    header: headerPrefix + property.name,
                    labelKey: labelPrefix + property.name,
                    atOffset: offset,
                    into: &columns
                )
            }
            offset += property.type.length
        }
    }

    private static func appendColumns(
        of type: StructProperty,
        header: String,
        labelKey: String,
        atOffset offset: Int,
        into columns: inout [StructCSVColumn]
    ) {
        switch type {
        case .padding, .primitive(.void):
            return

        case .primitive, .enumeration:
            columns.append(.init(header: header, type: type, offset: offset))

        case .label:
            columns.append(.init(header: header, type: type, offset: offset, labelKey: labelKey))

        case .subStruct(let definition):
            appendColumns(
                of: definition,
                atOffset: offset,
                headerPrefix: header + ".",
                labelPrefix: labelKey + ".",
                into: &columns
            )

        case .array(let element, let count):
            // A character array is a string: one column for the whole run.
            if case .primitive(.character) = element {
                columns.append(.init(header: header, type: type, offset: offset))
                return
            }
            let stride = element.length
            for index in 0 ..< count {
                appendColumns(
                    of: element,
                    header: "\(header)[\(index + 1)]",
                    labelKey: "\(labelKey)[\(index)]",
                    atOffset: offset + index * stride,
                    into: &columns
                )
            }
        }
    }
}
