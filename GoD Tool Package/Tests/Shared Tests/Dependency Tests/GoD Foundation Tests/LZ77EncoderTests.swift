//
//  LZ77EncoderTests.swift
//
//  Coverage for the match finder shared by Yaz0 and Yay0, at the token
//  level — before any container gets involved. The properties asserted here
//  are the ones a codec relies on when it packs a token into bit fields: a
//  distance that fits the window, a length that fits the count field, and a
//  token list that replays to exactly the input.
//

import Foundation
import XCTest
@testable import GoDFoundation

final class LZ77EncoderTests: XCTestCase {

    /// Reconstructs the input from its tokens, the way a decoder would.
    private func replay(_ tokens: [LZ77Token]) -> [UInt8] {
        var output: [UInt8] = []
        for token in tokens {
            switch token {
            case .literal(let byte):
                output.append(byte)
            case let .match(distance, length):
                let start = output.count - distance
                for offset in 0 ..< length {
                    let byte = output[start + offset]
                    output.append(byte)
                }
            }
        }
        return output
    }

    private func assertTokensAreWellFormed(
        _ tokens: [LZ77Token],
        for input: [UInt8],
        configuration: LZ77Encoder.Configuration = .nintendo,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(replay(tokens), input, "tokens do not replay to the input", file: file, line: line)

        var position = 0
        for token in tokens {
            switch token {
            case .literal:
                position += 1
            case let .match(distance, length):
                XCTAssertGreaterThan(distance, 0, "distance must be positive", file: file, line: line)
                XCTAssertLessThanOrEqual(
                    distance, configuration.windowSize,
                    "distance reaches outside the window", file: file, line: line
                )
                XCTAssertLessThanOrEqual(
                    distance, position,
                    "distance reaches before the start of the output", file: file, line: line
                )
                XCTAssertGreaterThanOrEqual(
                    length, configuration.minMatchLength,
                    "match is shorter than the minimum", file: file, line: line
                )
                XCTAssertLessThanOrEqual(
                    length, configuration.maxMatchLength,
                    "match is longer than the container can express", file: file, line: line
                )
                position += length
            }
        }
    }

    // MARK: - Shape

    func testEmptyInputProducesNoTokens() {
        XCTAssertTrue(LZ77Encoder().tokenize([]).isEmpty)
    }

    func testInputShorterThanMinimumMatchIsAllLiterals() {
        let tokens = LZ77Encoder().tokenize([0x01, 0x02])
        XCTAssertEqual(tokens, [.literal(0x01), .literal(0x02)])
    }

    func testIncompressibleInputIsAllLiterals() {
        var state: UInt32 = 0xDEAD_BEEF
        let input = (0 ..< 256).map { _ -> UInt8 in
            state = 1_664_525 &* state &+ 1_013_904_223
            return UInt8(state >> 24)
        }
        let tokens = LZ77Encoder().tokenize(input)
        assertTokensAreWellFormed(tokens, for: input)
        XCTAssertTrue(
            tokens.allSatisfy { if case .literal = $0 { return true } else { return false } },
            "random data should not produce matches"
        )
    }

    func testRunBecomesALiteralFollowedByAMatch() {
        let input = [UInt8](repeating: 0x5A, count: 64)
        let tokens = LZ77Encoder().tokenize(input)
        assertTokensAreWellFormed(tokens, for: input)
        XCTAssertEqual(tokens.first, .literal(0x5A))
        XCTAssertEqual(tokens.count, 2, "a uniform run should encode as one literal plus one match")
        XCTAssertEqual(tokens.last, .match(distance: 1, length: 63))
    }

    func testTwoByteRepeatIsNotWorthAMatch() {
        // "AB" recurring with nothing longer in common: a two-byte match
        // costs as much as the literals it replaces, so it is not taken.
        let input: [UInt8] = [0x41, 0x42, 0x43, 0x41, 0x42, 0x44]
        let tokens = LZ77Encoder().tokenize(input)
        assertTokensAreWellFormed(tokens, for: input)
        XCTAssertTrue(tokens.allSatisfy { if case .literal = $0 { return true } else { return false } })
    }

    // MARK: - Bounds

