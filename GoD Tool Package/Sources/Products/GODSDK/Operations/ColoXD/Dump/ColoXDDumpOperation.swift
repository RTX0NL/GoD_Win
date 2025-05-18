//
//  ColosseumXDDumpOperation.swift
//  
//
//  Created by Stars Momodu on 28/08/2024.
//

import GoDFoundation
import Dolphin
import GeniusSonority

extension ColoXD {
    private enum ProjectFolders {
        static let assetsFolder = Folder("/Assets")
        
        static let audioFolder = assetsFolder.folder("/Sounds")
        static let criesFolder = audioFolder.folder("/pokemon_cries")
        static let soundFontsFolder = audioFolder.folder("/sound_fonts")
        static let sequencedFolder = audioFolder.folder("/sequenced")
        static let streamedFolder = audioFolder.folder("/streamed")
        
        static let modelsFolder = assetsFolder.folder("/Models")
        static let datFolder = modelsFolder.folder("/characters-and-objects")
        static let pkxFolder = modelsFolder.folder("/battle_models")
        static let wzxFolder = modelsFolder.folder("/effects")
        static let camFolder = modelsFolder.folder("/cameras")
        
        static let mapsFolder = modelsFolder.folder("/Maps")
        static let rdatFolder = mapsFolder.folder("/models")
        static let ccdFolder = mapsFolder.folder("/collision")
        
        static let imagesFolder = assetsFolder.folder("/Images")
        static let pokemonFolder = imagesFolder.folder("/pokemon")
        static let facesFolder = pokemonFolder.folder("/faces")
        static let bodiesFolder = pokemonFolder.folder("/pc-box")
        static let dancerFolder = pokemonFolder.folder("/purify-chamber")
        static let menusFolder = imagesFolder.folder("/menus")
        
        static let flashFolder = assetsFolder.folder("/Flash-menus") // gsw
        static let videosFolder = assetsFolder.folder("/Videos") // thp
        
        static let dialogueFolder = assetsFolder.folder("/Text")
        static let messagesFolder = dialogueFolder.folder("/messages")
        static let fontsFolder = dialogueFolder.folder("/fonts")
        
        static let miscFolder = assetsFolder.folder("/Misc")
        
        static let sourcesFolder = Folder("/Data")
        
        static let fsysFolder = sourcesFolder.folder("/Archives") // fsys metadata
        static let mapScriptsFolder = sourcesFolder.folder("/Maps")
        static let dataTablesFolder = sourcesFolder.folder("/Data-tables")
        
        static let allFolders = [
            assetsFolder,
            audioFolder, criesFolder, soundFontsFolder, sequencedFolder, streamedFolder,
            modelsFolder, datFolder, pkxFolder, wzxFolder, camFolder,
            mapsFolder, rdatFolder, ccdFolder,
            imagesFolder, pokemonFolder, facesFolder, bodiesFolder, dancerFolder, menusFolder,
            flashFolder, videosFolder,
            dialogueFolder, messagesFolder, fontsFolder,
            miscFolder,
            sourcesFolder,
            fsysFolder, mapScriptsFolder, dataTablesFolder
        ]
    }
    
    static func dump(
        config: DumpConfig,
        settings: GoddessSettings,
        fileSystem: FileSystemTree
    ) throws {
        try config.operations.enabledEntries.forEach { operation in
            switch operation {
            case let .dumpColosseum(fstFolder, outputFolder, overwrite, dolphinPath, geniusPath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let geniusEngine = try GeniusSonorityEngine(from: geniusPath, in: fileSystem)
                
                let output = try dumpColosseum(
                    fileSystem: fileSystem,
                    rootFolder: fstFolder,
                    dolphinEngine: dolphinEngine,
                    gsEngine: geniusEngine,
                    settings: settings
                )
                
                fileSystem.importFST(output, from: "/", to: outputFolder, overwrite: overwrite)
            case let .dumpXD(fstFolder, outputFolder, overwrite, dolphinPath, geniusPath):
                let dolphinEngine = try DolphinEngine(from: dolphinPath, in: fileSystem)
                let geniusEngine = try GeniusSonorityEngine(from: geniusPath, in: fileSystem)
                
                let output = try dumpXD(
                    fileSystem: fileSystem,
                    rootFolder: fstFolder,
                    dolphinEngine: dolphinEngine,
                    gsEngine: geniusEngine,
                    settings: settings
                )
                
                fileSystem.importFST(output, from: "/", to: outputFolder, overwrite: overwrite)
            }
        }
    }
    
    private static func dumpColosseum(
        fileSystem: FileSystemTree,
        rootFolder: Folder,
        dolphinEngine: DolphinEngine,
        gsEngine: GeniusSonorityEngine,
        settings: GoddessSettings
    ) throws -> FileSystemTree {
        try dumpColosseumXD(
            fileSystem: fileSystem,
            rootFolder: rootFolder,
            dolphinEngine: dolphinEngine,
            gsEngine: gsEngine,
            settings: settings
        )
    }
    
    private static func dumpXD(
        fileSystem: FileSystemTree,
        rootFolder: Folder,
        dolphinEngine: DolphinEngine,
        gsEngine: GeniusSonorityEngine,
        settings: GoddessSettings
    ) throws -> FileSystemTree {
        try dumpColosseumXD(
            fileSystem: fileSystem,
            rootFolder: rootFolder,
            dolphinEngine: dolphinEngine,
            gsEngine: gsEngine,
            settings: settings
        )
    }
    
    private static func dumpColosseumXD(
        fileSystem: FileSystemTree,
        rootFolder: Folder,
        dolphinEngine: DolphinEngine,
        gsEngine: GeniusSonorityEngine,
        settings: GoddessSettings
    ) throws -> FileSystemTree {
        
        let projectFileSystem = InMemoryFST()
        
        ProjectFolders.allFolders.forEach { folder in
            _ = projectFileSystem.createFolder(at: folder, overwrite: true)
        }
        
        func dump(folder: Folder) throws {
            guard let folderData = fileSystem.inspectFolder(at: folder) else {
                throw FSTErrors.folderNotFound(folder, .init())
            }
            
            // get gsfsys
            
            
            try folderData.files.forEach { path in
                guard let file = fileSystem.readFile(at: path) else { return }
                let fileName = path.fileName
                
                if path.fileType == "fsys" {
                    let archive = try FSYSArchive(data: file, engine: gsEngine)
                    
                    
                    
                    _ = projectFileSystem.writeFile(
                        file,
                        at: ProjectFolders.fsysFolder.file(fileName),
                        overwrite: true
                    )
                }
            }
            
            try folderData.subFolders.forEach(dump)
        }
        
        try dump(folder: rootFolder)
        return projectFileSystem
    }
    
}
