//
//  CompressionOperationTests.swift
//  GODOpsTests
//
//  Exercises the compress / decompress operations against an InMemoryFST:
//  round trips through every format, magic detection, the byte range,
//  option validation, derived names, and the bulk variants.
//

import XCTest
import GoDFoundation
import FixtureCatalog
import TestSupport
@testable import GODOps

final class CompressionOperationTests: XCTestCase {

    // MARK: - Helpers

    /// Mixed content: repeats for the matchers to find, a run, and noise.
    private let sample: [UInt8] = {
        var bytes = [UInt8]()
        for _ in 0 ..< 6 { bytes += Array("PHENAC CITY ".utf8) }
        bytes += [UInt8](repeating: 0, count: 200)
        var state: UInt32 = 0x0BAD_F00D
        for _ in 0 ..< 150 {
            state = 1_664_525 &* state &+ 1_013_904_223
            bytes.append(UInt8(state >> 24))
        }
        bytes += Array("PHENAC CITY ".utf8)
        return bytes
    }()

    private func data(_ bytes: [UInt8]) -> GoDData {
        GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func write(_ bytes: [UInt8], at path: String, in fst: InMemoryFST) throws {
        try fst.writeFile(data(bytes), at: File(path), overwrite: true)
    }

    private func bytes(at path: String, in fst: InMemoryFST, file: StaticString = #filePath, line: UInt = #line) throws -> [UInt8] {
        try XCTUnwrap(fst.readFile(at: File(path))?.allData, "expected \(path)", file: file, line: line).rawBytes
    }

    private func compress(_ config: Compress.SingleConfig, in fst: InMemoryFST, logger: Logger = SilentLogger()) throws {
        try Compress.run(config: config, settings: .default, fileSystem: fst, logger: logger)
    }

    private func compress(_ config: Compress.BatchConfig, in fst: InMemoryFST, logger: Logger = SilentLogger()) throws {
        try Compress.run(config: config, settings: .default, fileSystem: fst, logger: logger)
    }

    private func decompress(_ config: Decompress.SingleConfig, in fst: InMemoryFST, logger: Logger = SilentLogger()) throws {
        try Decompress.run(config: config, settings: .default, fileSystem: fst, logger: logger)
    }

    private func decompress(_ config: Decompress.BatchConfig, in fst: InMemoryFST, logger: Logger = SilentLogger()) throws {
        try Decompress.run(config: config, settings: .default, fileSystem: fst, logger: logger)
    }

    private func infoMessages(_ logger: RecordingLogger) -> [String] {
        logger.entries.compactMap { if case .info(let message) = $0 { return message } else { return nil } }
    }

    // MARK: - Round trips

    func testCompressThenDecompressRoundTripsEveryFormat() throws {
        for format in CompressionOps.Format.allCases {
            let fst = InMemoryFST()
            try write(sample, at: "/project/in/model.dat", in: fst)
            try compress(.init(inputFile: "/project/in/model.dat", format: format,
                               outputFile: "/project/out/model.packed", overwrite: true), in: fst)
            XCTAssertLessThan(try bytes(at: "/project/out/model.packed", in: fst).count, sample.count, format.rawValue)

            // A stream with a magic is detected; the raw one has to be named.
            let named: CompressionOps.Format? = format.detectable == nil ? format : nil
            try decompress(.init(inputFile: "/project/out/model.packed", format: named,
                                 outputFile: "/project/out/model.dat", overwrite: true), in: fst)
            assertBytesEqual(try bytes(at: "/project/out/model.dat", in: fst), sample, format.rawValue)
        }
    }

    func testDecompressAcceptsAnExplicitMatchingFormat() throws {
        for format in CompressionOps.Format.allCases where format.detectable != nil {
            let fst = InMemoryFST()
            try write(sample, at: "/project/in/model.dat", in: fst)
            try compress(.init(inputFile: "/project/in/model.dat", format: format,
                               outputFile: "/project/out/packed", overwrite: true), in: fst)
            try decompress(.init(inputFile: "/project/out/packed", format: format,
                                 outputFile: "/project/out/model.dat", overwrite: true), in: fst)
            assertBytesEqual(try bytes(at: "/project/out/model.dat", in: fst), sample, format.rawValue)
        }
    }

    /// The operations add nothing to the codecs: their output on the
    /// fixture inputs is exactly what the codecs produce, and the golden
    /// tests pin those to the frozen streams.
    func testOperationsAreThinWrappersOverTheCodecs() throws {
        let nintendo = NintendoCompressionFixtures.sampleInput()
        let gs = LZSSFixtures.sampleInput()
        let fst = InMemoryFST()
        try write(nintendo, at: "/project/in/nintendo.bin", in: fst)
        try write(gs, at: "/project/in/gs.bin", in: fst)

        let expectations: [(CompressionOps.Format, String, [UInt8])] = [
            (.yaz0, "/project/in/nintendo.bin", Yaz0Compressor().compress(data(nintendo)).rawBytes),
            (.yay0, "/project/in/nintendo.bin", Yay0Compressor().compress(data(nintendo)).rawBytes),
            (.lzss, "/project/in/gs.bin", LZSSHeaderedCompressor().compress(data(gs)).rawBytes),
            (.lzssRaw, "/project/in/gs.bin", LZSSCompressor().compress(data(gs)).rawBytes),
        ]
        for (format, input, expected) in expectations {
            let output = "/project/out/\(format.rawValue)"
            try compress(.init(inputFile: File(input), format: format, outputFile: File(output), overwrite: true), in: fst)
            assertBytesEqual(try bytes(at: output, in: fst), expected, format.rawValue)
        }
    }

    // MARK: - Format resolution

    func testDecompressWithoutFormatRejectsUnrecognizedData() throws {
        let fst = InMemoryFST()
        try write(sample, at: "/project/in/plain.bin", in: fst)
        XCTAssertThrowsError(try decompress(.init(inputFile: "/project/in/plain.bin"), in: fst)) { error in
            guard case CompressionErrors.unrecognizedFormat(let file, let prefix, _) = error else {
                return XCTFail("expected unrecognizedFormat, got \(error)")
            }
            XCTAssertEqual(file, File("/project/in/plain.bin"))
            XCTAssertEqual(prefix, Array(sample[0 ..< 4]))
        }
    }

    func testDecompressExplicitFormatMismatchThrows() throws {
        let fst = InMemoryFST()
        try write(Yay0Compressor().compress(data(sample)).rawBytes, at: "/project/in/stream.szp", in: fst)
        XCTAssertThrowsError(try decompress(.init(inputFile: "/project/in/stream.szp", format: .yaz0), in: fst)) { error in
            guard case CompressionErrors.formatMismatch(_, let expected, let found, _) = error else {
                return XCTFail("expected formatMismatch, got \(error)")
            }
            XCTAssertEqual(expected, .yaz0)
            XCTAssertEqual(found, .yay0)
        }
    }

    func testRawLZSSRequiresAnExplicitFormat() throws {
        let fst = InMemoryFST()
        try write(LZSSCompressor().compress(data(sample)).rawBytes, at: "/project/in/stream.lzss", in: fst)
        XCTAssertThrowsError(try decompress(.init(inputFile: "/project/in/stream.lzss"), in: fst)) { error in
            guard case CompressionErrors.unrecognizedFormat = error else {
                return XCTFail("expected unrecognizedFormat, got \(error)")
            }
        }
        try decompress(.init(inputFile: "/project/in/stream.lzss", format: .lzssRaw,
                             outputFile: "/project/out/stream.bin", overwrite: true), in: fst)
        assertBytesEqual(try bytes(at: "/project/out/stream.bin", in: fst), sample)
    }

    func testMissingInputThrows() throws {
        let fst = InMemoryFST()
        XCTAssertThrowsError(try compress(.init(inputFile: "/project/in/missing.bin", format: .yaz0), in: fst)) { error in
            guard case CompressionErrors.inputFileNotFound = error else {
                return XCTFail("expected inputFileNotFound, got \(error)")
            }
        }
        XCTAssertThrowsError(try decompress(.init(inputFile: "/project/in/missing.bin"), in: fst)) { error in
            guard case CompressionErrors.inputFileNotFound = error else {
                return XCTFail("expected inputFileNotFound, got \(error)")
            }
        }
    }

    // MARK: - Range

    func testDecompressRangeExtractsAnEmbeddedStream() throws {
        let junk = [UInt8](repeating: 0xEE, count: 37)
        for format in [CompressionOps.Format.yaz0, .yay0, .lzss] {
            let fst = InMemoryFST()
            let stream = try CompressionOps.makeCompressor(format: format, options: nil).compress(data(sample)).rawBytes
            try write(junk + stream + junk, at: "/project/in/blob.bin", in: fst)

            // With an explicit length, and letting it run to the end of the
            // file — every self-describing format stops where its header says.
            try decompress(.init(inputFile: "/project/in/blob.bin", range: .init(offset: junk.count, length: stream.count),
                                 outputFile: "/project/out/sized.bin", overwrite: true), in: fst)
            assertBytesEqual(try bytes(at: "/project/out/sized.bin", in: fst), sample, "\(format.rawValue) sized")

            try decompress(.init(inputFile: "/project/in/blob.bin", range: .init(offset: junk.count),
                                 outputFile: "/project/out/open.bin", overwrite: true), in: fst)
            assertBytesEqual(try bytes(at: "/project/out/open.bin", in: fst), sample, "\(format.rawValue) to end")
        }
    }

    func testDecompressRangeOutOfBoundsThrows() throws {
        let fst = InMemoryFST()
        let stream = Yaz0Compressor().compress(data(sample)).rawBytes
        try write(stream, at: "/project/in/stream.szs", in: fst)

        let bad: [CompressionOps.ByteRange] = [
            .init(offset: stream.count + 1),
            .init(offset: 0, length: stream.count + 1),
            .init(offset: 16, length: stream.count),
            .init(offset: -1),
            .init(offset: 0, length: -1),
        ]
        for range in bad {
            XCTAssertThrowsError(try decompress(.init(inputFile: "/project/in/stream.szs", range: range), in: fst), "\(range)") { error in
                guard case CompressionErrors.rangeOutOfBounds(_, let offset, let length, let fileSize, _) = error else {
                    return XCTFail("expected rangeOutOfBounds, got \(error)")
                }
                XCTAssertEqual(offset, range.offset)
                XCTAssertEqual(length, range.length)
                XCTAssertEqual(fileSize, stream.count)
            }
        }
    }

    // MARK: - Options

    private func assertNotApplicable(
        _ option: String, format: CompressionOps.Format, _ body: () throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try body(), "\(option) on \(format.rawValue)", file: file, line: line) { error in
            guard case CompressionErrors.optionNotApplicable(let found, let foundFormat, _, _, _) = error else {
                return XCTFail("expected optionNotApplicable, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(found, option, file: file, line: line)
            XCTAssertEqual(foundFormat, format, file: file, line: line)
        }
    }

    func testOptionNotApplicableThrows() throws {
        let fst = InMemoryFST()
        try write(sample, at: "/project/in/model.dat", in: fst)
        try write(Yaz0Compressor().compress(data(sample)).rawBytes, at: "/project/in/model.dat.szs", in: fst)

        assertNotApplicable("windowBits", format: .yaz0) {
            try compress(.init(inputFile: "/project/in/model.dat", format: .yaz0, options: .init(windowBits: 12)), in: fst)
        }
        assertNotApplicable("alignment", format: .yay0) {
            try compress(.init(inputFile: "/project/in/model.dat", format: .yay0, options: .init(alignment: 32)), in: fst)
        }
        assertNotApplicable("deferredMatching", format: .lzss) {
            try compress(.init(inputFile: "/project/in/model.dat", format: .lzss, options: .init(deferredMatching: false)), in: fst)
        }
        assertNotApplicable("maxChainLength", format: .lzssRaw) {
            try compress(.init(inputFile: "/project/in/model.dat", format: .lzssRaw, options: .init(maxChainLength: 8)), in: fst)
        }
        // Encoder tuning means nothing on the way back in.
        assertNotApplicable("alignment", format: .yaz0) {
            try decompress(.init(inputFile: "/project/in/model.dat.szs", format: .yaz0, options: .init(alignment: 0)), in: fst)
        }
        assertNotApplicable("deferredMatching", format: .yaz0) {
            try decompress(.init(inputFile: "/project/in/model.dat.szs", options: .init(deferredMatching: true)), in: fst)
        }
        // An auto-detected decompress validates against what the file is.
        assertNotApplicable("windowBits", format: .yaz0) {
            try decompress(.init(inputFile: "/project/in/model.dat.szs", options: .init(windowBits: 12)), in: fst)
        }
    }

    func testOptionOutOfRangeThrows() throws {
        let fst = InMemoryFST()
        try write(sample, at: "/project/in/model.dat", in: fst)

        let cases: [(CompressionOps.Format, CompressionOps.Options, String)] = [
            (.yaz0, .init(maxChainLength: 0), "maxChainLength"),
            (.lzss, .init(windowBits: 0), "windowBits"),
            (.lzss, .init(windowBits: 16), "windowBits"),
            (.lzssRaw, .init(lengthBits: 9), "lengthBits"),
            (.lzssRaw, .init(lengthBits: 0), "lengthBits"),
            (.lzss, .init(threshold: -1), "threshold"),
            (.lzss, .init(windowBits: 13, lengthBits: 4), "windowBits"),          // 17 bits don't fit two bytes
            (.lzss, .init(windowBits: 4, lengthBits: 4, threshold: 2), "windowBits"), // 16-byte window, 18-byte lookahead
        ]
        for (format, options, option) in cases {
            XCTAssertThrowsError(
                try compress(.init(inputFile: "/project/in/model.dat", format: format, options: options), in: fst),
                "\(option) on \(format.rawValue)"
            ) { error in
                guard case CompressionErrors.optionOutOfRange(let found, _, let foundFormat, _, _) = error else {
                    return XCTFail("expected optionOutOfRange, got \(error)")
                }
                XCTAssertEqual(found, option)
                XCTAssertEqual(foundFormat, format)
            }
        }
    }

    func testYaz0AlignmentIsWrittenToTheHeader() throws {
        let fst = InMemoryFST()
        try write(sample, at: "/project/in/model.dat", in: fst)

        try compress(.init(inputFile: "/project/in/model.dat", format: .yaz0,
                           outputFile: "/project/out/default.szs", overwrite: true), in: fst)
        XCTAssertEqual(try Yaz0Compressor.header(of: data(try bytes(at: "/project/out/default.szs", in: fst))).alignment, 0)

        try compress(.init(inputFile: "/project/in/model.dat", format: .yaz0,
                           outputFile: "/project/out/aligned.szs", overwrite: true, options: .init(alignment: 32)), in: fst)
        let header = try Yaz0Compressor.header(of: data(try bytes(at: "/project/out/aligned.szs", in: fst)))
        XCTAssertEqual(header.alignment, 32)
        XCTAssertEqual(header.uncompressedSize, sample.count)
    }

    func testLZ77TuningStillDecodes() throws {
        for format in [CompressionOps.Format.yaz0, .yay0] {
            let fst = InMemoryFST()
            try write(sample, at: "/project/in/model.dat", in: fst)
            try compress(.init(inputFile: "/project/in/model.dat", format: format,
                               outputFile: "/project/out/packed", overwrite: true,
                               options: .init(deferredMatching: false, maxChainLength: 1)), in: fst)
            try decompress(.init(inputFile: "/project/out/packed",
                                 outputFile: "/project/out/model.dat", overwrite: true), in: fst)
            assertBytesEqual(try bytes(at: "/project/out/model.dat", in: fst), sample, format.rawValue)
        }
    }

    /// The LZSS geometry is honored by the encoder, not just the decoder:
    /// a stream cut with one geometry only decodes under that geometry.
    func testLZSSGeometryShapesTheStreamInBothDirections() throws {
        let geometry = CompressionOps.Options(windowBits: 10, lengthBits: 6, threshold: 1)
        for format in [CompressionOps.Format.lzss, .lzssRaw] {
            let fst = InMemoryFST()
            try write(sample, at: "/project/in/model.dat", in: fst)
            try compress(.init(inputFile: "/project/in/model.dat", format: format,
                               outputFile: "/project/out/custom", overwrite: true, options: geometry), in: fst)
            try compress(.init(inputFile: "/project/in/model.dat", format: format,
                               outputFile: "/project/out/standard", overwrite: true), in: fst)
            XCTAssertNotEqual(try bytes(at: "/project/out/custom", in: fst), try bytes(at: "/project/out/standard", in: fst))

            try decompress(.init(inputFile: "/project/out/custom", format: format,
                                 outputFile: "/project/out/model.dat", overwrite: true, options: geometry), in: fst)
            assertBytesEqual(try bytes(at: "/project/out/model.dat", in: fst), sample, format.rawValue)

            // Without the geometry the pairs are unpacked with the wrong split.
            let misread = try? decompress(.init(inputFile: "/project/out/custom", format: format,
                                                outputFile: "/project/out/misread.dat", overwrite: true), in: fst)
            let output = fst.readFile(at: File("/project/out/misread.dat"))?.allData?.rawBytes
            XCTAssertTrue(misread == nil || output != sample, "\(format.rawValue): the default geometry must not decode a custom stream")
        }
    }

    // MARK: - Derived names

    func testCompressDerivesAnOutputNameBesideTheInput() throws {
        let expected: [CompressionOps.Format: String] = [
            .yaz0: "model.dat.szs", .yay0: "model.dat.szp", .lzss: "model.dat.lzss", .lzssRaw: "model.dat.lzss",
        ]
        for (format, name) in expected {
            let fst = InMemoryFST()
            try write(sample, at: "/project/in/model.dat", in: fst)
            try compress(.init(inputFile: "/project/in/model.dat", format: format), in: fst)
            XCTAssertNotNil(fst.inspectFile(at: File("/project/in/\(name)")), "\(format.rawValue) should write \(name)")
        }
    }

    func testDecompressDerivesAnOutputNameBesideTheInput() throws {
        let stream = Yaz0Compressor().compress(data(sample)).rawBytes
        let expected = [
            "model.dat.szs": "model.dat",   // compressed extension dropped
            "archive.SZS": "archive",       // case-insensitively
            "blob.bin": "blob.bin.bin",     // unknown extension: never the input's name
            "noext": "noext.bin",
            ".szs": "decompressed.bin",
        ]
        for (input, output) in expected {
            let fst = InMemoryFST()
            try write(stream, at: "/project/in/\(input)", in: fst)
            try decompress(.init(inputFile: File("/project/in/\(input)")), in: fst)
            assertBytesEqual(try bytes(at: "/project/in/\(output)", in: fst), sample, "\(input) → \(output)")
        }
    }

    func testOverwriteFalseRefusesAnExistingOutput() throws {
        let fst = InMemoryFST()
        try write(sample, at: "/project/in/model.dat", in: fst)
        try write([0xAA], at: "/project/out/taken", in: fst)

        XCTAssertThrowsError(try compress(.init(inputFile: "/project/in/model.dat", format: .yaz0,
                                                outputFile: "/project/out/taken", overwrite: false), in: fst))
        assertBytesEqual(try bytes(at: "/project/out/taken", in: fst), [0xAA], "must be left alone")

        try write(Yaz0Compressor().compress(data(sample)).rawBytes, at: "/project/in/model.szs", in: fst)
        XCTAssertThrowsError(try decompress(.init(inputFile: "/project/in/model.szs",
                                                  outputFile: "/project/out/taken", overwrite: false), in: fst))
        assertBytesEqual(try bytes(at: "/project/out/taken", in: fst), [0xAA], "must be left alone")
    }

    // MARK: - Bulk

    private func populateTree(in fst: InMemoryFST) throws {
        try write(sample, at: "/project/in/a.dat", in: fst)
        try write(Array(sample.reversed()), at: "/project/in/sub/b.gtx", in: fst)
        try write(Array("not a model".utf8), at: "/project/in/notes.txt", in: fst)
        try write(Array(sample[0 ..< 100]), at: "/project/in/sub/deeper/c.dat", in: fst)
    }

    func testBulkCompressMirrorsLayoutAndFiltersByExtension() throws {
        let fst = InMemoryFST()
        try populateTree(in: fst)
        let logger = RecordingLogger()
        try compress(.init(inputFolder: "/project/in", outputFolder: "/project/out", format: .yaz0,
                           overwrite: true, recursive: true, extensions: ["dat", ".GTX"]), in: fst, logger: logger)

        XCTAssertNotNil(fst.inspectFile(at: File("/project/out/a.dat.szs")))
        XCTAssertNotNil(fst.inspectFile(at: File("/project/out/sub/b.gtx.szs")))
        XCTAssertNotNil(fst.inspectFile(at: File("/project/out/sub/deeper/c.dat.szs")))
        XCTAssertNil(fst.inspectFile(at: File("/project/out/notes.txt.szs")), "filtered out")
        XCTAssertEqual(CompressionFormat.detect(data(try bytes(at: "/project/out/sub/b.gtx.szs", in: fst))), .yaz0)
        XCTAssertTrue(infoMessages(logger).contains { $0.contains("compressed 3") && $0.contains("skipped 1") },
                      "expected a summary line, got \(infoMessages(logger))")
    }

    func testBulkCompressHonorsTheOutputExtensionAndDoesNotRecurseByDefault() throws {
        let fst = InMemoryFST()
        try populateTree(in: fst)
        try compress(.init(inputFolder: "/project/in", outputFolder: "/project/out", format: .lzss,
                           overwrite: true, outputExtension: ".packed"), in: fst)

        XCTAssertNotNil(fst.inspectFile(at: File("/project/out/a.dat.packed")))
        XCTAssertNotNil(fst.inspectFile(at: File("/project/out/notes.txt.packed")), "no filter takes every file")
        XCTAssertNil(fst.inspectFolder(at: Folder("/project/out/sub")), "not recursive")
        XCTAssertEqual(CompressionFormat.detect(data(try bytes(at: "/project/out/a.dat.packed", in: fst))), .lzss)
    }

    func testBulkCompressRejectsAnEmptyOutputExtension() throws {
        let fst = InMemoryFST()
        try populateTree(in: fst)
        XCTAssertThrowsError(try compress(.init(inputFolder: "/project/in", outputFolder: "/project/out",
                                                format: .lzss, outputExtension: "."), in: fst)) { error in
            guard case CompressionErrors.invalidOutputExtension = error else {
                return XCTFail("expected invalidOutputExtension, got \(error)")
            }
        }
    }

    func testBulkDecompressSkipsUnrecognizedFilesAndMirrorsLayout() throws {
        let fst = InMemoryFST()
        try write(Yaz0Compressor().compress(data(sample)).rawBytes, at: "/project/packed/a.dat.szs", in: fst)
        try write(Yay0Compressor().compress(data(sample)).rawBytes, at: "/project/packed/sub/b.gtx.szp", in: fst)
        try write(LZSSHeaderedCompressor().compress(data(sample)).rawBytes, at: "/project/packed/sub/c.lzss", in: fst)
        try write(Array("readme".utf8), at: "/project/packed/readme.txt", in: fst)
        let logger = RecordingLogger()

        try decompress(.init(inputFolder: "/project/packed", outputFolder: "/project/out",
                             overwrite: true, recursive: true), in: fst, logger: logger)

        assertBytesEqual(try bytes(at: "/project/out/a.dat", in: fst), sample)
        assertBytesEqual(try bytes(at: "/project/out/sub/b.gtx", in: fst), sample)
        assertBytesEqual(try bytes(at: "/project/out/sub/c", in: fst), sample)
        XCTAssertNil(fst.inspectFile(at: File("/project/out/readme.txt.bin")), "not a stream")
        XCTAssertTrue(infoMessages(logger).contains { $0.contains("decompressed 3") && $0.contains("skipped 1") },
                      "expected a summary line, got \(infoMessages(logger))")
    }

    func testBulkDecompressWithANamedFormatSkipsOtherFormats() throws {
        let fst = InMemoryFST()
        try write(Yaz0Compressor().compress(data(sample)).rawBytes, at: "/project/packed/a.szs", in: fst)
        try write(Yay0Compressor().compress(data(sample)).rawBytes, at: "/project/packed/b.szp", in: fst)

        try decompress(.init(inputFolder: "/project/packed", outputFolder: "/project/out",
                             format: .yay0, overwrite: true), in: fst)

        XCTAssertNil(fst.inspectFile(at: File("/project/out/a")), "yaz0 is not what was asked for")
        assertBytesEqual(try bytes(at: "/project/out/b", in: fst), sample)
    }

    func testBulkDecompressRawLZSSTakesEveryCandidateSoTheFilterSelects() throws {
        let fst = InMemoryFST()
        try write(LZSSCompressor().compress(data(sample)).rawBytes, at: "/project/packed/a.lzss", in: fst)
        try write(LZSSCompressor().compress(data(sample)).rawBytes, at: "/project/packed/sub/b.lzss", in: fst)
        try write(Array("readme".utf8), at: "/project/packed/readme.txt", in: fst)

        try decompress(.init(inputFolder: "/project/packed", outputFolder: "/project/out", format: .lzssRaw,
                             overwrite: true, recursive: true, extensions: ["lzss"]), in: fst)

        assertBytesEqual(try bytes(at: "/project/out/a", in: fst), sample)
        assertBytesEqual(try bytes(at: "/project/out/sub/b", in: fst), sample)
        XCTAssertNil(fst.inspectFile(at: File("/project/out/readme.txt.bin")))
    }

    func testBulkDecompressAppliesTheRangeToEveryFile() throws {
        let fst = InMemoryFST()
        let junk = [UInt8](repeating: 0x11, count: 8)
        try write(junk + Yaz0Compressor().compress(data(sample)).rawBytes, at: "/project/packed/a.bin", in: fst)
        try write(junk + LZSSHeaderedCompressor().compress(data(sample)).rawBytes, at: "/project/packed/b.bin", in: fst)

        try decompress(.init(inputFolder: "/project/packed", outputFolder: "/project/out",
                             range: .init(offset: junk.count), overwrite: true), in: fst)

        assertBytesEqual(try bytes(at: "/project/out/a.bin.bin", in: fst), sample)
        assertBytesEqual(try bytes(at: "/project/out/b.bin.bin", in: fst), sample)
    }

    func testBulkOperationsRejectAMissingInputFolder() throws {
        let fst = InMemoryFST()
        XCTAssertThrowsError(try compress(.init(inputFolder: "/project/nowhere", outputFolder: "/project/out", format: .yaz0), in: fst))
        XCTAssertThrowsError(try decompress(.init(inputFolder: "/project/nowhere", outputFolder: "/project/out"), in: fst))
    }

    func testBulkDecompressValidatesANamedFormatsOptionsUpFront() throws {
        let fst = InMemoryFST()
        try write(Yaz0Compressor().compress(data(sample)).rawBytes, at: "/project/packed/a.szs", in: fst)
        XCTAssertThrowsError(try decompress(.init(inputFolder: "/project/packed", outputFolder: "/project/out",
                                                  format: .yaz0, options: .init(windowBits: 12)), in: fst)) { error in
            guard case CompressionErrors.optionNotApplicable = error else {
                return XCTFail("expected optionNotApplicable, got \(error)")
            }
        }
        XCTAssertNil(fst.inspectFolder(at: Folder("/project/out")), "nothing written")
    }

    // MARK: - Naming rules

    func testFormatNamesAreHyphenatedLowercaseStrings() {
        XCTAssertEqual(CompressionOps.Format.yaz0.rawValue, "yaz0")
        XCTAssertEqual(CompressionOps.Format.yay0.rawValue, "yay0")
        XCTAssertEqual(CompressionOps.Format.lzss.rawValue, "lzss")
        XCTAssertEqual(CompressionOps.Format.lzssRaw.rawValue, "lzss-raw")
        XCTAssertNil(CompressionOps.Format(rawValue: "lzssRaw"))
        XCTAssertNil(CompressionOps.Format(rawValue: "Yaz0"))
    }

    func testEveryDetectableFormatRoundTripsThroughTheFoundationEnum() {
        for detected in CompressionFormat.allCases {
            XCTAssertEqual(CompressionOps.Format(detected: detected).detectable, detected)
        }
        XCTAssertNil(CompressionOps.Format.lzssRaw.detectable)
    }
}
