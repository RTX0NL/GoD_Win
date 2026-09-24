//
//  StructPaddingFill.swift
//
//  One run of padding inside a record, and the byte a packer leaves there.
//
//  Padding has no CSV column and nothing to edit, so a row rebuilt from a
//  CSV is zero across its gaps. That is right for a packer that zeroes them
//  and wrong for one that doesn't: Battle Revolution's table compiler fills
//  some gaps with `0xD0` and others with zero, per run rather than per
//  format, so the runs have to be named individually.
//
//  The value is measured where the table is read and carried to where it is
//  written (for `common.fsys` that is the FSYS registry), never inferred: a
//  run whose bytes are not one repeated value is not padding at all, and the
//  reader that measured it says so by refusing to type the table.
//

import Foundation

public struct StructPaddingFill: Codable, Equatable {
    /// Byte offset of the run within one entry.
    public let offset: Int
    /// Length of the run in bytes.
    public let length: Int
    /// The byte filling it.
    public let byte: UInt8

    public init(offset: Int, length: Int, byte: UInt8) {
        self.offset = offset
        self.length = length
        self.byte = byte
    }

    /// The fill in each of the definition's padding runs, read off the rows
    /// themselves, or `nil` if any run holds more than one distinct byte.
    ///
    /// `nil` is the interesting answer: a run that varies from row to row
    /// carries information, so it is a field the definition hasn't named —
    /// and a caller that writes a CSV on the strength of that definition
    /// would be dropping data. The reader is expected to refuse the table
    /// rather than record a fill that isn't one.
    ///
    /// Runs that are already zero are left out: a row rebuilt from a CSV
    /// starts zeroed, so naming them would only pad the manifest.
    public static func measure(in entries: [StructData], definition: StructDefinition) -> [StructPaddingFill]? {
        var fills = [StructPaddingFill]()
        for range in definition.paddingRanges {
            var fill: UInt8?
            for entry in entries {
                let bytes = entry.data.rawBytes
                guard range.upperBound <= bytes.count else { return nil }
                for byte in bytes[range] {
                    if let fill, fill != byte { return nil }
                    fill = byte
                }
            }
            if let fill, fill != 0 {
                fills.append(.init(offset: range.lowerBound, length: range.count, byte: fill))
            }
        }
        return fills
    }
}
