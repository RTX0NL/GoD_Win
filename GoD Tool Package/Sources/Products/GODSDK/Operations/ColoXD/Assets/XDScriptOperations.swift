//
//  XDScriptOperations.swift
//  GODOps
//
//  XD scripts (`.scd`) -> readable source, one `.xds` file per script.
//
//  Decompile only. Colosseum scripts round-trip (`dumpColoScripts` /
//  `buildColoScripts`); XD's dialect has a decompiler but no compiler yet,
//  so there is no build counterpart and the text says so at its top.
//

import Foundation
import GoDFoundation
import XD

extension ColoXD {

    static func dumpXDScripts(
        in folder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let decompiler = XDScriptDecompiler()
        try dumpBatch(
            in: folder,
            matching: { $0.fileType == "scd" },
            label: "XD script",
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                guard let data = fileSystem.readFile(at: file)?.allData else {
                    throw FSTErrors.fileNotFound(file, .init())
                }
                let script = try XDScript(data: data)
                let text = decompiler.decompile(script, fileName: file.fileName)
                return [FileData(fileName: "\(stem).xds", data: GoDData(string: text, format: .utf8))]
            }
        )
    }
}
