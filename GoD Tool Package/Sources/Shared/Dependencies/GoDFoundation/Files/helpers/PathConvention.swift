//
//  PathConvention.swift
//
//  Translation between the logical paths `File` and `Folder` carry and the
//  platform's native spelling.
//
//  `File` and `Folder` are an abstraction, not a passthrough for whatever the
//  host OS uses. Internally a path is always POSIX-shaped — `/`-separated,
//  absolute paths starting at `/` — because that is what the *data* uses:
//  disc images, FSYS archives and engine JSON all describe `/files/...`
//  regardless of the machine reading them. A project laid out on Windows must
//  address the same logical paths as one on macOS or the configs wouldn't be
//  portable.
//
//  That only works if the native spelling is confined to the boundary. The
//  leak was `PathRepresentable.url`, which handed the logical path straight to
//  `URL(fileURLWithPath:)`: on Windows that reads `/Data/Text` as rooted on the
//  current drive, and a real `C:\...` path can't be expressed as a `Folder` at
//  all — `Folder.init` traps on it. So conversion happens here, and only the
//  file-system implementations use it.
//
//  Windows mapping: a drive-qualified path becomes a logical path whose first
//  component is the drive, `C:\Games\rom.iso` <-> `/C:/Games/rom.iso`. That is
//  reversible, keeps logical paths absolute, and leaves the drive visible
//  rather than silently dropped.
//
//  A network share has no drive, so it gets a root of its own:
//  `\\server\share\a.iso` <-> `/UNC/server/share/a.iso`, the name Windows
//  itself gives that namespace in `\\?\UNC\…`. The `\\?\` prefix only turns
//  off Win32 path parsing, so it is dropped on the way in.
//

import Foundation

public enum PathConvention {
    case posix
    case windows

    /// The convention of the machine this build is running on.
    public static var current: PathConvention {
        #if os(Windows)
        return .windows
        #else
        return .posix
        #endif
    }
}

public enum PlatformPath {

    /// The logical root of a network share: `/UNC/server/share/…`.
    private static let uncRoot = "UNC"

    /// Matches a logical path's leading drive component, e.g. `/C:/…`.
    private static let driveComponent = try! NSRegularExpression(pattern: "^[A-Za-z]:$")

    private static func isDrive(_ component: String) -> Bool {
        let range = NSRange(component.startIndex..., in: component)
        return driveComponent.firstMatch(in: component, range: range) != nil
    }

    /// Logical path -> the spelling the platform's file APIs expect.
    public static func native(
        from logical: String,
        convention: PathConvention = .current
    ) -> String {
        guard convention == .windows else { return logical }

        // Relative paths only need their separators swapped.
        guard logical.hasPrefix("/") else {
            return logical.replacingOccurrences(of: "/", with: "\\")
        }

        var components = logical.split(separator: "/").map(String.init)
        if components.count >= 3, components[0] == uncRoot {
            return #"\\"# + components.dropFirst().joined(separator: "\\")
        }
        guard let first = components.first, isDrive(first) else {
            // No drive in the logical path: keep it rooted on the current
            // drive, which is what a leading separator means on Windows.
            return "\\" + components.joined(separator: "\\")
        }
        components.removeFirst()
        return components.isEmpty
            ? first + "\\"
            : first + "\\" + components.joined(separator: "\\")
    }

    /// Whether `path` is spelled the platform's way rather than logically: it
    /// names a drive (`C:`, `C:/…`, `C:\…`) or uses `\` separators. Logical
    /// paths, bare relative names included, never are.
    public static func isNativeSpelling(
        _ path: String,
        convention: PathConvention = .current
    ) -> Bool {
        guard convention == .windows else { return false }
        if path.contains("\\") { return true }
        let first = path.split(separator: "/", omittingEmptySubsequences: false).first ?? ""
        return isDrive(String(first))
    }

    /// Native path -> the logical form `File` and `Folder` store.
    ///
    /// Use this wherever a path arrives from outside: command-line arguments,
    /// `NSTemporaryDirectory()`, `Bundle` resource URLs. Passing a native path
    /// to `File`/`Folder` directly works by accident on POSIX and traps on
    /// Windows.
    public static func logical(
        from native: String,
        convention: PathConvention = .current
    ) -> String {
        guard convention == .windows else { return native }

        var unified = native.replacingOccurrences(of: "\\", with: "/")
        // `\\?\C:\…` and `\\?\UNC\server\…` are ordinary paths with parsing
        // switched off: what follows the prefix is the path.
        if unified.hasPrefix("//?/") {
            unified.removeFirst(4)
            if unified.hasPrefix(uncRoot + "/") {
                unified = "//" + unified.dropFirst(uncRoot.count + 1)
            }
        }
        let components = unified.split(separator: "/").map(String.init)

        if unified.hasPrefix("//"), components.count >= 2 {
            return "/" + ([uncRoot] + components).joined(separator: "/")
        }
        if let first = components.first, isDrive(first) {
            return "/" + components.joined(separator: "/")
        }
        if unified.hasPrefix("/") {
            return "/" + components.joined(separator: "/")
        }
        // Relative: keep it relative, in the form `Folder.init` accepts.
        let joined = components.joined(separator: "/")
        if joined.hasPrefix(".") { return joined }
        return joined.isEmpty ? "." : "./" + joined
    }
}

public extension PathRepresentable {
    /// This path in the host platform's spelling. Only the file-system
    /// implementations should need it.
    var nativePath: String { PlatformPath.native(from: path) }

    /// Builds from a path supplied by the platform (argv, a `Bundle` URL, the
    /// temporary directory) rather than from our own logical namespace.
    init(nativePath: String) {
        self.init(PlatformPath.logical(from: nativePath))
    }
}
