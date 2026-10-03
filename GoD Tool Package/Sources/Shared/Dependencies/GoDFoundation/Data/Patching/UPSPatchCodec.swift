//
//  UPSPatchCodec.swift
//
//  `PatchCodec` for UPS: creating a patch is one diff pass plus one checksum
//  pass, applying one is a parse, a checksum of the input, and a view.
//
//  Nothing here buffers a file. The two passes creating a patch needs are a
//  consequence of the format rather than of the implementation: the footer
//  stores the CRC-32 of every byte ahead of it, so the patch's own bytes have
//  to exist before its last word can be written.
//

import Foundation

public struct UPSPatchCodec: PatchCodec {

    public static let magic: [UInt8] = UPSPatch.magic
    public static let formatName = "UPS"

    public init() {}

    public func createPatch(source: GoDReadable, target: GoDReadable) throws -> GoDReadable {
        let plan = try UPSPatch.plan(source: source, target: target)
        // The footer's last word is the patch's own CRC-32, so the layout is
        // built once with a placeholder to checksum, then once for real. Both
        // are views: the placeholder costs a streamed pass, not a copy.
        let draft = UPSPatchView(source: source, target: target, plan: plan, patchChecksum: 0)
        let checksum = CRC32.compute(draft, bytes: 0 ..< (draft.length - 4))
        return UPSPatchView(source: source, target: target, plan: plan, patchChecksum: checksum)
    }

    public func apply(
        patch: GoDReadable,
        to input: GoDReadable,
        direction: PatchDirection?,
        validateInput: Bool
    ) throws -> PatchApplication {
        let ups = try UPSPatch.parse(patch)
        let inputSize = input.length
        let inputChecksum = CRC32.compute(input)
        var warnings = [String]()

        let chosen = try resolveDirection(
            requested: direction,
            ups: ups,
            inputSize: inputSize,
            inputChecksum: inputChecksum,
            validateInput: validateInput,
            warnings: &warnings
        )

        return PatchApplication(
            output: UPSPatchedView(input: input, patch: patch, ups: ups, direction: chosen),
            direction: chosen,
            expectedOutputChecksum: ups.outputChecksum(applying: chosen),
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

    /// Which side of the patch the input is.
    ///
    /// A named direction is checked and kept. Without one, the patch's own
    /// sizes and checksums answer it — exactly matching one side is the
    /// ordinary case. Falling back on size alone is what makes
    /// `validateInput: false` useful, and is also where it stops: when both
    /// sides are the same length and neither checksum matches, there is
    /// nothing left to decide it with, and guessing would quietly produce
    /// garbage.
    private func resolveDirection(
        requested: PatchDirection?,
        ups: UPSPatch,
        inputSize: Int,
        inputChecksum: UInt32,
        validateInput: Bool,
        warnings: inout [String]
    ) throws -> PatchDirection {
        let name = Self.formatName

        func checksumMismatch(_ direction: PatchDirection) -> PatchError {
            .inputChecksumMismatch(
                format: name,
                direction: direction,
                stored: ups.inputChecksum(applying: direction),
                computed: inputChecksum
            )
        }

        func note(_ direction: PatchDirection) {
            let side = direction == .forward ? "source" : "target"
            warnings.append(String(
                format: "the input does not match the %@ this patch was made from (patch %08X, input %08X) — patching it anyway",
                side, ups.inputChecksum(applying: direction), inputChecksum
            ))
        }

        if let requested {
            guard ups.inputSize(applying: requested) == inputSize else {
                throw PatchError.inputSizeMismatch(
                    format: name,
                    direction: requested,
                    expected: ups.inputSize(applying: requested),
                    found: inputSize
                )
            }
            if ups.inputChecksum(applying: requested) != inputChecksum {
                guard !validateInput else { throw checksumMismatch(requested) }
                note(requested)
            }
            return requested
        }

        for direction in [PatchDirection.forward, .reverse] {
            if ups.inputSize(applying: direction) == inputSize,
               ups.inputChecksum(applying: direction) == inputChecksum {
                return direction
            }
        }

        let fitsForward = ups.sourceSize == inputSize
        let fitsReverse = ups.targetSize == inputSize
        switch (fitsForward, fitsReverse) {
        case (true, false):
            guard !validateInput else { throw checksumMismatch(.forward) }
            note(.forward)
            return .forward
        case (false, true):
            guard !validateInput else { throw checksumMismatch(.reverse) }
            note(.reverse)
            return .reverse
        case (true, true):
            // Both sides are the same length and neither checksum matches, so
            // nothing in the patch can say which way round this input goes.
            guard !validateInput else { throw checksumMismatch(.forward) }
            throw PatchError.ambiguousDirection(format: name, size: inputSize)
        case (false, false):
            throw PatchError.inputMatchesNeitherSide(
                format: name,
                inputSize: inputSize,
                sourceSize: ups.sourceSize,
                targetSize: ups.targetSize
            )
        }
    }
}
