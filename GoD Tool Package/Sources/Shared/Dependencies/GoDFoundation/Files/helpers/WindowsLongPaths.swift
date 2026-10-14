//
//  WindowsLongPaths.swift
//
//  Explains write failures caused by Windows' MAX_PATH limit. A dump writes
//  paths of 270+ characters; past MAX_PATH Windows only accepts them when
//  the process is long-path aware (GODDESS embeds a manifest for that) *and*
//  the machine has LongPathsEnabled=1. Without this, such a failure reads
//  "Please check free space and write permissions", which sends people
//  looking in the wrong place.
//

#if os(Windows)
import WinSDK
#endif

public enum WindowsLongPaths {
    /// MAX_PATH, counting the terminating NUL.
    public static let maxPath = 260
    /// `CreateDirectory` keeps room for an 8.3 file name inside the folder.
    public static let maxFolderPath = maxPath - 12

    static let registryKey = #"SYSTEM\CurrentControlSet\Control\FileSystem"#
    static let registryValue = "LongPathsEnabled"

    /// The advice for a failed write to `nativePath`, or nil when the path
    /// is short enough that MAX_PATH can't be the cause.
    public static func hint(forNativePath nativePath: String, isFolder: Bool, longPathsEnabled: Bool) -> String? {
        let length = nativePath.utf16.count
        let limit = isFolder ? maxFolderPath : maxPath
        guard length >= limit else { return nil }
        let over = "The path is \(length) characters, over Windows' MAX_PATH limit of \(limit - 1)."
        if longPathsEnabled {
            return over + " \(registryValue) is set, so this GODDESS build is probably missing its"
                + " longPathAware manifest. Rebuild it, or move the project to a shorter folder."
        }
        return over + " Long paths are disabled on this machine: set the DWORD \(registryValue) to 1"
            + " under HKLM\\\(registryKey) (needs admin rights), or move the project to a shorter folder."
    }

    /// `hint(forNativePath:isFolder:longPathsEnabled:)` with the setting read
    /// from the registry. Always nil off Windows.
    static func hint(forNativePath nativePath: String, isFolder: Bool) -> String? {
        #if os(Windows)
        return hint(forNativePath: nativePath, isFolder: isFolder, longPathsEnabled: registryLongPathsEnabled())
        #else
        return nil
        #endif
    }

    #if os(Windows)
    private static func registryLongPathsEnabled() -> Bool {
        // HKEY_LOCAL_MACHINE and RRF_RT_REG_DWORD are C macros Swift can't import.
        let localMachine = HKEY(bitPattern: Int(Int32(bitPattern: 0x8000_0002)))
        let dwordOnly = DWORD(0x0000_0010)
        var value: DWORD = 0
        var size = DWORD(MemoryLayout<DWORD>.size)
        let status = registryKey.withCString(encodedAs: UTF16.self) { key in
            registryValue.withCString(encodedAs: UTF16.self) { name in
                RegGetValueW(localMachine, key, name, dwordOnly, nil, &value, &size)
            }
        }
        return status == 0 && value == 1
    }
    #endif
}
