import GoDFoundation

extension WiiOps {
    struct DumpConfig: Codable {
        enum Operations: Codable {
            case decryptISO(
                isoPath: File,
                outputFolder: Folder,
                overwrite: Bool,
                wiiEngine: Folder,
                dolphinEngine: Folder
            )
        }
        let operations: [OperationConfig<Operations>]
    }
}
