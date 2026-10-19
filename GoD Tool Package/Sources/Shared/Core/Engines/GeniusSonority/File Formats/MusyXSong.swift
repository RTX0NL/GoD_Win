//
//  MusyXSong.swift
//
//  MusyX song (arrangement) files and their conversion to a Standard MIDI
//  File. Colosseum's music is all MusyX songs; the FSYS unpack names them
//  `<name>_song.samp` after their FSYS type, though they hold no samples.
//
//  Layout (big-endian), from the MusyX sequencer in the Colosseum
//  decompilation (src/musyx/runtime/seq*.c: fn_801463C4, GenerateNextTrackEvent,
//  fn_801485FC) and checked on all 78 US songs:
//
//    header   u32 track table, u32 pattern table, u32 channel table (u8 per
//             track: its MIDI channel), u32 tempo track (0 = none), u32 info
//             (low 28 bits: bpm; bit 30: bpm is fixed-point x1024; bit 31: a
//             track-section table, unused on the US disc), u32 loop point
//    tracks   64 u32 offsets (0 = no track), each to a list of 12-byte entries:
//             u32 time, u8 program (0xFF = none), u8 volume (0xFF = none),
//             u16 pad, u16 pattern (0xFFFF = end, 0xFFFE = loop to the entry
//             whose index is the u16 at +0xA), s8 transpose, s8 velocity add
//    patterns u32 offsets; each pattern: u32 header length, u32 pitch-bend
//             stream, u32 modulation stream (0 = none), then events:
//               u16 delta time, u8 key, u8 velocity, u16 length   a note
//               key and velocity 0xFF                               the end
//               key bit 7 set (4 bytes)                             a control
//               key and velocity 0 (4 bytes)                        a rest
//             a control with velocity 0 changes program to key & 0x7F; with
//             velocity bit 7 set it sets controller (velocity & 0x7F) to
//             key & 0x7F
//    tempo    (u32 time, u32 bpm) pairs, until a time of 0xFFFFFFFF
//    streams  pitch bend and modulation as (delta time, delta value) pairs,
//             each 1 or 2 bytes (bit 7 of the first byte = 2-byte form), the
//             value sign-extended from 7 or 15 bits, until 0x80 0x00
//
//  Times are ticks at 384 per quarter note, which is what the sequencer's
//  tick arithmetic (SetTickDelta) works out to.
//

import Foundation

public struct MusyXSong {

    public static let ticksPerQuarter = 384
    public static let trackCount = 64

    public struct Note: Equatable {
        public var time: Int
        public var key: Int
        public var velocity: Int
        public var length: Int
    }

    public enum Event: Equatable {
        case note(Note)
        case program(time: Int, program: Int)
        case controller(time: Int, number: Int, value: Int)
        case pitchBend(time: Int, value: Int)
        case loop(time: Int, to: Int)
    }

    public struct Track: Equatable {
        public let index: Int
        public let channel: Int
        public var events: [Event]
    }

    public let bpm: Double
    public let tempo: [(time: Int, bpm: Double)]
    public let tracks: [Track]

    public init(bytes: [UInt8]) throws {
        func u8(_ at: Int) throws -> Int {
            guard at >= 0, at < bytes.count else { throw MusyXSongError.truncated(at) }
            return Int(bytes[at])
        }
        func u16(_ at: Int) throws -> Int { (try u8(at)) << 8 | (try u8(at + 1)) }
        func u32(_ at: Int) throws -> Int { (try u16(at)) << 16 | (try u16(at + 2)) }
        func s8(_ at: Int) throws -> Int { Int(Int8(bitPattern: UInt8(try u8(at)))) }

        let trackTable = try u32(0), patternTable = try u32(4), channelTable = try u32(8)
        let tempoTrack = try u32(12), info = try u32(16)
        let fixedPoint = info & 0x4000_0000 != 0
        let toBPM: (Int) -> Double = { fixedPoint ? Double($0) / 1024 : Double($0) }
        bpm = toBPM(info & 0x0FFF_FFFF)

        var tempo = [(time: Int, bpm: Double)]()
        if tempoTrack != 0 {
            var at = tempoTrack
            while at + 4 <= bytes.count, try u32(at) != 0xFFFF_FFFF {
                tempo.append((try u32(at), toBPM(try u32(at + 4))))
                at += 8
            }
        }
        self.tempo = tempo

        var tracks = [Track]()
        for index in 0 ..< Self.trackCount {
            let trackAt = try u32(trackTable + index * 4)
            guard trackAt != 0 else { continue }
            var events = [Event]()
            var entryIndex = 0
            var entryTimes = [Int]()
            while true {
                let at = trackAt + entryIndex * 12
                let time = try u32(at), program = try u8(at + 4), volume = try u8(at + 5)
                let pattern = try u16(at + 8)
                entryTimes.append(time)
                if pattern == 0xFFFF { break }
                if pattern == 0xFFFE {
                    let target = try u16(at + 0xA)
                    let targetTime = target < entryTimes.count ? entryTimes[target] : try u32(trackAt + target * 12)
                    events.append(.loop(time: time, to: targetTime))
                    break
                }
                if program != 0xFF { events.append(.program(time: time, program: program)) }
                if volume != 0xFF { events.append(.controller(time: time, number: 7, value: volume)) }
                events += try Self.patternEvents(
                    at: try u32(patternTable + pattern * 4), start: time,
                    transpose: try s8(at + 0xA), velocityAdd: try s8(at + 0xB), bytes: bytes
                )
                entryIndex += 1
            }
            tracks.append(Track(index: index, channel: try u8(channelTable + index) & 0x0F, events: events))
        }
        self.tracks = tracks
    }

