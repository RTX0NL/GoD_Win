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
    /// A strongly-typed pairing of a supported file type with the engine(s)
    /// that type's decoder/encoder requires. The file formats currently
    /// covered are all Genius Sonority formats, so every case carries the
    /// Genius Sonority engine folder; the message format additionally needs
    /// a variant because the binary layout is shared between Colosseum and
    /// XD but the string rendering differs.
    ///
    /// `ish` (ISF audio) and `thh` (THP video) are *paired* formats: the
    /// `inputFile` given to `decodeFile` is the header half (`.ish` / `.thh`)
    /// and the data half (`.isd` / `.thd`) is read from the same folder by
    /// swapping the extension — the naming convention FSYS extraction
    /// produces. Encoding reads the whole artifact folder, so both halves
    /// come back out together.
    enum FileFormatSelection: Codable, Equatable {
        case msg(geniusSonorityEngine: Folder, variant: MSGFile.Variant)
        case gtx(geniusSonorityEngine: Folder)
        case atx(geniusSonorityEngine: Folder)
        case fnt(geniusSonorityEngine: Folder)
        /// Battle Revolution's font, which shares the `.fnt` extension with
        /// the Colosseum/XD one above and nothing else. A separate case
        /// rather than a flag on `fnt`, because the *file* doesn't say which
        /// it is — the game does, and a config that names the game is the
        /// honest way to record that.
        ///
        /// Carries no engine folder, unlike its siblings: the codec reads no
        /// engine data, and demanding a folder would mean a project whose
        /// serialized engine predates some unrelated struct couldn't convert
        /// a font at all.
        case pbrFont
        /// Battle Revolution's 3D display font. Vector outlines, so its
        /// artifacts are an SVG specimen sheet plus a JSON manifest rather
        /// than an atlas image. Payload-free for the same reason as
        /// `pbrFont`: the codec reads no engine data.
        case pbrFont3D
        case gsw(geniusSonorityEngine: Folder)
        case ish(geniusSonorityEngine: Folder)
        case thh(geniusSonorityEngine: Folder)

        /// The lowercased file extension the registry keys this format under.
        /// For paired formats this is the header half's extension.
        var fileExtension: String {
            switch self {
            case .msg: return "msg"
            case .gtx: return "gtx"
            case .atx: return "atx"
            case .fnt, .pbrFont: return "fnt"
            case .pbrFont3D: return "f3d"
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
            case .msg, .gtx, .atx, .fnt, .pbrFont, .pbrFont3D, .gsw: return nil
            }
        }

        /// The Genius Sonority engine folder supplied for this format, or
        /// `nil` for a format whose codec that engine doesn't own.
        var geniusSonorityEngine: Folder? {
            switch self {
            case let .msg(folder, _),
                 let .gtx(folder),
                 let .atx(folder),
                 let .fnt(folder),
                 let .gsw(folder),
                 let .ish(folder),
                 let .thh(folder):
                return folder
            case .pbrFont, .pbrFont3D:
                return nil
            }
        }

        /// The PBR engine folder, for the formats that engine owns.
        /// True for the formats the PBR engine's registry owns.
        var usesPBRRegistry: Bool {
            switch self {
            case .pbrFont, .pbrFont3D: return true
            default: return false
            }
        }

        /// The file-format registry that owns this format's codec.
        ///
        /// The engine folders are loaded because a registry is an engine's
        /// statement about what it can read — and for `.fnt` the two engines
        /// disagree, which is the whole reason this isn't a single builtin
        /// registry shared by everything.
        func registry(in fileSystem: FileSystemTree) throws -> FileFormatRegistry {
            if usesPBRRegistry {
                return PBREngine.fileFormats()
            }
            guard let geniusSonorityEngine else {
                throw ConvertErrors.missingEngine(format: fileExtension, .init())
            }
            return try GeniusSonorityEngine(from: geniusSonorityEngine, in: fileSystem).fileFormats()
        }
    }
}
