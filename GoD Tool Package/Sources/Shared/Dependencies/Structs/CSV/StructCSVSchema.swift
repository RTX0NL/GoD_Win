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

    /// The header text. Sub-struct fields and bit fields are dotted paths
    /// (`stats.attack`, `flags.visible`); array elements are bracketed and
    /// **1-indexed** (`moves[1]`), because the file is meant to be read by
    /// a person.
    public let header: String

    /// What the column holds.
    public let kind: Kind

    /// Byte offset within an entry. For a bit field that is where its
    /// *container* starts — the field itself has no byte of its own.
    public let offset: Int

    /// Key this leaf uses in `StructData.labelValues`, for `.label` leaves
    /// only. **0-indexed** for array elements (`ptrs[0]`), unlike `header`:
    /// that's the key `TypedDataImporter` resolves against, so it is a wire
    /// format rather than a display choice.
    public let labelKey: String?

    public enum Kind: Equatable {
        /// A scalar leaf of its declared type. Character arrays keep their
        /// array type — a whole string is one column, not one per
        /// character.
        case value(StructProperty)
        /// One named bit range of the integer at `offset`. There is no
        /// column for the container itself: two columns writing the same
        /// bytes would make the result depend on header order.
        case bits(BitFieldLayout, BitFieldLayout.Field)
    }

    /// Bytes the column reads. A bit field reads its whole container.
    public var length: Int {
        switch kind {
        case .value(let type): return type.length
        case .bits(let layout, _): return layout.storage.length
        }
    }

    public init(header: String, kind: Kind, offset: Int, labelKey: String? = nil) {
        self.header = header
        self.kind = kind
        self.offset = offset
        self.labelKey = labelKey
    }

    public init(header: String, type: StructProperty, offset: Int, labelKey: String? = nil) {
        self.init(header: header, kind: .value(type), offset: offset, labelKey: labelKey)
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
    ///   * a bit container itself — its named ranges get the columns, and
    ///     a column for the whole integer would write the same bytes a
    ///     second time.
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

        case .bits(let layout):
            for field in layout.fields {
                columns.append(.init(
                    header: header + "." + field.name,
                    kind: .bits(layout, field),
                    offset: offset
                ))
            }

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
