//
//  IPSPatchCodec.swift
//
//  `PatchCodec` for IPS. The format carries no checksums and no source size,
//  so there is nothing to check in either direction — which `apply` reports
//  rather than leaving the caller to assume its usual guarantees held.
//

import Foundation

public struct IPSPatchCodec: PatchCodec {

    public static let magic: [UInt8] = IPSPatch.magic
    public static let formatName = "IPS"

    public init() {}

    public func createPatch(source: GoDReadable, target: GoDReadable) throws -> GoDReadable {
        let plan = try IPSPatch.plan(source: source, target: target)
        return IPSPatchView(target: target, plan: plan)
    }

    public func apply(
        patch: GoDReadable,
        to input: GoDReadable,
        direction: PatchDirection?,
        validateInput: Bool
    ) throws -> PatchApplication {
        // Applying an IPS patch backwards is not possible: a record says what
        // the new bytes are, never what they replaced.
        if let direction, direction == .reverse {
            throw PatchError.directionNotSupported(format: Self.formatName, direction: direction)
        }
        let ips = try IPSPatch.parse(patch)
        return PatchApplication(
            output: IPSPatchedView(input: input, patch: patch, ips: ips),
            direction: .forward,
            expectedOutputChecksum: nil,
            warnings: [
                "IPS carries no checksums or source size, so neither the file being patched nor the "
                + "result can be verified — nothing confirms this patch belongs to this file",
            ]
        )
    }

    public func validate(output: GoDReadable, of application: PatchApplication) throws {
        // Nothing to check: see above.
    }
}
