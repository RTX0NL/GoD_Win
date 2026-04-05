import GoDFoundation
import Dolphin

extension Gamecube {
    struct BuildConfig: Codable {
        enum Operations: Codable {
            case buildISO(
                fstPath: Folder,
                isoPath: File,
                overwrite: Bool,
                dolphinEngine: Folder,
                gamecubeEngine: Folder
            )
            case fillISO(
                isoPath: File,
                size: Int
            )
        }
        
        let operations: [OperationConfig<Operations>]
    }
}
