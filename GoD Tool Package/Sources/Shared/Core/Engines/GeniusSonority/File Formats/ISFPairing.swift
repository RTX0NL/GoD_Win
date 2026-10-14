//
//  ISFPairing.swift
//  GeniusSonority
//
//  Pairs the halves of ISF sounds stored in one FSYS archive: each `I_SF`
//  header (`.ish`) with the DSP-ADPCM stream (`.isd`) it describes.
//
//  Nameless halves are named by entry index, and the audio dump pairs them
//  by filename stem, so a stream has to be given its header's index. In an
//  archive holding many sounds the halves do not run in step:
//  `stm_se_nakigoe_archive` on XD stores 388 headers, then 388 streams, and
//  neither "the stream's FSYS identifier is the header's + 1" nor "the
//  stream sits 387 entries after its header" holds for all of them (379 and
//  384 of 388 on the US disc).
//
//  So a candidate is only accepted when its content confirms it. Each
//  channel's ADPCM block in the stream starts with that channel's
//  predictor/scale byte, which the header also records: channel k's
//  coefficient block starts at 0x40 + 0x40·k, its predictor/scale byte is
//  at 0x63 + 0x40·k, and its data starts at k × interleave (0x18) in the
//  stream. That check passes for all 379 identifier pairs on both
//  channels. On its own it can't find a pair (many headers share bytes
//  with several streams), but it reliably rejects a wrong one.
//
//  Pass 1 takes identifier + 1 when the content agrees. Pass 2 matches the
//  leftover headers to the leftover streams, only where the match is unique
//  both ways. Anything still unmatched stays unpaired, and the caller
//  reports it: a wrong pair would decode one Pokémon's cry as another's.
//

import Foundation
import GoDFoundation

enum ISFPairing {

    struct Half {
        let entryIndex: Int
        let identifier: Int
        let data: GoDData
    }

    struct Result: Equatable {
        /// Stream entry index → header entry index.
        var streamToHeader: [Int: Int]
        /// Header entry indices left without a stream, in archive order.
        var unpairedHeaders: [Int]
        /// The pass-2 subset of `streamToHeader`: pairs backed by content
        /// alone, which the caller reports so they can be audited.
        var contentOnly: [Int: Int] = [:]
    }

    static func pair(headers: [Half], streams: [Half]) -> Result {
        var streamToHeader = [Int: Int]()
        var pairedHeaders = Set<Int>()

        // Pass 1: identifier + 1, confirmed by content.
        var streamByIdentifier = [Int: Half]()
        for stream in streams where streamByIdentifier[stream.identifier] == nil {
            streamByIdentifier[stream.identifier] = stream
        }
        for header in headers {
            guard let stream = streamByIdentifier[header.identifier + 1],
                  streamToHeader[stream.entryIndex] == nil,
                  fits(header: header.data, stream: stream.data) else { continue }
            streamToHeader[stream.entryIndex] = header.entryIndex
            pairedHeaders.insert(header.entryIndex)
        }

        // Pass 2: leftovers, only where the content match is unique both
        // ways. One round is all there is: an accepted stream fitted no
        // other open header, so accepting it can't make another match unique.
        let freeStreams = streams.filter { streamToHeader[$0.entryIndex] == nil }
        let openHeaders = headers.filter { !pairedHeaders.contains($0.entryIndex) }
        var candidates = [Int: [Int]]()        // header → streams it fits
        var claimants = [Int: Int]()           // stream → number of headers it fits
        for header in openHeaders {
            let fitting = freeStreams.filter { fits(header: header.data, stream: $0.data) }.map(\.entryIndex)
            candidates[header.entryIndex] = fitting
            for stream in fitting { claimants[stream, default: 0] += 1 }
        }
        var contentOnly = [Int: Int]()
        for header in openHeaders {
            guard let fitting = candidates[header.entryIndex], fitting.count == 1,
                  let stream = fitting.first, claimants[stream] == 1 else { continue }
            streamToHeader[stream] = header.entryIndex
            contentOnly[stream] = header.entryIndex
            pairedHeaders.insert(header.entryIndex)
        }

        let unpaired = headers.map(\.entryIndex).filter { !pairedHeaders.contains($0) }
        return Result(streamToHeader: streamToHeader, unpairedHeaders: unpaired, contentOnly: contentOnly)
    }

    /// Whether every channel's first predictor/scale byte in `stream` is the
    /// one `header` records for it. False for anything that isn't a
    /// plausible ISF header, rather than a guess.
    static func fits(header: GoDData, stream: GoDData) -> Bool {
        guard let channels = u32(header, at: 0x14), (1...8).contains(channels),
              let interleave = u32(header, at: 0x18), interleave > 0 else { return false }
        for channel in 0..<Int(channels) {
            guard let recorded = byte(header, at: 0x63 + 0x40 * channel),
                  let actual = byte(stream, at: channel * Int(interleave)),
                  recorded == actual else { return false }
        }
        return true
    }

    private static func byte(_ data: GoDData, at offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.length else { return nil }
        return data.read(atAddress: offset, length: 1)?.rawBytes.first
    }

    private static func u32(_ data: GoDData, at offset: Int) -> UInt32? {
        guard offset + 4 <= data.length,
              let bytes = data.read(atAddress: offset, length: 4)?.rawBytes else { return nil }
        return bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }
}
