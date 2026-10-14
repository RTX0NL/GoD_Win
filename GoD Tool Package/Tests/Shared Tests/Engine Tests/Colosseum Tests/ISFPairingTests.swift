//
//  ISFPairingTests.swift
//  ColosseumTests
//
//  ISFPairing matches `I_SF` headers to their ADPCM streams inside one FSYS
//  archive. Fixtures are synthetic: a header records each channel's first
//  predictor/scale byte at 0x63 + 0x40·k, and a stream starts channel k's
//  data at k × interleave.
//

import XCTest
import GoDFoundation
@testable import GeniusSonority

final class ISFPairingTests: XCTestCase {

    private static let interleave = 0x100

    /// A 0xC0-byte header recording `scales` as its channels' first bytes.
    static func header(scales: [UInt8]) -> GoDData {
        var bytes = [UInt8](repeating: 0, count: 0xC0)
        bytes[0x00..<0x04] = [0x49, 0x5F, 0x53, 0x46]                        // "I_SF"
        bytes[0x14..<0x18] = [0, 0, 0, UInt8(scales.count)]                  // channels
        bytes[0x18..<0x1C] = [0, 0, UInt8(interleave >> 8), UInt8(interleave & 0xFF)]
        for (channel, scale) in scales.enumerated() { bytes[0x63 + 0x40 * channel] = scale }
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    /// A stream whose channel blocks start with `scales`.
    static func stream(scales: [UInt8]) -> GoDData {
        var bytes = [UInt8](repeating: 0x5A, count: interleave * scales.count)
        for (channel, scale) in scales.enumerated() { bytes[channel * interleave] = scale }
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    private func half(_ index: Int, id: Int, _ data: GoDData) -> ISFPairing.Half {
        .init(entryIndex: index, identifier: id, data: data)
    }

    func testIdentifierPlusOneIsTakenWhenTheContentAgrees() {
        let result = ISFPairing.pair(
            headers: [half(0, id: 10, Self.header(scales: [0x21, 0x31])),
                      half(1, id: 20, Self.header(scales: [0x22, 0x32]))],
            // Streams in the opposite order from their headers.
            streams: [half(2, id: 21, Self.stream(scales: [0x22, 0x32])),
                      half(3, id: 11, Self.stream(scales: [0x21, 0x31]))]
        )
        XCTAssertEqual(result, .init(streamToHeader: [3: 0, 2: 1], unpairedHeaders: []))
    }

    /// XD has headers whose identifier + 1 stream belongs to another header.
    /// Content rejects it, and the leftovers are matched where that is unique.
    func testAnOutOfStepPairIsResolvedByUniqueContent() {
        let result = ISFPairing.pair(
            headers: [half(0, id: 10, Self.header(scales: [0x41, 0x51])),
                      half(1, id: 30, Self.header(scales: [0x42, 0x52]))],
            streams: [half(2, id: 11, Self.stream(scales: [0x42, 0x52])),   // id+1 of header 0, content of header 1
                      half(3, id: 99, Self.stream(scales: [0x41, 0x51]))]
        )
        XCTAssertEqual(result, .init(streamToHeader: [3: 0, 2: 1], unpairedHeaders: []))
    }

    /// Two free streams that both fit one header: guessing would decode one
    /// sound as another, so the header stays unpaired.
    func testAnAmbiguousLeftoverStaysUnpaired() {
        let result = ISFPairing.pair(
            headers: [half(0, id: 10, Self.header(scales: [0x61]))],
            streams: [half(1, id: 50, Self.stream(scales: [0x61])),
                      half(2, id: 60, Self.stream(scales: [0x61]))]
        )
        XCTAssertEqual(result, .init(streamToHeader: [:], unpairedHeaders: [0]))
    }

    func testIdentifierPlusOneIsRejectedWhenTheContentDisagrees() {
        let result = ISFPairing.pair(
            headers: [half(0, id: 10, Self.header(scales: [0x71, 0x72]))],
            streams: [half(1, id: 11, Self.stream(scales: [0x71, 0x00]))]   // second channel differs
        )
        XCTAssertEqual(result, .init(streamToHeader: [:], unpairedHeaders: [0]))
    }

    func testDataThatIsNotAnISFHeaderNeverFits() {
        let text = GoDData(byteStream: Array("header one".utf8), byteOrder: .big)
        XCTAssertFalse(ISFPairing.fits(header: text, stream: Self.stream(scales: [0x68])))
    }
}
