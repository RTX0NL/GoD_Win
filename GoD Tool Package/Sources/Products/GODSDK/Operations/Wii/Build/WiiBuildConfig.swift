import GoDFoundation

extension WiiOps {
    struct BuildConfig: Codable {
        enum Operations: Codable {
            case encryptISO(
                fstPath: Folder,
                isoPath: File,
                overwrite: Bool,
                wiiEngine: Folder,
                dolphinEngine: Folder
            )
            case fillISO(
                isoPath: File,
                size: Int
            )
        }
        let operations: [OperationConfig<Operations>]
    }
}