    private static func patternEvents(
        at pattern: Int, start: Int, transpose: Int, velocityAdd: Int, bytes: [UInt8]
    ) throws -> [Event] {
        func u8(_ at: Int) throws -> Int {
            guard at >= 0, at < bytes.count else { throw MusyXSongError.truncated(at) }
            return Int(bytes[at])
        }
        func u16(_ at: Int) throws -> Int { (try u8(at)) << 8 | (try u8(at + 1)) }
        func u32(_ at: Int) throws -> Int { (try u16(at)) << 16 | (try u16(at + 2)) }

        var events = [Event]()
        var at = pattern + 12
        var time = 0
        while true {
            time += try u16(at)
            let key = try u8(at + 2), velocity = try u8(at + 3)
            if key == 0xFF && velocity == 0xFF { break }
            if key & 0x80 != 0 {
                if velocity == 0 {
                    events.append(.program(time: start + time, program: key & 0x7F))
                } else if velocity & 0x80 != 0, !(0x68 ... 0x6A).contains(velocity & 0x7F) {
                    // 0x68-0x6A drive MusyX's crossfade sync and its own
                    // per-channel state, which MIDI has no counterpart for.
                    events.append(.controller(time: start + time, number: velocity & 0x7F, value: key & 0x7F))
                }
                at += 4
                continue
            }
            if key == 0 && velocity == 0 {
                at += 4
                continue
            }
            events.append(.note(Note(
                time: start + time,
                key: max(0, min(127, key + transpose)),
                velocity: max(1, min(127, velocity + velocityAdd)),
                length: try u16(at + 4)
            )))
            at += 6
        }

        for (offset, base, number) in [(try u32(pattern + 4), 0x2000, -1), (try u32(pattern + 8), 0, 1)] where offset != 0 {
            var value = base
            var streamAt = offset
            var streamTime = 0
            while true {
                guard let (delta, deltaValue, next) = try Self.streamValue(at: streamAt, bytes: bytes) else { break }
                streamTime += delta
                value += deltaValue
                if number < 0 {
                    events.append(.pitchBend(time: start + streamTime, value: max(0, min(0x3FFF, value))))
                } else {
                    events.append(.controller(time: start + streamTime, number: number, value: max(0, min(127, value >> 7))))
                }
                streamAt = next
            }
        }
        return events
    }

    /// One (delta time, delta value) pair of a pitch-bend or modulation
    /// stream, or nil at its 0x80 0x00 end (GetStreamValue in seq.c).
    private static func streamValue(at: Int, bytes: [UInt8]) throws -> (Int, Int, Int)? {
        guard at + 1 < bytes.count else { throw MusyXSongError.truncated(at) }
        var at = at
        if bytes[at] == 0x80 && bytes[at + 1] == 0 { return nil }
        let delta: Int
        if bytes[at] & 0x80 != 0 {
            delta = Int(bytes[at] & 0x7F) << 8 | Int(bytes[at + 1])
            at += 2
        } else {
            delta = Int(bytes[at])
            at += 1
        }
        guard at + 1 < bytes.count else { throw MusyXSongError.truncated(at) }
        let value: Int
        if bytes[at] & 0x80 != 0 {
            let raw = Int(bytes[at] & 0x7F) << 8 | Int(bytes[at + 1])
            value = raw & 0x4000 != 0 ? raw - 0x8000 : raw
            at += 2
        } else {
            let raw = Int(bytes[at])
            value = raw & 0x40 != 0 ? raw - 0x80 : raw
            at += 1
        }
        return (delta, value, at)
    }

