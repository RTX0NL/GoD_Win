//
//  MusyXSongTests.swift
//
//  MusyX songs to MIDI. The synthetic song has one track with one pattern:
//  a program change, a rest, two notes (one transposed past the top of the
//  key range) and a loop back to the first entry. GODDESS_MUSYX_SONGS points
//  the corpus test at a folder of `*_song.samp` files.
//

import XCTest
import Foundation
import GoDFoundation
@testable import GeniusSonority

final class MusyXSongTests: XCTestCase {

    private func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    private func be32(_ v: Int) -> [UInt8] { be16(v >> 16) + be16(v & 0xFFFF) }

    private var song: [UInt8] {
        // Layout: header 0x18 | track table 64*4 | channel table 64 |
        // pattern table | track entries | pattern | tempo.
        let trackTable = 0x18, channelTable = trackTable + 256, patternTable = channelTable + 64
        let entries = patternTable + 4, pattern = entries + 24, tempo = pattern + 12 + 4 + 4 + 6 + 6 + 4
        var bytes = be32(trackTable) + be32(patternTable) + be32(channelTable) + be32(tempo)
        bytes += be32(120) + be32(0)                                      // 120 bpm, integer form
        bytes += be32(entries) + [UInt8](repeating: 0, count: 252)       // track 0 only
        bytes += [3] + [UInt8](repeating: 0, count: 63)                  // track 0 on channel 3
        bytes += be32(pattern)
        // entry 0: time 0, no program, volume 100, pattern 0, transpose +2, velocity add -10
        bytes += be32(0) + [0xFF, 100] + be16(0) + be16(0) + [2, 0xF6]
        // entry 1: time 768, loop to entry 0
        bytes += be32(768) + [0xFF, 0xFF] + be16(0) + be16(0xFFFE) + be16(0)
        bytes += be32(12) + be32(0) + be32(0)                            // pattern header, no streams
        bytes += be16(0) + [0x85, 0x00]                                  // program 5
        bytes += be16(10) + [0x00, 0x00]                                 // rest of 10 ticks
        bytes += be16(0) + [60, 90] + be16(96)                           // C4 at tick 10
        bytes += be16(96) + [127, 120] + be16(48)                        // key 127 + 2 clamps to 127
        bytes += be16(0) + [0xFF, 0xFF]                                  // end of pattern
        bytes += be32(0) + be32(120) + be32(384) + be32(90) + be32(0xFFFF_FFFF)
        return bytes
    }

    func testASongParses() throws {
        let parsed = try MusyXSong(bytes: song)
        XCTAssertEqual(parsed.bpm, 120)
        XCTAssertEqual(parsed.tempo.map(\.bpm), [120, 90])
        XCTAssertEqual(parsed.tracks.count, 1)
        let track = try XCTUnwrap(parsed.tracks.first)
        XCTAssertEqual(track.channel, 3)
        XCTAssertEqual(track.events, [
            .controller(time: 0, number: 7, value: 100),
            .program(time: 0, program: 5),
            .note(.init(time: 10, key: 62, velocity: 80, length: 96)),
            .note(.init(time: 106, key: 127, velocity: 110, length: 48)),
            .loop(time: 768, to: 0),
        ])
    }

    func testTheMIDIFileIsWellFormed() throws {
        let midi = try MusyXSong(bytes: song).midi(name: "test")
        XCTAssertEqual(Array(midi[0 ..< 4]), Array("MThd".utf8))
        XCTAssertEqual(Array(midi[8 ..< 14]), [0, 1, 0, 2, 0x01, 0x80], "format 1, 2 tracks, 384 PPQ")
        // Walk both track chunks to their ends.
        var at = 14
        for _ in 0 ..< 2 {
            XCTAssertEqual(Array(midi[at ..< at + 4]), Array("MTrk".utf8))
            let length = Int(midi[at + 4]) << 24 | Int(midi[at + 5]) << 16 | Int(midi[at + 6]) << 8 | Int(midi[at + 7])
            XCTAssertEqual(Array(midi[at + 8 + length - 3 ..< at + 8 + length]), [0xFF, 0x2F, 0x00], "track ends")
            at += 8 + length
        }
        XCTAssertEqual(at, midi.count)
        XCTAssertNotNil(midi.firstRange(of: [0x93, 62, 80]), "note on, channel 4, transposed and velocity-adjusted")
        XCTAssertNotNil(midi.firstRange(of: [0xC3, 5]), "program change")
        XCTAssertNotNil(midi.firstRange(of: Array("loopStart".utf8)))
    }

    func testATruncatedSongIsAnError() {
        XCTAssertThrowsError(try MusyXSong(bytes: Array(song.prefix(0x170))), "cut inside the track entries")
    }

    func testEveryRealSongConverts() throws {
        guard let folder = ProcessInfo.processInfo.environment["GODDESS_MUSYX_SONGS"],
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else {
            throw XCTSkip("Set GODDESS_MUSYX_SONGS to a folder of *_song.samp files")
        }
        let songs = names.filter { $0.hasSuffix("_song.samp") }
        XCTAssertFalse(songs.isEmpty)
        var silent = [String]()
        for name in songs {
            let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent(name)))
            let parsed = try MusyXSong(bytes: bytes)
            XCTAssertFalse(parsed.tracks.isEmpty, name)
            if parsed.tracks.allSatisfy({ $0.noteCount == 0 }) { silent.append(name) }
            XCTAssertEqual(Array(parsed.midi(name: name).prefix(4)), Array("MThd".utf8))
        }
        // Colosseum's null_bgm is a song with nothing in it, there to stop
        // the music; every other song has notes.
        XCTAssertLessThanOrEqual(silent.count, 1, "\(silent)")
    }
}
