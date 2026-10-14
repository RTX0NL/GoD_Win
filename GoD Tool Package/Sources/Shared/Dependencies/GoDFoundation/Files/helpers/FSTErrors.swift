//
//  File.swift
//
//
//  Created by Stars Momodu on 09/06/2024.
//

import Foundation

public enum FSTErrors: GoDError {
    case fileNotFound(File, ErrorTrace)
    case folderNotFound(Folder, ErrorTrace)
    case failedToWriteFile(File, ErrorTrace)
    /// A write was refused because something already exists at the path and
    /// the caller passed `overwrite: false`.
    case itemExists(String, ErrorTrace)
    case failedToMoveFile(File, File, ErrorTrace)
    case failedToDeleteFile(File, ErrorTrace)
    case failedToCreateFolder(Folder, ErrorTrace)
    case failedToMoveFolder(Folder, Folder, ErrorTrace)
    case failedToDeleteFolder(Folder, ErrorTrace)
    /// A path had no parent folder to write into (e.g. the filesystem root).
    case invalidPath(String, ErrorTrace)
    /// The underlying file system rejected the operation.
    case underlying(String, Error, ErrorTrace)

    public var description: String {
        switch self {
        case let .fileNotFound(file, errorTrace):
            return "Error: file not found: \(file)\n\(errorTrace)"
        case let .folderNotFound(folder, errorTrace):
            return "Error: folder not found: \(folder)\n\(errorTrace)"
        case let .failedToWriteFile(file, errorTrace):
            return "Error: failed to write file: \(file)\n\(errorTrace)\n\(Self.writeAdvice(file.nativePath, isFolder: false))"
        case let .itemExists(path, errorTrace):
            return "Error: refusing to overwrite existing item: \(path)\n\(errorTrace)\nPass overwrite: true to replace it"
        case let .failedToMoveFile(from, to, errorTrace):
            return "Error: failed to move file \(from) to \(to)\n\(errorTrace)"
        case let .failedToDeleteFile(file, errorTrace):
            return "Error: failed to delete file: \(file)\n\(errorTrace)"
        case let .failedToCreateFolder(folder, errorTrace):
            return "Error: failed to create folder: \(folder)\n\(errorTrace)\n\(Self.writeAdvice(folder.nativePath, isFolder: true))"
        case let .failedToMoveFolder(from, to, errorTrace):
            return "Error: failed to move folder \(from) to \(to)\n\(errorTrace)"
        case let .failedToDeleteFolder(folder, errorTrace):
            return "Error: failed to delete folder: \(folder)\n\(errorTrace)"
        case let .invalidPath(path, errorTrace):
            return "Error: invalid path: \(path)\n\(errorTrace)"
        case let .underlying(operation, error, errorTrace):
            return "Error: \(operation) failed: \(error)\n\(errorTrace)"
        }
    }

    /// A write past MAX_PATH on Windows gets advice naming that limit;
    /// anything else keeps the generic advice.
    private static func writeAdvice(_ nativePath: String, isFolder: Bool) -> String {
        WindowsLongPaths.hint(forNativePath: nativePath, isFolder: isFolder)
            ?? "Please check free space and write permissions"
    }
}