    // MARK: - MIDI

    /// The song as a type-1 Standard MIDI File: a tempo track, then one MIDI
    /// track per song track on that track's channel. Programs are MusyX
    /// program numbers, which pick an entry of the bank's song page table,
    /// not General MIDI instruments. A track's loop is marked with
    /// "loopStart" and "loopEnd" markers rather than unrolled.
    public func midi(name: String) -> [UInt8] {
        var chunks = [Self.trackChunk(Self.tempoEvents(name: name, bpm: bpm, tempo: tempo))]
        for track in tracks {
            chunks.append(Self.trackChunk(Self.events(for: track)))
        }
        let header = Array("MThd".utf8) + Self.be32(6) + Self.be16(1) + Self.be16(chunks.count)
            + Self.be16(Self.ticksPerQuarter)
        return header + chunks.flatMap { $0 }
    }

    private typealias TimedEvent = (time: Int, order: Int, bytes: [UInt8])

    private static func tempoEvents(name: String, bpm: Double, tempo: [(time: Int, bpm: Double)]) -> [TimedEvent] {
        var events: [TimedEvent] = [(0, 0, [0xFF, 0x03] + variableLength(name.utf8.count) + Array(name.utf8))]
        let changes = tempo.isEmpty ? [(time: 0, bpm: bpm)] : tempo
        for change in changes where change.bpm > 0 {
            let microseconds = Int((60_000_000 / change.bpm).rounded())
            events.append((change.time, 1, [0xFF, 0x51, 0x03, UInt8(microseconds >> 16 & 0xFF),
                                            UInt8(microseconds >> 8 & 0xFF), UInt8(microseconds & 0xFF)]))
        }
        return events
    }

    private static func events(for track: Track) -> [TimedEvent] {
        let channel = UInt8(track.channel)
        var events: [TimedEvent] = []
        for event in track.events {
            switch event {
            case .note(let note):
                events.append((note.time, 2, [0x90 | channel, UInt8(note.key), UInt8(note.velocity)]))
                events.append((note.time + note.length, 0, [0x80 | channel, UInt8(note.key), 0]))
            case let .program(time, program):
                events.append((time, 1, [0xC0 | channel, UInt8(program & 0x7F)]))
            case let .controller(time, number, value):
                events.append((time, 1, [0xB0 | channel, UInt8(number & 0x7F), UInt8(value & 0x7F)]))
            case let .pitchBend(time, value):
                events.append((time, 1, [0xE0 | channel, UInt8(value & 0x7F), UInt8(value >> 7 & 0x7F)]))
            case let .loop(time, to):
                events.append((to, 0, [0xFF, 0x06, 9] + Array("loopStart".utf8)))
                events.append((time, 3, [0xFF, 0x06, 7] + Array("loopEnd".utf8)))
            }
        }
        return events
    }

    /// Sorts by time (note-offs before everything else at the same tick) and
    /// writes delta times, ending the track.
    private static func trackChunk(_ events: [TimedEvent]) -> [UInt8] {
        var body = [UInt8]()
        var last = 0
        let sorted = events.enumerated().sorted {
            ($0.element.time, $0.element.order, $0.offset) < ($1.element.time, $1.element.order, $1.offset)
        }.map(\.element)
        for event in sorted {
            body += variableLength(event.time - last) + event.bytes
            last = event.time
        }
        body += [0x00, 0xFF, 0x2F, 0x00]
        return Array("MTrk".utf8) + be32(body.count) + body
    }

    private static func variableLength(_ value: Int) -> [UInt8] {
        var value = max(0, value)
        var bytes = [UInt8(value & 0x7F)]
        value >>= 7
        while value > 0 {
            bytes.insert(UInt8(value & 0x7F) | 0x80, at: 0)
            value >>= 7
        }
        return bytes
    }

    private static func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    private static func be32(_ v: Int) -> [UInt8] { be16(v >> 16) + be16(v & 0xFFFF) }
}

extension MusyXSong.Track {
    public var noteCount: Int { events.filter { if case .note = $0 { return true }; return false }.count }
}

public enum MusyXSongError: Error, CustomStringConvertible {
    case truncated(Int)

    public var description: String {
        switch self {
        case .truncated(let at):
            return "MusyX song ends early: needed a byte at 0x\(String(at, radix: 16))"
        }
    }
}
