//
//  FileFormatRegistry+Dolphin.swift
//
//  Dolphin-side built-in registrations. Currently only `.rel`. Engines
//  can be merged into a single registry via the static `merging` helper.
//

import GoDFoundation

public extension FileFormatRegistry {
    /// A registry pre-populated with every Dolphin-side FileFormat
    /// (currently just RELFile under the `rel` extension).
    static func dolphinBuiltins() -> FileFormatRegistry {
        var r = FileFormatRegistry()
        r.register("rel", RELFile.self)
        return r
    }

}
