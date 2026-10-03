//
//  PatchOperationTests.swift
//  GODOpsTests
//
//  Exercises createPatch / applyPatch against an InMemoryFST: the round trip
//  through the operations, format detection, the in-place refusal, and what
//  happens to an output that fails its checksum.
//

import XCTest
import GoDFoundation
@testable import GODOps

final class PatchOperationTests: XCTestCase {

    // MARK: - Helpers

    private let source: [UInt8] = Array("PHENAC CITY, ORRE — population 0".utf8)
    private let target: [UInt8] = Array("PHENAC CITY, ORRE — population 7".utf8)

    private func write(_ bytes: [UInt8], at path: String, in fst: InMemoryFST) throws {
        try fst.writeFile(GoDData(byteStream: bytes, byteOrder: .big), at: File(path), overwrite: true)
    }

    private func bytes(at path: String, in fst: InMemoryFST) throws -> [UInt8] {
        try XCTUnwrap(fst.readFile(at: File(path))?.allData, "expected \(path)").rawBytes
    }

    private func create(
        _ config: CreatePatch.Config,
        in fst: InMemoryFST,
        logger: Logger = SilentLogger()
    ) throws {
        try CreatePatch.run(config: config, settings: .default, fileSystem: fst, logger: logger)
    }

    private func apply(
        _ config: ApplyPatch.Config,
        in fst: InMemoryFST,
        logger: Logger = SilentLogger()
    ) throws {
        try ApplyPatch.run(config: config, settings: .default, fileSystem: fst, logger: logger)
    }

    /// A tree holding the two files and the patch between them.
    private func populated() throws -> InMemoryFST {
        let fst = InMemoryFST()
        try write(source, at: "/p/source.bin", in: fst)
        try write(target, at: "/p/target.bin", in: fst)
        try create(
            .init(
                sourceFile: File("/p/source.bin"),
                targetFile: File("/p/target.bin"),
                patchFile: File("/p/patch.ups"),
                format: .ups
            ),
            in: fst
        )
        return fst
    }

    // MARK: - Round trip

    func testCreateThenApplyReproducesTheTarget() throws {
        let fst = try populated()
        let patch = try bytes(at: "/p/patch.ups", in: fst)
        XCTAssertEqual(Array(patch[0 ..< 4]), Array("UPS1".utf8))

        try apply(
            .init(
                inputFile: File("/p/source.bin"),
                patchFile: File("/p/patch.ups"),
                outputFile: File("/p/out.bin")
            ),
            in: fst
        )
        XCTAssertEqual(try bytes(at: "/p/out.bin", in: fst), target)
    }

    func testApplyingToTheTargetUndoesThePatch() throws {
        let fst = try populated()
        try apply(
            .init(
                inputFile: File("/p/target.bin"),
                patchFile: File("/p/patch.ups"),
                outputFile: File("/p/out.bin")
            ),
            in: fst
        )
        XCTAssertEqual(try bytes(at: "/p/out.bin", in: fst), source)
    }

    func testANamedDirectionIsHonored() throws {
        let fst = try populated()
        try apply(
            .init(
                inputFile: File("/p/target.bin"),
                patchFile: File("/p/patch.ups"),
                outputFile: File("/p/out.bin"),
                direction: .reverse
            ),
            in: fst
        )
        XCTAssertEqual(try bytes(at: "/p/out.bin", in: fst), source)
    }

    func testFilesOfDifferentLengthsRoundTrip() throws {
        let fst = InMemoryFST()
        try write(Array("short".utf8), at: "/p/a.bin", in: fst)
        try write(Array("a good deal longer than the other one".utf8), at: "/p/b.bin", in: fst)
        try create(
            .init(
                sourceFile: File("/p/a.bin"),
                targetFile: File("/p/b.bin"),
                patchFile: File("/p/patch.ups"),
                format: .ups
            ),
            in: fst
        )
        try apply(
            .init(inputFile: File("/p/a.bin"), patchFile: File("/p/patch.ups"), outputFile: File("/p/out.bin")),
            in: fst
        )
        XCTAssertEqual(try bytes(at: "/p/out.bin", in: fst), try bytes(at: "/p/b.bin", in: fst))

        try apply(
            .init(inputFile: File("/p/b.bin"), patchFile: File("/p/patch.ups"), outputFile: File("/p/back.bin")),
            in: fst
        )
        XCTAssertEqual(try bytes(at: "/p/back.bin", in: fst), try bytes(at: "/p/a.bin", in: fst))
    }

    // MARK: - Format

    func testADeclaredFormatMustAgreeWithTheMagic() throws {
        let fst = try populated()
        try write(Array("BPS1".utf8) + [0, 0, 0, 0], at: "/p/other.bps", in: fst)
        XCTAssertThrowsError(try apply(
            .init(
                inputFile: File("/p/source.bin"),
                patchFile: File("/p/other.bps"),
                outputFile: File("/p/out.bin"),
                format: .ups
            ),
            in: fst
        )) { error in
            guard case PatchErrors.formatMismatch = error else {
                return XCTFail("expected a format mismatch, got \(error)")
            }
        }
    }

