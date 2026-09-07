//
//  PBREngine+FileFormats.swift
//  PBR
//
//  Battle Revolution's view of the shared file-format registry.
//
//  `.fnt` names two unrelated formats: Genius Sonority's linked-list font in
//  Colosseum/XD, and PBR's `FONT`-block container. Nothing in the extension
//  distinguishes them, so the *engine* decides — an operation unpacking a PBR
//  disc already knows it is PBR and asks this engine for its registry, rather
//  than sniffing magic at the point of use.
//
//  Everything else PBR shares with Colo/XD (msg, gtx, atx, …) comes straight
//  from the builtins, so this overrides one binding rather than standing up a
//  parallel registry.
//

import GoDFoundation
import GeniusSonority

public extension PBREngine {
    /// File formats a PBR project can dump and rebuild, with `fnt` bound to
    /// `PBRFont` instead of the Genius Sonority font.
    func fileFormats() -> FileFormatRegistry {
        Self.fileFormats()
    }

    /// Static form, for callers that need the registry before an engine has
    /// been loaded — the binding doesn't depend on any engine data.
    static func fileFormats() -> FileFormatRegistry {
        var registry = FileFormatRegistry.builtins()
        registry.register(PBRFont.formatName, PBRFont.self)
        // The 3D display font, a separate format from the bitmap `.fnt`.
        registry.register(PBRFont3D.formatName, PBRFont3D.self)
        return registry
    }
}
