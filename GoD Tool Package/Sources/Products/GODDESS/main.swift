//
//  main.swift
//  GODDESS
//
//  Thin CLI shell over the shared `GODOps` dispatch library. Two modes:
//    GODDESS <file> [<file> ...]   — process each input by extension
//    GODDESS mcp                   — run a stdio MCP server (see MCP/)
//  All real work lives in GODOps, so the MCP server drives the exact same
//  code paths as the command line.
//
//  Every input path is resolved to an absolute path against the process
//  working directory before it reaches GODOps. Downstream code (project
//  folder naming, `Folder` construction, `FileSystem.extendPath`) assumes
//  absolute paths, so normalizing once here keeps `GODDESS game.iso` and
//  `GODDESS ./game.iso` working the same as a fully-qualified path.
//
//  Exit status is EXIT_FAILURE if *any* input failed, so shell scripts,
//  CI, and the generated Dump.sh / Build.sh launchers can chain safely.
//  Each input is still attempted independently — one bad file doesn't
//  abandon the rest of the batch.
//

import Foundation
import GoDFoundation
import GODOps

/// Resolves `argument` to an absolute path against the process working
/// directory. Absolute paths and `~`-relative paths pass through
/// (expanded); everything else is joined onto the CWD and normalized so
/// `.`/`..` components don't survive into `File`/`Folder`.
func absolutePath(for argument: String) -> String {
    let expanded = NSString(string: argument).expandingTildeInPath
    if expanded.hasPrefix("/") {
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return URL(fileURLWithPath: expanded, relativeTo: cwd).standardizedFileURL.path
}

let arguments = Array(CommandLine.arguments.dropFirst())

guard let first = arguments.first else {
    FileHandle.standardError.write(Data("No input files provided. Exiting program.\n".utf8))
    FileHandle.standardError.write(Data("Usage: GODDESS <file.iso|.gci|.fsys|.json> ...   or   GODDESS mcp\n".utf8))
    exit(EXIT_FAILURE)
}

if first == "--version" || first == "-v" || first == "version" {
    print(Version.versionLine)
    exit(EXIT_SUCCESS)
} else if first == "mcp" {
    // Start the Model Context Protocol server on stdio and block until the
    // client disconnects.
    await runMCPServer()
} else {
    var failed = false
    for inputFile in arguments.map({ File(nativePath: absolutePath(for: $0)) }) {
        // Skip the executable path itself if it slips into the argument list.
        guard inputFile.nativePath != Bundle.main.executablePath else { continue }
        do {
            try GODOps.process(inputFile: inputFile, toolVersion: Version.semanticVersion)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            failed = true
        }
    }
    if failed {
        exit(EXIT_FAILURE)
    }
}