    func testAFileThatIsNoPatchAtAllIsRefused() throws {
        let fst = try populated()
        try write([0, 1, 2, 3, 4, 5, 6, 7], at: "/p/noise.bin", in: fst)
        XCTAssertThrowsError(try apply(
            .init(
                inputFile: File("/p/source.bin"),
                patchFile: File("/p/noise.bin"),
                outputFile: File("/p/out.bin")
            ),
            in: fst
        )) { error in
            guard case PatchErrors.unrecognizedPatchFormat = error else {
                return XCTFail("expected an unrecognized format, got \(error)")
            }
            XCTAssertTrue("\(error)".contains("UPS"), "the error lists what is read")
        }
    }

    // MARK: - Refusals

    func testPatchingInPlaceIsRefused() throws {
        let fst = try populated()
        XCTAssertThrowsError(try apply(
            .init(
                inputFile: File("/p/source.bin"),
                patchFile: File("/p/patch.ups"),
                outputFile: File("/p/source.bin")
            ),
            in: fst
        )) { error in
            guard case PatchErrors.outputIsInput = error else {
                return XCTFail("expected an in-place refusal, got \(error)")
            }
        }
        XCTAssertEqual(try bytes(at: "/p/source.bin", in: fst), source, "the input must be untouched")
    }

    func testMissingFilesAreNamed() throws {
        let fst = try populated()
        XCTAssertThrowsError(try apply(
            .init(
                inputFile: File("/p/source.bin"),
                patchFile: File("/p/absent.ups"),
                outputFile: File("/p/out.bin")
            ),
            in: fst
        )) { error in
            guard case PatchErrors.patchFileNotFound = error else {
                return XCTFail("expected a missing patch, got \(error)")
            }
        }
        XCTAssertThrowsError(try create(
            .init(
                sourceFile: File("/p/absent.bin"),
                targetFile: File("/p/target.bin"),
                patchFile: File("/p/patch2.ups"),
                format: .ups
            ),
            in: fst
        )) { error in
            guard case PatchErrors.inputFileNotFound = error else {
                return XCTFail("expected a missing input, got \(error)")
            }
        }
    }

    func testPatchingTheWrongFileIsRefused() throws {
        let fst = try populated()
        try write(Array("PHENAC CITY, ORRE — population 9".utf8), at: "/p/other.bin", in: fst)
        XCTAssertThrowsError(try apply(
            .init(
                inputFile: File("/p/other.bin"),
                patchFile: File("/p/patch.ups"),
                outputFile: File("/p/out.bin")
            ),
            in: fst
        )) { error in
            guard case PatchError.inputChecksumMismatch = error else {
                return XCTFail("expected an input checksum mismatch, got \(error)")
            }
        }
        XCTAssertNil(fst.readFile(at: File("/p/out.bin")), "nothing should have been written")
    }

    func testIgnoringChecksumsWarnsTwiceAndKeepsTheFile() throws {
        let fst = try populated()
        try write(Array("PHENAC CITY, ORRE — population 9".utf8), at: "/p/other.bin", in: fst)
        let logger = RecordingLogger()
        try apply(
            .init(
                inputFile: File("/p/other.bin"),
                patchFile: File("/p/patch.ups"),
                outputFile: File("/p/out.bin"),
                direction: .forward,
                ignoreChecksums: true
            ),
            in: fst,
            logger: logger
        )
        // One warning for the input it was not made from, one for the result
        // that therefore isn't what the patch names.
        XCTAssertEqual(logger.warnings.count, 2, "\(logger.warnings)")
        let written = try bytes(at: "/p/out.bin", in: fst)
        XCTAssertEqual(written.count, target.count)
        XCTAssertNotEqual(written, target)
    }

    func testAnOutputThatFailsItsChecksumIsDeleted() throws {
        let fst = try populated()
        // Corrupt a hunk's payload but fix the patch's own checksum, so the
        // patch passes every check it makes about itself and only the result
        // can give it away.
        var patch = try bytes(at: "/p/patch.ups", in: fst)
        // Last byte before the footer is the hunk's terminator; the one
        // before it is its single XOR byte.
        XCTAssertEqual(patch[patch.count - 13], 0, "expected the hunk terminator here")
        patch[patch.count - 14] ^= 0x01
        let body = Array(patch[0 ..< (patch.count - 4)])
        let crc = CRC32.compute(body)
        patch[patch.count - 4] = UInt8(crc & 0xFF)
        patch[patch.count - 3] = UInt8((crc >> 8) & 0xFF)
        patch[patch.count - 2] = UInt8((crc >> 16) & 0xFF)
        patch[patch.count - 1] = UInt8((crc >> 24) & 0xFF)
        try write(patch, at: "/p/bad.ups", in: fst)

        XCTAssertThrowsError(try apply(
            .init(
                inputFile: File("/p/source.bin"),
                patchFile: File("/p/bad.ups"),
                outputFile: File("/p/out.bin")
            ),
            in: fst
        )) { error in
            guard case PatchError.outputChecksumMismatch = error else {
                return XCTFail("expected an output checksum mismatch, got \(error)")
            }
        }
        XCTAssertNil(fst.readFile(at: File("/p/out.bin")), "a wrong result must not be left behind")
    }

