//
//  RegistryFactories.swift
//
//  Factories that build FileFormatRegistry instances spanning multiple
//  engines (which are otherwise unaware of each other). Lives in GODSDK
//  because that's the only target that imports every engine module.
//

import GoDFoundation
import GeniusSonority
import Dolphin

extension FileFormatRegistry {
    /// Registry containing every FileFormat across all engines: the
    /// Genius Sonority bundle (msg/fnt/gtx/atx/gsw) plus the Dolphin
    /// bundle (rel).
    public static func all() -> FileFormatRegistry {
        var r = FileFormatRegistry.builtins()
        r.merge(.dolphinBuiltins())
        return r
    }
}
