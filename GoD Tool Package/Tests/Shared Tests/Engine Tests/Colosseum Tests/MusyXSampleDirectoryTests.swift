//
//  MusyXSampleDirectoryTests.swift
//
//  MusyX `.sdir` parsing and sample decoding. GODDESS_MUSYX_SDIR and
//  GODDESS_MUSYX_SAMP point the corpus test at a folder of `.sdir` files and
//  the folder holding their `.samp` banks.
//

import XCTest
import Foundation
import GoDFoundation
@testable import GeniusSonority

final class MusyXSampleDirectoryTests: XCTestCase {

    private func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    private func be32(_ v: Int) -> [UInt8] { be16(v >> 16) + be16(v & 0xFFFF) }

    /// A directory of one sample: id 7, 28 samples (two frames) at offset 0
    /// of the `.samp`, 22050 Hz, base pitch 60, starting from history
    /// (hist1 100, hist2 0), with pair 0 = (2048, 0), i.e. "repeat the last
    /// sample".
    private func directory(format: Int = 0, offset: Int = 0) -> [UInt8] {
        let paramsAt = 0x40
        var entry = be16(7) + be16(0) + be32(offset) + be32(0)
        entry += [60, 0] + be16(22050) + be32(format << 24 | 28) + be32(0) + be32(0) + be32(paramsAt)
        let terminator = be16(0xFFFF) + [UInt8](repeating: 0, count: 0x1E)
        let coefficients = [2048, 0] + [Int](repeating: 0, count: 14)
        let params = be16(8) + [0x00, 0] + be16(0) + be16(100) + coefficients.flatMap(be16)
        return entry + terminator + params
    }

    /// Two frames, header 0x00 (pair 0, scale 1), every nibble 0.
    private let samp: [UInt8] = [UInt8](repeating: 0, count: 16)

    func testAnEntryParses() throws {
        let sample = try XCTUnwrap(try MusyXSampleDirectory(bytes: directory()).samples.first)
        XCTAssertEqual(sample.id, 7)
        XCTAssertEqual(sample.sampleRate, 22050)
        XCTAssertEqual(sample.sampleCount, 28)
        XCTAssertEqual(sample.basePitch, 60)
        XCTAssertEqual(sample.hist1, 100)
        XCTAssertEqual(sample.hist2, 0)
        XCTAssertEqual(sample.byteLength, 16)
        XCTAssertEqual(try MusyXSampleDirectory(bytes: directory()).samples.count, 1, "the 0xFFFF id ends the list")
    }

    /// MusyX stores the decoder state each sample starts from; with pair
    /// (1.0, 0) and silent nibbles every sample repeats it. Starting from
    /// zero, as ISF does, would give silence.
    func testDecodingStartsFromTheStoredHistory() throws {
        let sample = try XCTUnwrap(try MusyXSampleDirectory(bytes: directory()).samples.first)
        let pcm = try MusyXSampleDirectory.decode(sample, samp: samp)
        XCTAssertEqual(pcm.count, 28)
        XCTAssertEqual(Set(pcm), [100])
    }

    func testTheWAVCarriesTheSampleRate() throws {
        let sample = try XCTUnwrap(try MusyXSampleDirectory(bytes: directory()).samples.first)
        let wav = try MusyXSampleDirectory.wav(sample, samp: samp)
        XCTAssertEqual(Array(wav[0 ..< 4]), Array("RIFF".utf8))
        XCTAssertEqual(Int(wav[24]) | Int(wav[25]) << 8, 22050)
    }

    func testANonADPCMSampleIsRefused() throws {
        let sample = try XCTUnwrap(try MusyXSampleDirectory(bytes: directory(format: 1)).samples.first)
        XCTAssertThrowsError(try MusyXSampleDirectory.decode(sample, samp: samp))
    }

    func testASampleRunningPastTheBankIsRefused() throws {
        let sample = try XCTUnwrap(try MusyXSampleDirectory(bytes: directory(offset: 8)).samples.first)
        XCTAssertThrowsError(try MusyXSampleDirectory.decode(sample, samp: samp))
    }

    func testATruncatedDirectoryIsAnError() {
        XCTAssertThrowsError(try MusyXSampleDirectory(bytes: Array(directory().prefix(0x30))))
    }

    // MARK: - Real banks

    func testEveryRealSampleDecodesToItsFullLength() throws {
        let env = ProcessInfo.processInfo.environment
        guard let sdirFolder = env["GODDESS_MUSYX_SDIR"], let sampFolder = env["GODDESS_MUSYX_SAMP"],
              let names = try? FileManager.default.contentsOfDirectory(atPath: sdirFolder) else {
            throw XCTSkip("Set GODDESS_MUSYX_SDIR and GODDESS_MUSYX_SAMP")
        }
        let banks = names.filter { $0.hasSuffix(".sdir") }.sorted()
        XCTAssertFalse(banks.isEmpty)
        for bank in banks {
            let stem = String(bank.dropLast(5))
            let sdir = [UInt8](try Data(contentsOf: URL(fileURLWithPath: sdirFolder).appendingPathComponent(bank)))
            let samp = [UInt8](try Data(contentsOf: URL(fileURLWithPath: sampFolder).appendingPathComponent(stem + ".samp")))
            for sample in try MusyXSampleDirectory(bytes: sdir).samples {
                XCTAssertEqual(try MusyXSampleDirectory.decode(sample, samp: samp).count, sample.sampleCount,
                               "\(stem) sample \(sample.id)")
            }
        }
    }
}
