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
        r.register("gsw", GSWFile.self)
        return r
    }
}
