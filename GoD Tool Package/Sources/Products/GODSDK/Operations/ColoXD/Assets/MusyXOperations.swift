//
//  MusyXOperations.swift
//  GODOps
//
//  MusyX sample banks -> WAV: every sample of every `.sdir` under a folder,
//  decoded from the matching `.samp`, one folder per bank.
//
//  Dump only. A bank's samples are the instruments of its songs and the
//  sounds of its effects; which define, macro or song note plays which
//  sample is in the bank's `.proj` and `.pool`, which this doesn't read.
//

import Foundation
import GoDFoundation
import GeniusSonority

extension ColoXD {

    /// What `<bank>.samples.json` lists for each sample.
    struct MusyXSampleRecord: Codable {
        let id: Int
        let wav: String?
        let sampleRate: Int
        let sampleCount: Int
        let basePitch: Int
        let loopStart: Int
        let loopLength: Int
        let skipped: String?
    }

    static func dumpMusyXSamples(
        sdirFolder: Folder,
        sampFolder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let task = "Dump MusyX sample banks"
        logger?.log(.taskStatus(taskName: task, status: .started))
        let banks = fileSystem.scan(sdirFolder, matches: { $0.fileType == "sdir" })
        logger?.log(.info("Found \(banks.count) MusyX bank(s)"))

        var failures = [String]()
        var written = 0
        for scanned in banks {
            let bank = scanned.file.fileName.withoutExtensions
            let sampFile = sampFolder.file(bank + ".samp")
            do {
                guard let sdir = fileSystem.readFile(at: scanned.file)?.allData?.rawBytes else {
                    throw FSTErrors.fileNotFound(scanned.file, .init())
                }
                guard let samp = fileSystem.readFile(at: sampFile)?.allData?.rawBytes else {
                    throw MusyXOpsError.missingSamp(bank: bank, expected: sampFile, .init())
                }
                let directory = try MusyXSampleDirectory(bytes: sdir)
                let folder = outputFolder.folder(bank)
                var records = [MusyXSampleRecord]()
                for sample in directory.samples {
                    let name = String(format: "%04d.wav", sample.id)
                    do {
                        let wav = try MusyXSampleDirectory.wav(sample, samp: samp)
                        try fileSystem.writeFile(GoDData(byteStream: wav, byteOrder: .little),
                                                 at: folder.file(name), overwrite: overwrite)
                        written += 1
                        records.append(record(sample, wav: name, skipped: nil))
                    } catch let error as MusyXError {
                        // One sample in a format this can't decode costs that
                        // sample, and the JSON says which and why.
                        records.append(record(sample, wav: nil, skipped: error.description))
                        logger?.log(.warning("\(bank): \(error)"))
                    }
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try fileSystem.writeFile(GoDData(byteStream: [UInt8](try encoder.encode(records)), byteOrder: .big),
                                         at: folder.file(bank + ".samples.json"), overwrite: overwrite)
                logger?.log(.info("  \(bank): \(records.count) sample(s) → \(folder.path)"))
            } catch {
                failures.append(bank)
                logger?.log(.warning("Failed to dump MusyX bank \(bank): \(error)"))
            }
        }
        logger?.log(.info("Wrote \(written) WAV file(s)"))
        logger?.log(.taskStatus(taskName: task, status: .completed(failures.isEmpty)))
        if !failures.isEmpty {
            throw MusyXOpsError.bankFailures(failures, total: banks.count, .init())
        }
    }

    /// What `<song>.song.json` says about a song beside its MIDI file.
    struct MusyXSongSummary: Codable {
        struct Track: Codable {
            let index: Int
            let channel: Int
            let notes: Int
            let programs: [Int]
            let loops: Bool
        }
        let name: String
        let bpm: Double
        let tempoChanges: Int
        let tracks: [Track]
    }

    /// Every MusyX song under `songsFolder` (the FSYS unpack names them
    /// `<name>_song.samp`) to a Standard MIDI File plus a summary.
    static func dumpMusyXSongs(
        songsFolder: Folder,
        outputFolder: Folder,
        overwrite: Bool,
        fileSystem: FileSystemTree,
        logger: Logger?
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try dumpBatch(
            in: songsFolder,
            matching: { $0.fileName.hasSuffix("_song.samp") },
            label: "MusyX song",
            outputFolder: outputFolder,
            overwrite: overwrite,
            fileSystem: fileSystem,
            logger: logger,
            artifacts: { file, stem in
                guard let bytes = fileSystem.readFile(at: file)?.allData?.rawBytes else {
                    throw FSTErrors.fileNotFound(file, .init())
                }
                let name = String(stem.dropLast("_song".count))
                let song = try MusyXSong(bytes: bytes)
                let summary = MusyXSongSummary(
                    name: name, bpm: song.bpm, tempoChanges: song.tempo.count,
                    tracks: song.tracks.map { track in
                        MusyXSongSummary.Track(
                            index: track.index, channel: track.channel, notes: track.noteCount,
                            programs: Array(Set(track.events.compactMap {
                                if case let .program(_, program) = $0 { return program }; return nil
                            })).sorted(),
                            loops: track.events.contains { if case .loop = $0 { return true }; return false }
                        )
                    }
                )
                return [
                    FileData(fileName: name + ".mid", data: GoDData(byteStream: song.midi(name: name), byteOrder: .big)),
                    FileData(fileName: name + ".song.json",
                             data: GoDData(byteStream: [UInt8](try encoder.encode(summary)), byteOrder: .big)),
                ]
            }
        )
    }

    private static func record(_ sample: MusyXSampleDirectory.Sample, wav: String?, skipped: String?) -> MusyXSampleRecord {
        MusyXSampleRecord(id: sample.id, wav: wav, sampleRate: sample.sampleRate, sampleCount: sample.sampleCount,
                          basePitch: sample.basePitch, loopStart: sample.loopStart, loopLength: sample.loopLength,
                          skipped: skipped)
    }
}

enum MusyXOpsError: Error, CustomStringConvertible {
    case missingSamp(bank: String, expected: File, ErrorTrace)
    case bankFailures([String], total: Int, ErrorTrace)

    var description: String {
        switch self {
        case let .missingSamp(bank, expected, trace):
            return "MusyX bank \(bank) has a .sdir but no \(expected.path)\n\(trace)"
        case let .bankFailures(banks, total, trace):
            return "\(banks.count) of \(total) MusyX bank(s) failed: \(banks.joined(separator: ", "))\n\(trace)"
        }
    }
}
