//
//  PatchOps.swift
//  GODOps
//
//  Shared bits of the two patch operations. Nothing here reads engine data:
//  a patch format is fixed knowledge about a file layout, so the format name
//  plus the patch's own magic fully determine the codec.
//

import GoDFoundation

enum PatchOps {

    /// The format to read `patch` as: the named one, checked against the
    /// magic, or else whatever the magic says.
    static func resolveFormat(named: PatchFormat?, of patch: GoDReadable, file: File) throws -> PatchFormat {
        let detected = PatchFormat.detect(patch)
        guard let named else {
            guard let detected else {
                throw PatchErrors.unrecognizedPatchFormat(file: file, prefix: prefix(of: patch), .init())
            }
            return detected
        }
        guard detected == named else {
            throw PatchErrors.formatMismatch(file: file, expected: named, found: detected, .init())
        }
        return named
    }

    private static func prefix(of patch: GoDReadable) -> [UInt8] {
        let count = min(patch.length, PatchFormat.magicLength)
        guard count > 0 else { return [] }
        return patch.read(atAddress: 0, length: count)?.rawBytes ?? []
    }
}
