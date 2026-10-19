//
//  ProjectInfo.swift
//  GODOps
//
//  What a project folder is, for an MCP client about to work in it: the
//  GODDESS version that dumped it and whether that is this one, the game,
//  each config with the operations it would run, and what each folder holds.
//
//  The version comes first because it decides whether the client may touch
//  the project at all — engine folders and manifests are written in the
//  dumping version's layout (see the server instructions).
//

import Foundation
import GoDFoundation

extension GODOps {

    public enum ProjectInfoError: Error, CustomStringConvertible {
        case notAProject(File)

        public var description: String {
            switch self {
            case .notAProject(let path):
                return "\(path.nativePath) is not inside a GODDESS project: neither it nor a folder above it "
                    + "has an Engines/Version.txt, or both a Config and an Engines folder."
            }
        }
    }

    /// Describes the project at `path`, which may be the project folder or
    /// anything inside it. `toolVersion` is the caller's own version, to
    /// compare with the one that dumped the project.
    public static func projectInfo(
        at path: File,
        toolVersion: String,
        fileSystem: FileSystemTree = FileSystem.shared
    ) throws -> String {
        guard let root = projectRoot(containing: path, fileSystem: fileSystem) else {
            throw ProjectInfoError.notAProject(path)
        }
        return (
            ["Project: \(root.nativePath)", kind(of: root, fileSystem: fileSystem)]
            + [version(of: root, toolVersion: toolVersion, fileSystem: fileSystem)]
            + configs(in: root, fileSystem: fileSystem)
            + folders(in: root, fileSystem: fileSystem)
        ).joined(separator: "\n")
    }

    // MARK: - Parts

    private static func projectRoot(containing path: File, fileSystem: FileSystemTree) -> Folder? {
        var folder: Folder? = fileSystem.inspectFolder(at: Folder(path.path)) != nil
            ? Folder(path.path)
            : path.parentFolder
        while let candidate = folder {
            let engines = candidate.folder("Engines")
            if fileSystem.inspectFile(at: engines.file(Project.versionStampFileName)) != nil
                || (fileSystem.inspectFolder(at: engines) != nil
                    && fileSystem.inspectFolder(at: candidate.folder("Config")) != nil) {
                return candidate
            }
            folder = candidate.path == "/" ? nil : candidate.parentFolder
        }
        return nil
    }

    private static func kind(of root: Folder, fileSystem: FileSystemTree) -> String {
        if let boot = fileSystem.readFile(at: root.file("Build/Contents/sys/boot.bin")) {
            return "Kind: disc project, game \(gameID(in: boot))"
        }
        let saveFolder = root.folder("Build/Save")
        if let gci = fileSystem.inspectFolder(at: saveFolder)?.files
            .filter({ $0.fileType?.lowercased() == "gci" })
            .min(by: { $0.fileName < $1.fileName }),
           let data = fileSystem.readFile(at: gci) {
            return "Kind: save project, game \(gameID(in: data)) (Build/Save/\(gci.fileName))"
        }
        return "Kind: unknown (no Build/Contents/sys/boot.bin, and no .gci in Build/Save)"
    }

    /// A disc's boot header and a GCI's header both open with the game code
    /// and maker code: six ASCII characters.
    private static func gameID(in data: GoDReadable) -> String {
        let id = data.readStringSafely(atAddress: 0, format: .utf8, maxCharacters: 6)
        return id.isEmpty ? "unknown" : id
    }

    private static func version(of root: Folder, toolVersion: String, fileSystem: FileSystemTree) -> String {
        guard let stamp = fileSystem.readFile(at: root.folder("Engines").file(Project.versionStampFileName))?.allData else {
            return "Version: unknown (no Engines/\(Project.versionStampFileName)). "
                + "Treat it as dumped by a different GODDESS version."
        }
        let version = stamp.string(format: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        if version == toolVersion {
            return "Version: \(version), the same as this server."
        }
        return "Version: \(version), but this server is \(toolVersion). Don't run this server's operations on it; "
            + "move it to this version as the server instructions describe."
    }

    private static func configs(in root: Folder, fileSystem: FileSystemTree) -> [String] {
        let configFolder = root.folder("Config")
        let files = (fileSystem.inspectFolder(at: configFolder)?.files ?? [])
            .filter { $0.fileType?.lowercased() == "json" }
            .sorted { $0.fileName < $1.fileName }
        guard !files.isEmpty else { return ["Configs: none in Config/"] }

        return ["Configs (Config/):"] + files.map { file in
            do {
                let config = try GoddessConfig.decodeFromFile(file, fileSystem: fileSystem)
                let enabled = config.operations.enabledEntries.map(\.name.rawValue)
                let disabled = config.operations.count - enabled.count
                let disabledNote = disabled > 0 ? " (\(disabled) disabled)" : ""
                let operations = enabled.isEmpty ? "no enabled operations" : enabled.joined(separator: ", ")
                return "  \(file.fileName): \(operations)\(disabledNote)"
            } catch {
                let message = String(userMessage(for: error).dropFirst("Error: ".count))
                return "  \(file.fileName): does not decode: \(message.split(separator: "\n").first ?? "")"
            }
        }
    }

    private static func folders(in root: Folder, fileSystem: FileSystemTree) -> [String] {
        guard let contents = fileSystem.inspectFolder(at: root) else { return [] }
        var lines = ["Folders:"]
        if !contents.files.isEmpty {
            let bytes = contents.files.reduce(0) { $0 + (fileSystem.fileSize(at: $1) ?? 0) }
            lines.append("  (top level): \(RunMonitor.count(contents.files.count, "file")), \(byteCount(bytes))")
        }
        for folder in contents.subFolders.sorted(by: { $0.folderName < $1.folderName }) {
            let tally = fileSystem.tally(of: folder) ?? FolderTally(files: 0, bytes: 0)
            lines.append("  \(folder.folderName): \(RunMonitor.count(tally.files, "file")), \(byteCount(tally.bytes))")
        }
        return lines
    }

    /// "10 B", "3.1 KB", "1.4 GB" (1024-based).
    static func byteCount(_ bytes: Int) -> String {
        guard bytes >= 1024 else { return "\(bytes) B" }
        var value = Double(bytes) / 1024
        for unit in ["KB", "MB", "GB"] {
            if value < 1024 || unit == "GB" {
                return String(format: "%.1f \(unit)", value)
            }
            value /= 1024
        }
        return "\(bytes) B"
    }
}
