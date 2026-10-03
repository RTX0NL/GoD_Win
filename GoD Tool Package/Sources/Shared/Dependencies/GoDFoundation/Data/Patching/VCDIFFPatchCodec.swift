//
//  VCDIFFPatchCodec.swift
//
//  `PatchCodec` for VCDIFF — what `.xdelta` files hold.
//
//  The format carries no checksum of either whole file: xdelta3 stamps each
//  *window* with an Adler-32 of the bytes it decodes to, and that is all. So
//  there is nothing to identify the file a patch belongs to before applying it,
//  and nothing to compare the finished result against — which `apply` reports,
//  the same way the IPS codec does. What it does have is per-window checking,
//  and that is verified as each window decodes: a patch applied to the wrong
//  file fails at the first window that copies from it.
//

import Foundation

public struct VCDIFFPatchCodec: PatchCodec {

    public static let magic: [UInt8] = VCDIFFPatch.magic
    public static let formatName = "xdelta"

    public var encoder: VCDIFFEncoder

    public init(encoder: VCDIFFEncoder = VCDIFFEncoder()) {
        self.encoder = encoder
    }

    public func createPatch(source: GoDReadable, target: GoDReadable) throws -> GoDReadable {
        // The only writer here that produces its bytes eagerly. A window's
        // instructions cannot be laid out until its matches are found, and a
        // window's length cannot be known until they are, so a lazy view over
        // the patch would have to encode everything twice.
        try encoder.encode(source: source, target: target)
    }

    public func apply(
        patch: GoDReadable,
        to input: GoDReadable,
        direction: PatchDirection?,
        validateInput: Bool
    ) throws -> PatchApplication {
        if let direction, direction == .reverse {
            throw PatchError.directionNotSupported(format: Self.formatName, direction: direction)
        }
        let vcdiff = try VCDIFFPatch.parse(patch)
        let checksummed = vcdiff.windows.allSatisfy { $0.adler32 != nil }
        var warnings = [String]()
        if !checksummed {
            warnings.append(
                "this xdelta patch carries no checksum of the file it was made from, and none of the result — "
                + "nothing confirms it belongs to this file"
            )
        }
        return PatchApplication(
            output: VCDIFFPatchedView(patch: patch, source: input, vcdiff: vcdiff),
            direction: .forward,
            expectedOutputChecksum: nil,
            warnings: warnings
        )
    }

    public func validate(output: GoDReadable, of application: PatchApplication) throws {
        // Nothing covers the whole file. Each window's own checksum, where the
        // writer stamped one, is verified as it decodes.
    }
}
