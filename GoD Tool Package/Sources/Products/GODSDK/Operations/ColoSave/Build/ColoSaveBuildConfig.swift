import GoDFoundation

extension ColoSaveOps {
    struct BuildConfig: Codable {
        enum Operations: Codable {
            case buildColosseumSave(
                inputFolder: Folder,
                unpackedFolder: Folder,
                overwrite: Bool,
                decrypted: Bool,
                colosseumEngine: Folder
            )
        }

        let operations: [OperationConfig<Operations>]
    }
}
