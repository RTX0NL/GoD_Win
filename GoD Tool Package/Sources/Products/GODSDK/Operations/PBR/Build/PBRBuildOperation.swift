import GoDFoundation
import GoDEngine
import GeniusSonority
import PBR
import Structs

extension PBROps {

    static func build(
        config: BuildConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree,
        logger: Logger? = nil
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .packPBR(unpackedFolder, fstFolder, overwrite, geniusPath, pbrPath, engines):
                try packPBR(
                    unpackedFolder: unpackedFolder, fstFolder: fstFolder, overwrite: overwrite,
                    geniusPath: geniusPath, pbrPath: pbrPath, engines: engines,
                    fileSystem: fileSystem, logger: logger
                )
            }
        }
    }

    private static func packPBR(
        unpackedFolder: Folder, fstFolder: Folder, overwrite: Bool,
        geniusPath: Folder, pbrPath: Folder, engines: [Folder],
        fileSystem: FileSystemTree, logger: Logger?
    ) throws {
        let geniusEngine = try GeniusSonorityEngine(from: geniusPath, in: fileSystem)
        let pbrEngine = try PBREngine(from: pbrPath, in: fileSystem)

        // The typed-table entries name their reconstruction structs; the FSYS
        // pack resolves those names against these definitions. Resolving each
        // through a combined engine (PBR + the config's engines, e.g. Pokemon)
        // means struct fields that reference a species/move/item enum decode
        // correctly — `getStruct` on one engine only sees its own enums.
        let structEngine = try GenericEngine(combining: [pbrPath] + engines, in: fileSystem)
        var structDefinitions = [String: StructDefinition]()
        for structMap in pbrEngine.structs.entries {
            structDefinitions[structMap.name] = try structEngine.getStruct(structMap.name)
        }

        try geniusEngine.packProject(
            fstRegistryFile: unpackedFolder.file("FST.json"),
            outputFolder: fstFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            structDefinitions: structDefinitions,
            logger: logger
        )
    }
}
