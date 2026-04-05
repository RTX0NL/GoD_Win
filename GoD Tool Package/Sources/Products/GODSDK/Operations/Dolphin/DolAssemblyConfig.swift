import GoDFoundation

extension DolAssembly {
    struct Config: Codable {
        let codeFolder: Folder
        let outputDolPath: File
        let dolphinEngine: Folder
    }
}
