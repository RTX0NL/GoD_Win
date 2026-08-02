//
//  LauncherScript.swift
//  GODOps
//
//  The one-line `Scripts/Dump.sh` / `Scripts/Build.sh` launchers written
//  into a new project.
//

import Foundation
import GoDFoundation

enum LauncherScript {

    /// Quotes a path for POSIX `sh`.
    ///
    /// Escaping only spaces (what this used to do) breaks on every other
    /// character the shell treats specially, and ROM filenames are full of
    /// them — `Pokemon XD (USA).iso` alone contains parentheses, which the
    /// shell reads as a subshell. Single quotes suppress all of it; the only
    /// character that can't appear inside them is `'` itself, which is closed,
    /// escaped and reopened.
    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Body of a launcher that runs `configFile` through `executablePath`.
    ///
    /// The script `cd`s to its own directory first. The config path is
    /// relative to `Scripts/`, so without that it only resolved correctly
    /// when the caller happened to already be inside `Scripts/` — running
    /// `./Scripts/Dump.sh` from the project root looked for the config one
    /// level above the project.
    static func body(executablePath: String, configFile: File) -> String {
        let relativeConfig = Folder("..").file(configFile.path).nativePath
        return """
        #!/bin/sh
        cd "$(dirname "$0")" || exit 1
        exec \(shellQuoted(executablePath)) \(shellQuoted(relativeConfig))
        """
    }

    /// Writes a launcher for each config into `projectFolder/Scripts/`,
    /// named after the config (`Dump-Config.json` -> `Dump.sh`).
    static func write(
        for configFiles: [File],
        in projectFolder: Folder,
        fileSystem: FileSystemTree
    ) throws {
        guard let executablePath = Bundle.main.executablePath else { return }
        for config in configFiles {
            let name = config.fileName.replacingOccurrences(of: "-Config.json", with: ".sh")
            let file = projectFolder.folder("Scripts").file(name)
            let script = body(executablePath: executablePath, configFile: config)
            try fileSystem.writeFile(script.data(format: .utf8), at: file, overwrite: false)
            // A no-op on trees without permissions.
            fileSystem.setExecutable(file: file)
        }
    }
}
