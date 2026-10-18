import GoDFoundation

/// Nintendo container ops — U8 (`.arc`) and NARC (`.narc`).
///
/// Both formats are handled by one pair of ops rather than one pair each:
/// the archive's own magic says which format and which byte order it is, so
/// a caller that had to name the format up front could only get it wrong.
/// The manifest the dump leaves behind records what was detected, and the
/// build reads it back — see `NintendoArchiveRegistry`.
///
/// Single and bulk variants mirror the map-REL ops: the bulk form scans a
/// folder and gives each archive its own subfolder, so an archive's
/// contents can't collide with another's.
enum NintendoArchiveDump {

    /// Which archives a bulk dump picks up.
    enum Filter: Codable, Equatable {
        /// Every file whose magic identifies it, whatever its extension.
        case all
        /// Only these formats.
        case onlyFormats([String])
        /// Only files with these extensions (no leading dot).
        case onlyExtensions([String])
    }

    /// Unpack one archive into `outputFolder`, writing its contents and a
    /// manifest beside them.
    struct SingleConfig: Codable {
        let archivePath: File
        let outputFolder: Folder
        let overwrite: Bool
        /// Engine folder supplying the alignment and header constants.
        /// Absent uses the built-in defaults, which match every archive
        /// measured so far.
        let nintendoEngine: Folder?

        init(
            archivePath: File,
            outputFolder: Folder,
            overwrite: Bool = true,
            nintendoEngine: Folder? = nil
        ) {
            self.archivePath = archivePath
            self.outputFolder = outputFolder
            self.overwrite = overwrite
            self.nintendoEngine = nintendoEngine
        }
    }

    /// Bulk — scan `archivesFolder` and unpack everything that matches.
    /// Each archive lands in its own subfolder of `outputFolder`, named
    /// after the archive, so `homeBtn.arc` → `<outputFolder>/homeBtn.arc/`.
    /// A recursive dump mirrors the folders it walked, so `hb/x/homeBtn.arc`
    /// → `<outputFolder>/hb/x/homeBtn.arc/`: two folders can hold archives
    /// with the same name.
    struct BatchConfig: Codable {
        let archivesFolder: Folder
        let outputFolder: Folder
        let overwrite: Bool
        let filter: Filter
        /// Descend into subfolders. Off by default so a bulk dump of one
        /// folder can't quietly walk a whole disc.
        let recursive: Bool
        let nintendoEngine: Folder?

        init(
            archivesFolder: Folder,
            outputFolder: Folder,
            overwrite: Bool = true,
            filter: Filter = .all,
            recursive: Bool = false,
            nintendoEngine: Folder? = nil
        ) {
            self.archivesFolder = archivesFolder
            self.outputFolder = outputFolder
            self.overwrite = overwrite
            self.filter = filter
            self.recursive = recursive
            self.nintendoEngine = nintendoEngine
        }
    }
}

enum NintendoArchiveBuild {

    /// Repack one archive from its manifest.
    struct SingleConfig: Codable {
        let manifestPath: File
        /// Where to write the rebuilt archive. Absent puts it next to the
        /// manifest under the archive's own name.
        let outputPath: File?
        let overwrite: Bool
        let nintendoEngine: Folder?

        init(
            manifestPath: File,
            outputPath: File? = nil,
            overwrite: Bool = true,
            nintendoEngine: Folder? = nil
        ) {
            self.manifestPath = manifestPath
            self.outputPath = outputPath
            self.overwrite = overwrite
            self.nintendoEngine = nintendoEngine
        }
    }

    /// Bulk — every manifest under `inputFolder` produces one rebuilt
    /// archive in `outputFolder`, named by the manifest's `archiveName`.
    /// The archive goes where its manifest's folder sits, mirrored under
    /// `outputFolder`, so a bulk dump's `hb/x/homeBtn.arc/` builds back to
    /// `<outputFolder>/hb/x/homeBtn.arc`. Two manifests that would build to
    /// the same file stop the run instead of overwriting each other.
    struct BatchConfig: Codable {
        let inputFolder: Folder
        let outputFolder: Folder
        let overwrite: Bool
        let recursive: Bool
        let nintendoEngine: Folder?

        init(
            inputFolder: Folder,
            outputFolder: Folder,
            overwrite: Bool = true,
            recursive: Bool = true,
            nintendoEngine: Folder? = nil
        ) {
            self.inputFolder = inputFolder
            self.outputFolder = outputFolder
            self.overwrite = overwrite
            self.recursive = recursive
            self.nintendoEngine = nintendoEngine
        }
    }
}
