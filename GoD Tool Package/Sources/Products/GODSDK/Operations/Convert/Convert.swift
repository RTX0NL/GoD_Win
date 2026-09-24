//
//  Convert.swift
//  GODOps
//
//  Standalone binary <-> decoded-artifact conversions that don't belong to
//  a specific game family: decode a single binary file into its editable
//  representation (a file format's JSON/PNG artifacts, or a struct/struct-
//  table JSON) and encode those artifacts back into the binary.
//

import GoDFoundation
import GeniusSonority
import PBR

enum Convert {}

extension Convert {
    /// The file format a `decodeFile` / `encodeFile` converts, as one plain
    /// name in the config (`"format": "msg-colo"`). Raw values are the
    /// lowercase extension, then each game suffix hyphenated: `fnt-colo-xd`,
    /// `fnt-pbr`.
    ///
    /// Where one extension is shared by unrelated layouts, or one layout is
    /// rendered differently per game, each variant is its own case named
    /// `<format><Game>`: the *file* doesn't say which it is, the game does,
    /// and a config that names the game records that honestly. A format
    /// with a single layout keeps its bare extension. Nothing here carries
    /// an engine folder: every codec in both registries is self-contained,
    /// so the format name alone picks the registry.
    ///
    /// `ish` (ISF audio) and `thh` (THP video) are *paired* formats: the
    /// `inputFile` given to `decodeFile` is the header half (`.ish` / `.thh`)
    /// and the data half (`.isd` / `.thd`) is read from the same folder by
    /// swapping the extension — the naming convention FSYS extraction
    /// produces. Encoding reads the whole artifact folder, so both halves
    /// come back out together.
    enum FileFormatSelection: String, Codable {
        /// Colosseum/XD string table. One binary layout, but the string
        /// rendering differs per game, so decode has to be told which.
        case msgColo = "msg-colo"
        case msgXD = "msg-xd"
        case gtx
        case atx
        /// The Colosseum/XD bitmap font.
        case fntColoXD = "fnt-colo-xd"
        /// Battle Revolution's bitmap font — the same `.fnt` extension as
        /// `fntColoXD` and nothing else in common.
        case fntPBR = "fnt-pbr"
        /// Battle Revolution's 3D display font. Vector outlines, so its
        /// artifacts are an SVG specimen sheet plus a JSON manifest rather
        /// than an atlas image.
        case f3d
        case gsw
        case ish
        case thh

        /// The lowercased file extension the registry keys this format under.
        /// For paired formats this is the header half's extension.
        var fileExtension: String {
            switch self {
            case .msgColo, .msgXD: return "msg"
            case .gtx: return "gtx"
            case .atx: return "atx"
            case .fntColoXD, .fntPBR: return "fnt"
            case .f3d: return "f3d"
            case .gsw: return "gsw"
            case .ish: return "ish"
            case .thh: return "thh"
            }
        }

        /// For paired formats, the extension of the data half that lives
        /// alongside the header input; `nil` for single-binary formats.
        var pairedDataExtension: String? {
            switch self {
            case .ish: return "isd"
            case .thh: return "thd"
            case .msgColo, .msgXD, .gtx, .atx, .fntColoXD, .fntPBR, .f3d, .gsw: return nil
            }
        }

        /// The string-rendering variant for a message table; `nil` for every
        /// other format.
        var msgVariant: MSGFile.Variant? {
            switch self {
            case .msgColo: return .colo
            case .msgXD: return .xd
            case .gtx, .atx, .fntColoXD, .fntPBR, .f3d, .gsw, .ish, .thh: return nil
            }
        }

        /// The file-format registry that owns this format's codec.
        ///
        /// A registry is an engine's statement about what it can read, and
        /// for `.fnt` the two engines disagree — which is why the selection
        /// is per format rather than one shared registry. Both registries
        /// are static: no codec reads engine data, so no folder is loaded.
        var registry: FileFormatRegistry {
            switch self {
            case .fntPBR, .f3d:
                return PBREngine.fileFormats()
            case .msgColo, .msgXD, .gtx, .atx, .fntColoXD, .gsw, .ish, .thh:
                return GeniusSonorityEngine.fileFormats()
            }
        }
    }
}
