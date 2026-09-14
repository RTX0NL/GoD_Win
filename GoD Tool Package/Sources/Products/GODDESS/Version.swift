//
//  Version.swift
//  GODDESS
//
//  The single source of truth for the GODDESS executable's version. Every
//  front-end in this target reads from here rather than hardcoding a literal,
//  so the CLI (`GODDESS --version`) and the MCP server's `serverInfo.version`
//  can never drift apart.
//
//  This is the version of the *product*, not of the shared libraries it is
//  built from: GODOps and the engines are unversioned build inputs, and each
//  executable product in the package owns its own version file like this one.
//
//  On release: bump `semanticVersion` here and tag git to match (a CI check
//  can assert `git describe --tags` == Version.semanticVersion).
//

import Foundation

enum Version {
    /// The semantic version of the tool (e.g. "0.1.0"). This is the value to
    /// bump on release.
    static let semanticVersion = "0.1.0"

    /// The tool's display name, used in `--version` output and elsewhere.
    static let toolName = "GODDESS"

    /// A human-readable version line, e.g. "GODDESS 0.1.0".
    static var versionLine: String {
        "\(toolName) \(semanticVersion)"
    }
}
