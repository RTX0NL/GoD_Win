//
//  ProjectVersionStamp.swift
//  GODOps
//
//  A project is bound to the tool version that dumped it: its engine folders,
//  registries and manifests are written in that version's layout, and moving
//  a project between versions means rebuilding with the old one and dumping
//  again with the new. Setup therefore records the version that wrote the
//  project as a small text file at the top of `/Engines` — the folder whose
//  contents that version defines.
//
//  The version is a parameter, not a constant: GODOps is a library, and the
//  number belongs to the executable built on it (`Version` in GODDESS), so
//  the caller says who it is.
//

import GoDFoundation

extension Project {
    /// Name of the stamp file at the top level of a project's `/Engines` folder.
    static let versionStampFileName = "Version.txt"

    /// Writes `toolVersion` (with a trailing newline) to
    /// `<enginesFolder>/Version.txt`.
    static func writeVersionStamp(
        _ toolVersion: String,
        to fileSystem: FileSystemTree,
        in enginesFolder: Folder
    ) throws {
        try fileSystem.writeFile(
            (toolVersion + "\n").data(format: .utf8),
            at: enginesFolder.file(versionStampFileName),
            overwrite: false
        )
    }
}
