import GoDFoundation

extension DolAssembly {
    struct Config: Codable {
        let codeFolder: Folder
        let outputDolPath: File
        let symbolMapPath: File?
        let dolphinEngine: Folder
    }
}
