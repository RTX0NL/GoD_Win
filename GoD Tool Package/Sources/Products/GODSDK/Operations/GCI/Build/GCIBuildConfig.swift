import GoDFoundation

extension GCIOps {
    struct BuildConfig: Codable {
        enum Operations: Codable {
            /// Reassemble a `.gci` save from the manifest + region bins
            /// produced by `dumpGCI`.
            case buildGCI(
                inputFolder: Folder,
                gciFile: File,
                overwrite: Bool
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
