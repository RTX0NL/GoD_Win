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
            case .fnt: return "fnt"
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
            case .msg, .gtx, .atx, .fnt, .gsw: return nil
            }
        }

        /// The Genius Sonority engine folder supplied for this format.
        var geniusSonorityEngine: Folder {
            switch self {
            case let .msg(folder, _),
                 let .gtx(folder),
                 let .atx(folder),
                 let .fnt(folder),
                 let .gsw(folder),
                 let .ish(folder),
                 let .thh(folder):
                return folder
            }
        }
    }
}
