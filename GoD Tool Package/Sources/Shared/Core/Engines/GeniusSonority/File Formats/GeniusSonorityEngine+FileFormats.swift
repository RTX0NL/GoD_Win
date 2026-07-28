//
//  GeniusSonorityEngine+FileFormats.swift
//
//  The engine is the authority on which self-contained file formats it can
//  dump and rebuild. Callers that hold a loaded engine ask it for the
//  registry rather than reaching for the static `builtins()` directly — this
//  is the extension point for engine-specific format registration later.
//

import GoDFoundation

public extension GeniusSonorityEngine {
    /// File formats this engine knows how to dump/rebuild (msg, fnt, gtx,
    /// atx, gsw, and the paired ish/thh headers).
    func fileFormats() -> FileFormatRegistry {
        .builtins()
    }
}
