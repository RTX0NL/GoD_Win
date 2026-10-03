//
//  PatchFormat.swift
//
//  Which binary patch format a file holds, and the codec for it.
//
//  A closed enum rather than a registry, for the reason `CompressionFormat`
//  is one: the set of patch formats is fixed knowledge about other people's
//  tooling, not something an engine extends. A case promises `makeCodec()`,
//  so a format only appears here once it can be both written and read.
//

import Foundation

public enum PatchFormat: String, CaseIterable, Codable {

    /// byuu's UPS. A variable-width-integer header, XOR hunks, and a footer
    /// of three CRC-32s.
    case ups

    /// The International Patching System. Offsets are three bytes, so it
    /// cannot address past 16 MiB, and it carries no checksums at all.
    case ips

    /// byuu's BPS, the format that replaced UPS: an instruction stream rather
    /// than an XOR, so it can describe data that moved.
    case bps

    /// VCDIFF (RFC 3284), what an `.xdelta` file holds. The only one of these
    /// whose instructions can copy from anywhere in the source, and the only
    /// one with no checksum of either whole file.
    case xdelta

    /// The bytes at offset 0 that identify this format.
    public var magic: [UInt8] {
        switch self {
        case .ups: return UPSPatchCodec.magic
        case .ips: return IPSPatchCodec.magic
        case .bps: return BPSPatchCodec.magic
        case .xdelta: return VCDIFFPatchCodec.magic
        }
    }

    /// The format's conventional spelling, for logs and errors.
    public var name: String {
        switch self {
        case .ups: return UPSPatchCodec.formatName
        case .ips: return IPSPatchCodec.formatName
        case .bps: return BPSPatchCodec.formatName
        case .xdelta: return VCDIFFPatchCodec.formatName
        }
    }

    /// The extension a patch of this format conventionally takes.
    public var defaultExtension: String {
        switch self {
        case .ups: return "ups"
        case .ips: return "ips"
        case .bps: return "bps"
        case .xdelta: return "xdelta"
        }
    }

    public func makeCodec() -> PatchCodec {
        switch self {
        case .ups: return UPSPatchCodec()
        case .ips: return IPSPatchCodec()
        case .bps: return BPSPatchCodec()
        case .xdelta: return VCDIFFPatchCodec()
        }
    }

    /// The number of bytes of a patch `detect` needs to see.
    public static var magicLength: Int {
        allCases.map(\.magic.count).max() ?? 0
    }

    /// The format whose magic `data` starts with, or nil.
    public static func detect(_ data: GoDReadable) -> PatchFormat? {
        let prefix = self.prefix(of: data)
        return allCases.first { prefix.starts(with: $0.magic) }
    }

    private static func prefix(of data: GoDReadable) -> [UInt8] {
        let count = min(data.length, magicLength)
        guard count > 0 else { return [] }
        return data.read(atAddress: 0, length: count)?.rawBytes ?? []
    }
}
