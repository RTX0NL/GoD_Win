//
//  DiscImageFormat.swift
//
//  Sniff a disc image file and tell callers what format it's in.
//  Used by ProjectSetup and the various dump operations to chain the
//  right decoder automatically — the user can point `GODDESS` at a
//  `.iso`, `.ciso`, `.nkit.iso`, `.wia`, or `.rvz` and it'll do the
//  right thing.
//
//  Detection order (cheapest / most specific first):
//    1. ASCII magic at offset 0x00: "CISO" (Wii/GC CISO), "WIA\x01"
//       (WIA/RVZ)
//    2. ASCII magic at offset 0x200: "NKIT v01" (both GC and Wii NKit
//       live here, differ by the disc-header magic at 0x1C/0x18)
//    3. Disc magic at offset 0x18/0x1C: `0xC2339F3D` (GameCube) or
//       `0x5D1C9EA3` (Wii) for a raw, uncompressed ISO
//
//  Everything else falls through to `.unknown`.
//

import Foundation
import GoDFoundation

public enum DiscImageFormat: Equatable {
    case gamecubeISO
    case wiiISO
    case ciso        // Wii/GC CISO (not PSP CSO — distinguished by block-size)
    case wiaOrRVZ    // handled by the same reader; `compression` field inside picks WIA vs RVZ
    case nkitGC
    case nkitWii
    case unknown

    /// Inspect the first 0x400 bytes and return the detected format.
    /// Returns `.unknown` if no signature matches.
    public static func detect(in binary: GoDData) -> DiscImageFormat {
        binary.setByteOrder(.big)
        guard binary.length >= 0x400 else { return .unknown }

        // 1. Compressed-format magic at file offset 0.
        if let head = binary.read(atAddress: 0, length: 4)?.rawBytes {
            if head == [0x43, 0x49, 0x53, 0x4F] {  // "CISO"
                // Disambiguate from PSP CSO via the block-size at 0x04.
                binary.setByteOrder(.little)
                let blockSize: UInt32 = binary.readSafely(atAddress: 4)
                binary.setByteOrder(.big)
                if blockSize >= 0x8000 {
                    return .ciso
                }
                return .unknown  // PSP CSO or malformed
            }
            // WIA and RVZ share a reader but not a magic: Dolphin writes
            // "RVZ\x01" for the newer variant. Missing the RVZ spelling made
            // real `.rvz` files fall through as `.unknown`, i.e. get treated
            // as raw disc images, so setup read compressed bytes as a game ID
            // instead of reporting that the format isn't decodable yet.
            if head == [0x57, 0x49, 0x41, 0x01]     // "WIA\x01"
                || head == [0x52, 0x56, 0x5A, 0x01] // "RVZ\x01"
            {
                return .wiaOrRVZ
            }
        }

        // 2. NKit magic at 0x200.
        if let nkit = binary.read(atAddress: 0x200, length: 8)?.rawBytes,
           nkit == NKitHeader.magic {
            return isWiiDisc(binary) ? .nkitWii : .nkitGC
        }

        // 3. Raw disc image magic.
        let gcMagic: UInt32 = binary.readSafely(atAddress: 0x1C)
        if gcMagic == 0xC233_9F3D { return .gamecubeISO }
        let wiiMagic: UInt32 = binary.readSafely(atAddress: 0x18)
        if wiiMagic == 0x5D1C_9EA3 { return .wiiISO }

        return .unknown
    }

    /// Whether the disc header (bytes 0-0x1FF) identifies this as a
    /// Wii disc. NKit doesn't rewrite those bytes (apart from the
    /// encryption/hash flags at 0x60/0x61), so we can trust the
    /// original disc magic.
    private static func isWiiDisc(_ binary: GoDData) -> Bool {
        let wiiMagic: UInt32 = binary.readSafely(atAddress: 0x18)
        return wiiMagic == 0x5D1C_9EA3
    }

    /// Short human label. Handy for logging and sections.txt headers.
    public var description: String {
        switch self {
        case .gamecubeISO: return "GameCube ISO"
        case .wiiISO:      return "Wii ISO"
        case .ciso:        return "Compact ISO (CISO)"
        case .wiaOrRVZ:    return "WIA/RVZ"
        case .nkitGC:      return "NKit GameCube"
        case .nkitWii:     return "NKit Wii"
        case .unknown:     return "Unknown"
        }
    }

    /// Whether the format needs decoding before normal `gamecubeDump`
    /// / `wiiDump` operations can consume it. Raw ISOs are passed
    /// through untouched; everything else needs a predecoder.
    public var requiresDecoding: Bool {
        switch self {
        case .gamecubeISO, .wiiISO, .unknown: return false
        case .ciso, .wiaOrRVZ, .nkitGC, .nkitWii: return true
        }
    }
}
