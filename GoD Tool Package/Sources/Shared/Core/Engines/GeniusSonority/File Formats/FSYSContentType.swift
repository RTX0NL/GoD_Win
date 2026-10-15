//
//  FSYSContentType.swift
//  GeniusSonority
//
//  The project extension of an FSYS entry is normally its archive type. Two
//  PBR cases on the US disc store a type the bytes contradict, and the
//  operations that read the project find files by extension, so those files
//  were invisible to them:
//
//  * `mes_common.fsys` holds string table 1 (every language) as entries with
//    no type at all, so they unpacked as `.bin` and `pbrStringsDump` saw only
//    tables 2-4 and refused the disc.
//  * `common.fsys` entry 34 is typed `fnt` but is a 3D font (`F3` magic), so
//    `pbrFontsDump` parsed it as a bitmap font and failed.
//
//  Only a contradiction this unambiguous is corrected, and only the project
//  file's extension: the registry keeps the archive's own type, which is what
//  the repack writes, so the archive still rebuilds byte for byte.
//

import Foundation
import GoDFoundation

extension GeniusSonorityEngine {

    /// The extension an entry's project file takes: the archive's type, or
    /// the type the content plainly has where the two disagree.
    static func projectFileType(archiveType: String?, data: GoDData) -> String {
        let magic = data.read(atAddress: 0, length: 4)?.rawBytes ?? []
        if archiveType == nil, magic == Array("MESG".utf8) {
            return "msg"
        }
        if archiveType == "fnt", magic.starts(with: Array("F3".utf8)) {
            return "f3d"
        }
        return archiveType ?? FSYSArchive.Entry.MetaData.defaultFileExtension
    }
}
