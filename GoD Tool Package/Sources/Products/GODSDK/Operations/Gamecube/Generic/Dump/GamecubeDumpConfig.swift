import GoDFoundation

extension Gamecube {
    struct DumpConfig: Codable {
        enum Operations: Codable {
            case unpackISO(
                isoPath: File,
                fstFolder: Folder,
                overwrite: Bool,
                dolphinEngine: Folder,
                gamecubeEngine: Folder
            )
        }
        
        let operations: [OperationConfig<Operations>]
    }
}