    func testLongRunSplitsAtTheMaximumMatchLength() {
        let input = [UInt8](repeating: 0x00, count: 2000)
        let tokens = LZ77Encoder().tokenize(input)
        assertTokensAreWellFormed(tokens, for: input)

        let longest = tokens.compactMap { token -> Int? in
            if case let .match(_, length) = token { return length }
            return nil
        }.max()
        XCTAssertEqual(longest, 0x111, "a long run should saturate the maximum match length")
    }

    func testMatchesNeverReachOutsideTheWindow() {
        // A phrase, then more than a window's worth of filler, then the
        // phrase again — the repeat is out of reach and must stay literal.
        let phrase = Array("GENIUS SONORITY".utf8)
        var state: UInt32 = 0x0C0F_FEE0
        let filler = (0 ..< 0x1400).map { _ -> UInt8 in
            state = 1_664_525 &* state &+ 1_013_904_223
            return UInt8(state >> 24)
        }
        let input = phrase + filler + phrase
        assertTokensAreWellFormed(LZ77Encoder().tokenize(input), for: input)
    }

    func testHonorsACustomConfiguration() {
        let configuration = LZ77Encoder.Configuration(
            windowSize: 0x40,
            minMatchLength: 3,
            maxMatchLength: 0x20,
            usesDeferredMatching: false
        )
        let input = [UInt8](repeating: 0xCC, count: 500)
        let tokens = LZ77Encoder(configuration: configuration).tokenize(input)
        assertTokensAreWellFormed(tokens, for: input, configuration: configuration)
    }

    // MARK: - Deferred matching

    /// The heuristic is a size trade, not a correctness one, so both
    /// settings have to replay to the same bytes.
    func testDeferredMatchingReplaysIdenticallyToGreedyMatching() {
        var bytes = Array("SHADOW POKEMON PURIFICATION".utf8)
        bytes += Array("SHADOW POKEMON".utf8)
        bytes += [UInt8](repeating: 0x20, count: 40)
        bytes += Array("PURIFICATION CHAMBER".utf8)

        let greedy = LZ77Encoder(configuration: .init(usesDeferredMatching: false)).tokenize(bytes)
        let deferred = LZ77Encoder(configuration: .init(usesDeferredMatching: true)).tokenize(bytes)

        assertTokensAreWellFormed(greedy, for: bytes)
        assertTokensAreWellFormed(deferred, for: bytes)
    }

    /// The deferral exists to find a longer match one byte later; on input
    /// built to reward it, it should not do worse than greedy.
    func testDeferredMatchingDoesNotProduceMoreOperations() {
        var bytes: [UInt8] = []
        for index in 0 ..< 200 {
            bytes += Array("ORRE_\(index % 17)_COLOSSEUM".utf8)
        }
        let greedy = LZ77Encoder(configuration: .init(usesDeferredMatching: false)).tokenize(bytes)
        let deferred = LZ77Encoder(configuration: .init(usesDeferredMatching: true)).tokenize(bytes)
        XCTAssertLessThanOrEqual(deferred.count, greedy.count)
    }

    // MARK: - Match selection

    /// Among matches of equal length the furthest back is taken, which is
    /// what the reference encoder does.
    func testEqualLengthMatchesPreferTheFurthestBack() {
        // "XYZ!" appears at 0 and again at 4; the match at position 8 can
        // reach either, and both run three bytes.
        let input: [UInt8] = Array("XYZ!XYZ?XYZ".utf8)
        let tokens = LZ77Encoder().tokenize(input)
        assertTokensAreWellFormed(tokens, for: input)

        let distances = tokens.compactMap { token -> Int? in
            if case let .match(distance, _) = token { return distance }
            return nil
        }
        XCTAssertEqual(distances.last, 8, "expected the older of the two equal-length matches")
    }

    func testOverlappingMatchesAreAllowed() {
        // A three-byte cycle: the match reads bytes it is itself writing.
        let input = [UInt8](repeating: 0, count: 30).enumerated().map { UInt8($0.offset % 3) }
        let tokens = LZ77Encoder().tokenize(input)
        assertTokensAreWellFormed(tokens, for: input)
        XCTAssertTrue(
            tokens.contains { token in
                if case let .match(distance, length) = token { return length > distance }
                return false
            },
            "expected at least one match that reads past its own start"
        )
    }
}
