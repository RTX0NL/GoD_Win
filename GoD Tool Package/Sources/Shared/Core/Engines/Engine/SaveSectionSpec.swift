//
//  SaveSectionSpec.swift
//
//  Engine-level descriptor for a single save-data section. Mirrors
//  the `DataSectionManifest.Chunk` shape used for DOL/REL data
//  sections — same taxonomy, same field names, same dump path.
//
//  Per-engine `saveSections` are flat ordered arrays where the array
//  index *is* the section's logical index. Sections are always
//  sequential within a slot — the `engine.sectionStructTypes` map
//  binds each index to a registered `StructDefinition`, and the
//  section's length derives from that struct (or struct × count for
//  tables). Physical offset within the slot is therefore also
//  derivable: array position N's offset is the cumulative sum of
//  all earlier sections' lengths added to whatever base address
//  the runtime uses (XD: the slot's in-slot TOC at +0x40; Colo:
//  the engine's known body-base, currently +0x08).
//
//  Section ↔ struct binding lives **outside** this type, in the
//  engine's flat `sectionStructTypes: [Int: String]` mapping. That
//  keeps mod authoring simple: adding, removing, or rewiring a
//  section's struct binding is a one-key edit on the engine, with
//  no need to redeclare `SaveSectionSpec` instances.
//
//  Round-trip status: all three section types round-trip. `.struct` and
//  `.table` sections dump to JSON through `StructData` and rebuild from
//  that same JSON via `StructData(definition:json:)` — the shared entry
//  point the DOL/REL typed-chunk pipeline also uses. `.binary` sections
//  dump and rebuild as raw bytes. Edits to a dumped `.json` land in the
//  rebuilt save; `raw-slot.bin` is a diffing reference and is not read
//  by the build.
//

import Foundation

public enum SaveSectionType: String, Codable, Equatable {
    /// Raw bytes only — no JSON sidecar emitted, but the section
    /// still has a struct binding (for length-derivation purposes).
    case binary
    /// A single typed struct instance. Resolves the struct via
    /// `engine.sectionStructTypes[index]`.
    case `struct`
    /// A run of consecutive same-typed structs. Struct comes from
    /// `engine.sectionStructTypes[index]`; entry count comes from
    /// `count` here, falling back to `bytes.length / struct.length`.
    case table
}

public struct SaveSectionSpec: Codable, Equatable {

    /// Display name. Drives dump filenames (`<idx>-<name>.bin`,
    /// `<idx>-<name>.json`) and JSON keys.
    public let name: String

    /// What this section *is*. Switches the dump emitter between
    /// `.bin`-only and the struct-driven `.json` path.
    public let type: SaveSectionType

    /// For `.table` sections: hardcoded entry count. Used only when
    /// the runtime can't compute it from
    /// `section.byteLength / struct.length` (e.g. trailing entries
    /// are zero-padded and shouldn't be parsed).
    public let count: Int?

    public init(name: String, type: SaveSectionType, count: Int? = nil) {
        self.name = name
        self.type = type
        self.count = count
    }

    // MARK: - Convenience constructors

    public static func binary(name: String) -> SaveSectionSpec {
        SaveSectionSpec(name: name, type: .binary)
    }

    /// `.struct` sections derive their length from
    /// `engine.sectionStructTypes[index]` → `engine.structs`. The
    /// engine *must* have a binding for the section's index.
    public static func structInstance(name: String) -> SaveSectionSpec {
        SaveSectionSpec(name: name, type: .struct)
    }

    /// `.table` sections derive total length from
    /// `engine.sectionStructTypes[index]` → struct × `count`.
    public static func table(name: String, count: Int? = nil) -> SaveSectionSpec {
        SaveSectionSpec(name: name, type: .table, count: count)
    }

}
