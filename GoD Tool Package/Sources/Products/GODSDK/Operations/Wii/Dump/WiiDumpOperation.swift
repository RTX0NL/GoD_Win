import GoDFoundation
import GoDEngine
import Dolphin
import Wii

extension WiiOps {
    static func dump(
        config: DumpConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .decryptISO(isoPath, outputFolder, overwrite, wiiEnginePath, dolphinEnginePath):
                guard let commonKeyFile = settings.wiiCommonKeyFile else {
                    throw WiiErrors.missingCommonKey(.init())
                }
                let commonKey = try WiiOps.loadCommonKey(from: commonKeyFile, fileSystem: fileSystem)
                logger?.log(.info("Loaded common key from \(commonKeyFile.path)"))

                let wiiEngine = try WiiEngine(from: wiiEnginePath, in: fileSystem)
                let dolphinEngine = try DolphinEngine(from: dolphinEnginePath, in: fileSystem)
                guard let data = fileSystem.readFile(at: isoPath) else {
                    throw FSTErrors.fileNotFound(isoPath, .init())
                }

                logger?.log(.warning("Decrypting Wii ISO: \(isoPath.fileName)"))
                let iso = try WiiISO(
                    data: data,
                    commonKey: commonKey,
                    wiiEngine: wiiEngine,
                    dolphinEngine: dolphinEngine,
                    logger: logger
                )
                fileSystem.importFST(iso, from: Folder("/"), to: outputFolder, overwrite: overwrite, logger: logger)
                logger?.log(.warning("Wii ISO decryption complete"))
            }
        }
    }

    static func loadCommonKey(from file: File, fileSystem: FileSystemTree) throws -> [UInt8] {
        guard let keyData = fileSystem.readFile(at: file) else {
            throw WiiErrors.commonKeyNotFound(file, .init())
        }

        // Read file as UTF-8 text, trim whitespace, parse as 32-char hex string
        guard let hexString = keyData.readString(atAddress: 0, format: .utf8, maxCharacters: keyData.length) else {
            throw WiiErrors.invalidCommonKey(.init())
        }
        let trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 32 else {
            throw WiiErrors.invalidCommonKey(.init())
        }
        var bytes = [UInt8]()
        var index = trimmed.startIndex
        for _ in 0..<16 {
            let nextIndex = trimmed.index(index, offsetBy: 2)
            guard let byte = UInt8(trimmed[index..<nextIndex], radix: 16) else {
                throw WiiErrors.invalidCommonKey(.init())
            }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes
    }
}

enum WiiErrors: Error, CustomStringConvertible {
    case missingCommonKey(ErrorTrace)
    case commonKeyNotFound(File, ErrorTrace)
    case invalidCommonKey(ErrorTrace)

    var description: String {
        switch self {
        case .missingCommonKey(let trace):
            return "Error: No Wii common key file specified in settings (wiiCommonKeyFile).\n\(trace)"
        case .commonKeyNotFound(let file, let trace):
            return "Error: Wii common key file not found: \(file.path)\n\(trace)"
        case .invalidCommonKey(let trace):
            return "Error: Invalid Wii common key. File must contain a 32-character hex string.\n\(trace)"
        }
    }
}
