import GoDFoundation

extension ColoXD {
    static func build(
        config: BuildConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree
    ) throws {
        config.operations.enabledEntries.forEach { operation in
            switch operation {
            case .pass: break
            }
        }
    }
}
