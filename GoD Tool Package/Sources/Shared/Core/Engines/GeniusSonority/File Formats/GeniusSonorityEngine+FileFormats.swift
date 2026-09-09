//
//  GeniusSonorityEngine+FileFormats.swift
//
//  The engine is the authority on which self-contained file formats it can
//  dump and rebuild. Callers ask it for the registry — through a loaded
//  engine, or the static form when none is needed — rather than reaching
//  for `builtins()` directly.
//
//  This registry covers the formats the *shared* Genius Sonority layer owns,
//  which for `.fnt` means the Colosseum/XD font. Battle Revolution uses an
//  entirely different format under the same extension (`PBRFont`), so its
//  engine will override that one binding once `PBRFont` conforms to
//  `FileFormat`. The specialization belongs there rather than here: the
//  dependency runs PBR -> GeniusSonority, and an operation unpacking a PBR
//  disc already knows it is PBR, so nothing has to sniff bytes to decide.
//

import GoDFoundation

public extension GeniusSonorityEngine {
    /// File formats this engine knows how to dump/rebuild (msg, fnt, gtx,
    /// atx, gsw, and the paired ish/thh headers).
    ///
    /// This binds `fnt` to the Colosseum/XD format; a PBR project must not
    /// use it for fonts.
    func fileFormats() -> FileFormatRegistry {
        Self.fileFormats()
    }

    /// Static form, for callers that need the registry without loading an
    /// engine — the binding doesn't depend on any engine data.
    static func fileFormats() -> FileFormatRegistry {
        .builtins()
    }
}
