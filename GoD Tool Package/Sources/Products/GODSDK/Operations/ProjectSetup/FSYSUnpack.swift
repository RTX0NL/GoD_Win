import GoDFoundation
import GeniusSonority

extension Project {

    /// Unpacks a standalone `.fsys` archive passed directly on the command
    /// line (`GODDESS path/to/common.fsys`) into a sibling folder named
    /// `<stem>_fsys/`, writing each entry as `<name>.<fileType>` with LZSS
    /// entries decompressed.
    ///
    /// The game is auto-detected by attempting each engine's defaults in
    /// priority order (XD, Colosseum, PBR) — extraction itself is
    /// engine-agnostic apart from the file-type name mapping, so the first
    /// engine that parses cleanly wins.
    static func unpack(fsys fsysInputFile: File) throws {
        let fileSystem = FileSystem.shared

        guard let data = fileSystem.readFile(at: fsysInputFile) else {
            throw ProjectSetupErrors.fsysNotFound(fsysInputFile, .init())
        }

        var archive: FSYSArchive?
        var detectedGame: GSGame?
        var lastError: Error?
        for game in [GSGame.galeOfDarkness, .colosseum, .battleRevolution] {
            do {
                archive = try FSYSArchive(data: data, engine: .defaultEngine(for: game))
                detectedGame = game
                break
            } catch {
                lastError = error
            }
        }
        guard let archive, let detectedGame else {
            throw ProjectSetupErrors.fsysParseFailed(
                fsysInputFile,
                underlying: lastError.map(String.init(describing:)) ?? "unknown",
                .init()
            )
        }

        let stem = fsysInputFile.fileName.withoutExtensions
        let outputFolder = (fsysInputFile.parentFolder ?? Folder("/")).folder("\(stem)_fsys")
        try fileSystem.createFolder(at: outputFolder, overwrite: true)

        // Entry names aren't guaranteed unique within an archive — suffix
        // the entry index on collision.
        var usedNames = Set<String>()
        for (index, entry) in archive.entries.enumerated() {
            var outputName = "\(entry.metadata.name).\(entry.metadata.fileType)"
            if usedNames.contains(outputName) {
                outputName = "\(entry.metadata.name)_\(index).\(entry.metadata.fileType)"
            }
            usedNames.insert(outputName)
            try fileSystem.writeFile(entry.data, at: outputFolder.file(outputName), overwrite: true)
        }

        print("Unpacked \(archive.entries.count) entries from \(fsysInputFile.fileName) (\(detectedGame)) into \(outputFolder.path)")
    }
}
