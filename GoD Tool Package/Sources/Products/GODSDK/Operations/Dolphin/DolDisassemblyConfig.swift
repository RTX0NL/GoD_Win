import GoDFoundation

enum DolDisassembly {
    struct Config: Codable {
        let dolPath: File
        let outputFolder: Folder
        let symbolMapPath: File?
        let dolphinEngine: Folder
    }
}
