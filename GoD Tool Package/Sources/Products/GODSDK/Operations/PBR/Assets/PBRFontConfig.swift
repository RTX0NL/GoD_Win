//
//  PBRFontConfig.swift
//  GODOps
//
//  Config surface for Battle Revolution's font operations.
//
//  Separate from the Colosseum/XD font ops rather than shared with them,
//  because `.fnt` names two unrelated formats and the *operation you invoke*
//  is what says which one you mean. Nothing sniffs bytes to decide; a config
//  naming a PBR operation is the statement that these are PBR fonts.
//
//  Both PBR font formats route through here — the bitmap `.FNT` and the 3D
//  `.f3d` — because the file-format registry already picks the handler from
//  the extension. One pair of operations covers both, and adding a third PBR
//  font format later would need no new operation.
//

import GoDFoundation

enum PBRFontDump {

    /// One font file to its editable artifacts.
    struct SingleConfig: Codable {
        let fontPath: File
        /// Artifacts land in a subfolder named after the font, because a font
        /// dumps to several files (a manifest plus an atlas or an SVG) and
        /// two fonts in one folder would otherwise interleave.
        let outputFolder: Folder
        let overwrite: Bool

        init(fontPath: File, outputFolder: Folder, overwrite: Bool = false) {
            self.fontPath = fontPath
            self.outputFolder = outputFolder
            self.overwrite = overwrite
        }
    }

    /// Every PBR font under a folder, mirroring its layout into the output.
    struct BatchConfig: Codable {
        let fontsFolder: Folder
        let outputFolder: Folder
        let overwrite: Bool

        init(fontsFolder: Folder, outputFolder: Folder, overwrite: Bool = false) {
            self.fontsFolder = fontsFolder
            self.outputFolder = outputFolder
            self.overwrite = overwrite
        }
    }
}

enum PBRFontBuild {

    /// One artifact bundle back to its font binary.
    struct SingleConfig: Codable {
        /// Folder holding one font's manifest and its companion asset.
        let fontFolder: Folder
        let outputFolder: Folder
        let overwrite: Bool

        init(fontFolder: Folder, outputFolder: Folder, overwrite: Bool = true) {
            self.fontFolder = fontFolder
            self.outputFolder = outputFolder
            self.overwrite = overwrite
        }
    }

    /// Every artifact bundle under a folder. Each font's bundle is its own
    /// subfolder, which is the layout the batch dump produces.
    struct BatchConfig: Codable {
        /// Folder of per-font bundles, which is what the batch dump produces.
        let fontsFolder: Folder
        let outputFolder: Folder
        let overwrite: Bool

        init(fontsFolder: Folder, outputFolder: Folder, overwrite: Bool = true) {
            self.fontsFolder = fontsFolder
            self.outputFolder = outputFolder
            self.overwrite = overwrite
        }
    }
}
