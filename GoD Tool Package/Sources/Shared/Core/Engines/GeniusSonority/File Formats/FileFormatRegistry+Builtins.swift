//
//  FileFormatRegistry+Builtins.swift
//
//  Pre-populated registry bundling all Genius Sonority file formats we
//  currently know how to dump and rebuild from artifacts.
//

import GoDFoundation

public extension FileFormatRegistry {
    /// Returns a registry containing every FileFormat implemented in
    /// the GeniusSonority engine module.
    static func builtins() -> FileFormatRegistry {
        var r = FileFormatRegistry()
        r.register("msg", MSGFile.self)
        r.register("fnt", GSFont.self)
        r.register("gtx", GTXFile.self)
        r.register("atx", ATXFile.self)
        r.register("gsw", GSWFile.self)
        // ISF is paired (ISH + ISD); the single-extension registry entry
        // here is mostly for discoverability — ops invoke the format
        // directly with both binaries. Keyed under `ish` so extension-
        // driven lookups find the header half.
        r.register("ish", ISFFile.self)
        // THP is paired (THH + THD); the single-extension entry keyed
        // under `thh` is mostly for discoverability — ops invoke the
        // format directly with both binaries.
        r.register("thh", THPFile.self)
        return r
    }
}