    // MARK: - Every format through the generic operations

    /// The operations name a format and nothing else, so each one has to work
    /// through them — the codecs differ in what they verify, what they can run
    /// backwards, and whether their output is a view or a buffer.
    func testEveryFormatRoundTripsThroughTheOperations() throws {
        for format in PatchFormat.allCases {
            let fst = InMemoryFST()
            try write(source, at: "/p/source.bin", in: fst)
            try write(target, at: "/p/target.bin", in: fst)
            try create(
                .init(
                    sourceFile: File("/p/source.bin"),
                    targetFile: File("/p/target.bin"),
                    patchFile: File("/p/patch.bin"),
                    format: format
                ),
                in: fst
            )
            let patch = try bytes(at: "/p/patch.bin", in: fst)
            XCTAssertTrue(patch.starts(with: format.magic), "\(format.rawValue): magic")
            XCTAssertEqual(PatchFormat.detect(GoDData(byteStream: patch, byteOrder: .big)), format)

            // No `format` in the config: the magic has to be enough.
            try apply(
                .init(
                    inputFile: File("/p/source.bin"),
                    patchFile: File("/p/patch.bin"),
                    outputFile: File("/p/out.bin")
                ),
                in: fst
            )
            XCTAssertEqual(try bytes(at: "/p/out.bin", in: fst), target, "\(format.rawValue): patched output")
        }
    }

    func testOnlyUPSCanBeAppliedBackwards() throws {
        for format in PatchFormat.allCases {
            let fst = InMemoryFST()
            try write(source, at: "/p/source.bin", in: fst)
            try write(target, at: "/p/target.bin", in: fst)
            try create(
                .init(
                    sourceFile: File("/p/source.bin"),
                    targetFile: File("/p/target.bin"),
                    patchFile: File("/p/patch.bin"),
                    format: format
                ),
                in: fst
            )
            let reverse = ApplyPatch.Config(
                inputFile: File("/p/target.bin"),
                patchFile: File("/p/patch.bin"),
                outputFile: File("/p/back.bin"),
                direction: .reverse
            )
            if format == .ups {
                try apply(reverse, in: fst)
                XCTAssertEqual(try bytes(at: "/p/back.bin", in: fst), source)
            } else {
                XCTAssertThrowsError(try apply(reverse, in: fst), "\(format.rawValue) is not symmetric") { error in
                    guard case PatchError.directionNotSupported = error else {
                        return XCTFail("\(format.rawValue): expected an unsupported direction, got \(error)")
                    }
                }
            }
        }
    }

    /// IPS and xdelta carry no checksum of either whole file, and say so rather
    /// than letting a caller assume the usual gate ran.
    func testFormatsWithoutChecksumsWarn() throws {
        for format in [PatchFormat.ips, .xdelta] {
            let fst = InMemoryFST()
            try write(source, at: "/p/source.bin", in: fst)
            try write(target, at: "/p/target.bin", in: fst)
            try create(
                .init(
                    sourceFile: File("/p/source.bin"),
                    targetFile: File("/p/target.bin"),
                    patchFile: File("/p/patch.bin"),
                    format: format
                ),
                in: fst
            )
            let logger = RecordingLogger()
            try apply(
                .init(
                    inputFile: File("/p/source.bin"),
                    patchFile: File("/p/patch.bin"),
                    outputFile: File("/p/out.bin")
                ),
                in: fst,
                logger: logger
            )
            XCTAssertEqual(logger.warnings.count, 1, "\(format.rawValue): \(logger.warnings)")
            XCTAssertEqual(try bytes(at: "/p/out.bin", in: fst), target)
        }
    }

    func testOverwriteIsHonored() throws {
        let fst = try populated()
        try write([0xFF], at: "/p/out.bin", in: fst)
        XCTAssertThrowsError(try apply(
            .init(
                inputFile: File("/p/source.bin"),
                patchFile: File("/p/patch.ups"),
                outputFile: File("/p/out.bin"),
                overwrite: false
            ),
            in: fst
        ))
        XCTAssertEqual(try bytes(at: "/p/out.bin", in: fst), [0xFF])
    }
}
