import GoDFoundation

/// Reads manifests from the filesystem and loads files in manifest order.
public struct ManifestReader {

    public init() {}

    /// Read a data section manifest from a folder.
    public func readDataManifest(
        from folder: Folder,
        fileSystem: FileSystemTree
    ) -> DataSectionManifest? {
        let manifestFile = folder.file("manifest.json")
        guard let data = fileSystem.readFile(at: manifestFile)?.allData else { return nil }
        return try? JSONDecoder().decode(DataSectionManifest.self, from: data)
    }

    /// Read a text section manifest from a folder.
    public func readTextManifest(
        from folder: Folder,
        fileSystem: FileSystemTree
    ) -> TextSectionManifest? {
        let manifestFile = folder.file("manifest.json")
        guard let data = fileSystem.readFile(at: manifestFile)?.allData else { return nil }
        return try? JSONDecoder().decode(TextSectionManifest.self, from: data)
    }

    /// Load text section assembly files in manifest order.
    /// Falls back to recursive filesystem traversal if no manifest exists.
    public func loadTextSectionFiles(
        sectionName: String,
        codeFolder: Folder,
        fileSystem: FileSystemTree
    ) -> [(name: String, content: String)] {
        let sectionFolder = codeFolder.folder(sectionName)

        // Try manifest first
        if let manifest = readTextManifest(from: sectionFolder, fileSystem: fileSystem) {
            var files = [(name: String, content: String)]()
            for filePath in manifest.files {
                let file = sectionFolder.file(filePath)
                if let data = fileSystem.readFile(at: file)?.allData {
                    files.append((name: filePath, content: data.string(format: .utf8)))
                }
            }
            return files
        }

        // Fall back to folder inspection
        if fileSystem.inspectFolder(at: sectionFolder) != nil {
            return collectAssemblyFilesRecursively(from: sectionFolder, fileSystem: fileSystem)
        }

        // Fall back to single file
        let sectionFile = codeFolder.file("\(sectionName).s")
        if let data = fileSystem.readFile(at: sectionFile)?.allData {
            return [(sectionName + ".s", data.string(format: .utf8))]
        }

        return []
    }

    /// Recursively collect .s files from a folder (fallback when no manifest exists)
    private func collectAssemblyFilesRecursively(
        from folder: Folder,
        fileSystem: FileSystemTree
    ) -> [(name: String, content: String)] {
        guard let contents = fileSystem.inspectFolder(at: folder) else { return [] }

        var files = [(name: String, content: String)]()

        for file in contents.files where file.fileType == "s" {
            if let data = fileSystem.readFile(at: file)?.allData {
                files.append((name: file.fileName, content: data.string(format: .utf8)))
            }
        }

        for subFolder in contents.subFolders {
            files.append(contentsOf: collectAssemblyFilesRecursively(from: subFolder, fileSystem: fileSystem))
        }

        return files
    }
}
