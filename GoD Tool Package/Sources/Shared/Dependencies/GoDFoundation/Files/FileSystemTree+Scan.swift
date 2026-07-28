//
//  FileSystemTree+Scan.swift
//
//  Recursive listing, in one place.
//
//  "Walk this folder and collect the files matching X, keeping track of where
//  each one sat relative to the root" was written out by hand at ten separate
//  call sites across the ColoXD dump and build operations — the same ~14 lines
//  each time, differing only in the predicate. Anything that needs fixing in
//  it (ordering, symlinks, error handling) has to be fixed ten times.
//

import Foundation

/// A file found by a scan, with its location relative to the scanned root.
public struct ScannedFile: Equatable {
    public let file: File
    /// Folder containing `file`, relative to the scanned root — `.` for a file
    /// sitting directly in it. This is what lets a dump mirror the input's
    /// directory layout into its output.
    public let relativeFolder: Folder

    public init(file: File, relativeFolder: Folder) {
        self.file = file
        self.relativeFolder = relativeFolder
    }
}

public extension FileSystemTree {

    /// Files under `folder` (optionally recursing) that satisfy `matches`.
    ///
    /// Results are ordered by path so a run is reproducible: neither
    /// `contentsOfDirectory` nor a `Set`-backed in-memory tree promises an
    /// order, and an operation that builds output from a listing would
    /// otherwise vary between runs.
    func scan(
        _ folder: Folder,
        recursive: Bool = true,
        matches: (File) -> Bool
    ) -> [ScannedFile] {
        var found = [ScannedFile]()

        func walk(_ current: Folder, _ relative: Folder) {
            guard let contents = inspectFolder(at: current) else { return }
            for file in contents.files where matches(file) {
                found.append(ScannedFile(file: file, relativeFolder: relative))
            }
            guard recursive else { return }
            for sub in contents.subFolders.sorted() {
                walk(sub, relative.folder(sub.folderName))
            }
        }

        walk(folder, Folder("."))
        return found.sorted { $0.file.path < $1.file.path }
    }

    /// Files under `folder` with the given extension (no leading dot).
    func scan(_ folder: Folder, withExtension ext: String, recursive: Bool = true) -> [ScannedFile] {
        let wanted = ext.lowercased()
        return scan(folder, recursive: recursive) { $0.fileType?.lowercased() == wanted }
    }

    /// Files under `folder` whose name ends with `suffix` — for the compound
    /// artifact names a manifest uses (`<name>.atx.json`), which aren't a
    /// single file extension.
    func scan(_ folder: Folder, withSuffix suffix: String, recursive: Bool = true) -> [ScannedFile] {
        scan(folder, recursive: recursive) { $0.fileName.hasSuffix(suffix) }
    }
}
