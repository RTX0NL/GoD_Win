//
//  BPSPatchCodec.swift
//
//  `PatchCodec` for BPS.
//
//  The reader handles all four actions, because other tools emit all four. The
//  writer emits the two that describe data in place — `SourceRead` and
//  `TargetRead`, byuu's "linear" creator — so a patch it writes is correct and
//  run-length-compact, but does not claim matches for data that moved. Finding
//  those is a delta search over the whole source, which is a separate piece of
//  work; what is here never produces a wrong patch, only a larger one.
//

import Foundation

public struct BPSPatchCodec: PatchCodec {

    public static let magic: [UInt8] = BPSPatch.magic
    public static let formatName = "BPS"

    public init() {}

    public func createPatch(source: GoDReadable, target: GoDReadable) throws -> GoDReadable {
        let plan = try BPSPatch.plan(source: source, target: target)
        let draft = BPSPatchView(target: target, plan: plan, patchChecksum: 0)
        let checksum = CRC32.compute(draft, bytes: 0 ..< (draft.length - 4))
        return BPSPatchView(target: target, plan: plan, patchChecksum: checksum)
    }

    public func apply(
        patch: GoDReadable,
        to input: GoDReadable,
        direction: PatchDirection?,
        validateInput: Bool
    ) throws -> PatchApplication {
        // A BPS patch says what the target's bytes are, never what they
        // replaced, so there is nothing to run backwards.
        if let direction, direction == .reverse {
            throw PatchError.directionNotSupported(format: Self.formatName, direction: direction)
        }
        let bps = try BPSPatch.parse(patch)

        var warnings = [String]()
        guard input.length == bps.sourceSize else {
            throw PatchError.inputSizeMismatch(
                format: Self.formatName, direction: .forward, expected: bps.sourceSize, found: input.length
            )
        }
        let checksum = CRC32.compute(input)
        if checksum != bps.sourceChecksum {
            guard !validateInput else {
                throw PatchError.inputChecksumMismatch(
                    format: Self.formatName, direction: .forward, stored: bps.sourceChecksum, computed: checksum
                )
            }
            warnings.append(String(
                format: "the input does not match the source this patch was made from (patch %08X, input %08X) "
                + "— patching it anyway",
                bps.sourceChecksum, checksum
            ))
        }

        return PatchApplication(
            output: BPSPatchedView(source: input, patch: patch, bps: bps),
            direction: .forward,
            expectedOutputChecksum: bps.targetChecksum,
            warnings: warnings
        )
    }

    public func validate(output: GoDReadable, of application: PatchApplication) throws {
        guard let expected = application.expectedOutputChecksum else { return }
        let computed = CRC32.compute(output)
        guard computed == expected else {
            throw PatchError.outputChecksumMismatch(
                format: Self.formatName, expected: expected, computed: computed
            )
        }
    }
}
