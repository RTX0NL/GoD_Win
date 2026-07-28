//
//  GoDVersion.swift
//
//  The single source of truth for the tool's version. Every front-end reads
//  from here rather than hardcoding a literal, so the CLI (`GODDESS --version`),
//  the MCP server's `serverInfo.version`, and anything else that reports the
//  version can never drift apart.
//
//  On release: bump `semanticVersion` here and tag git to match (a CI check
//  can assert `git describe --tags` == GoDVersion.semanticVersion). This file
//  is deliberately dependency-free and low in the graph so any module can
//  import it via GoDFoundation.
//

import Foundation

public enum GoDVersion {
    /// The semantic version of the tool (e.g. "0.1.0"). This is the value to
    /// bump on release.
    public static let semanticVersion = "0.1.0"

    /// The tool's display name, used in `--version` output and elsewhere.
    public static let toolName = "GODDESS"

    /// A human-readable version line, e.g. "GODDESS 0.1.0".
    public static var versionLine: String {
        "\(toolName) \(semanticVersion)"
    }
}
