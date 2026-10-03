//
//  RVZRealCorpusTests.swift
//
//  Reads real Dolphin-produced `.rvz` / `.wia` files, which is where this
//  format's awkward cases actually live. The synthetic fixtures cover the
//  container's shapes; only a real image covers the entropy coder's tail
//  behaviour — the bug that cost two of one disc's 35,859 groups was a
//  sequence whose extra-bit fields overran the bit reader's window, and
//  nothing smaller ever produced one.
//
//  Skips when there is no corpus rather than passing vacuously.
//  `GODDESS_RVZ_CORPUS` points at a folder to scan (default:
//  `~/Documents/Emulation`), and `GODDESS_RVZ_LIMIT` sets how many groups
//  per image to decode — `all` for every one, which is the full check and
//  takes minutes per disc.
//

import XCTest
import Foundation
import GoDFoundation
@testable import Dolphin

final class RVZRealCorpusTests: XCTestCase {

    private static let defaultGroupSample = 150

    private func corpusImages() throws -> [URL] {
        let root = ProcessInfo.processInfo.environment["GODDESS_RVZ_CORPUS"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Documents/Emulation")
        let rootURL = URL(fileURLWithPath: root)
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw XCTSkip("No WIA/RVZ corpus at \(rootURL.path); set GODDESS_RVZ_CORPUS to point at one.")
        }
        var found: [URL] = []
        if let walker = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil) {
            for case let url as URL in walker {
                let ext = url.pathExtension.lowercased()
                if ext == "rvz" || ext == "wia" { found.append(url) }
            }
        }
        guard !found.isEmpty else {
            throw XCTSkip("No .rvz or .wia files under \(rootURL.path).")
        }
        return found.sorted { $0.path < $1.path }
    }

    private var groupLimit: Int? {
        guard let raw = ProcessInfo.processInfo.environment["GODDESS_RVZ_LIMIT"] else {
            return Self.defaultGroupSample
        }
        if raw.lowercased() == "all" { return nil }
        return Int(raw) ?? Self.defaultGroupSample
    }

    /// Parsing validates `file_head_hash`, `disc_hash` and `part_hash`, so
    /// getting this far already says the container was read correctly.
    func testParsesEveryImageInTheCorpus() throws {
        for url in try corpusImages() {
            let image = try RVZImage(binary: try GoDStreamedData(file: File(url.path)))
            XCTAssertGreaterThan(image.groups.count, 0, url.lastPathComponent)
            XCTAssertGreaterThan(image.header.isoFileSize, 0, url.lastPathComponent)
            XCTAssertEqual(
                image.chunkSize % RVZImage.clusterSize, 0,
                "\(url.lastPathComponent): chunk size is not a whole number of clusters"
            )
            if image.disc.discType == .wii {
                XCTAssertFalse(image.partitions.isEmpty, "\(url.lastPathComponent): a Wii image with no partitions")
            }
        }
    }

    /// Every group must decode to exactly the size its region needs.
    ///
    /// A group that decodes to the wrong length is the failure mode that
    /// matters: it is not a crash, it is every later byte of the disc landing
    /// somewhere else.
    func testEveryGroupDecodesToItsDeclaredSize() throws {
        let limit = groupLimit
        for url in try corpusImages() {
            let image = try RVZImage(binary: try GoDStreamedData(file: File(url.path)))
            var checked = 0
            var failures: [String] = []

            func check(index: Int, dataSize: Int, exceptionLists: Int, dataOffset: Int) {
                guard limit == nil || checked < limit! else { return }
                checked += 1
                do {
                    let contents = try image.readGroup(
                        index: index,
                        dataSize: dataSize,
                        exceptionListCount: exceptionLists,
                        dataOffset: dataOffset
                    )
                    if contents.data.count != dataSize {
                        failures.append("group \(index): \(contents.data.count) bytes, wanted \(dataSize)")
                    }
                } catch {
                    failures.append("group \(index): \(error)")
                }
            }

            // Sample across the whole image rather than the first N groups —
            // the awkward ones are wherever the disc's densest data is.
            let stride = limit.map { max(1, image.groups.count / max(1, $0)) } ?? 1

            for entry in image.rawData {
                let skipped = Int(entry.discOffset) % RVZImage.clusterSize
                let size = Int(entry.size) + skipped
                for i in Swift.stride(from: 0, to: Int(entry.groupCount), by: stride) {
                    let offsetInEntry = i * image.chunkSize
                    guard offsetInEntry < size else { break }
                    check(
                        index: Int(entry.firstGroupIndex) + i,
                        dataSize: min(image.chunkSize, size - offsetInEntry),
                        exceptionLists: 0,
                        dataOffset: offsetInEntry
                    )
                }
            }
            for partition in image.partitions {
                for segment in [partition.managementSegment, partition.dataSegment] {
                    guard segment.sectorCount > 0 else { continue }
                    let segmentSize = Int(segment.sectorCount) * RVZImage.userDataPerCluster
                    for i in Swift.stride(from: 0, to: Int(segment.groupCount), by: stride) {
                        let offsetInSegment = i * image.chunkDataSize
                        guard offsetInSegment < segmentSize else { break }
                        check(
                            index: Int(segment.firstGroupIndex) + i,
                            dataSize: min(image.chunkDataSize, segmentSize - offsetInSegment),
                            exceptionLists: image.exceptionListsPerGroup,
                            dataOffset: offsetInSegment
                        )
                    }
                }
            }

            XCTAssertGreaterThan(checked, 0, "\(url.lastPathComponent): nothing was checked")
            XCTAssertTrue(
                failures.isEmpty,
                "\(url.lastPathComponent): \(failures.count) of \(checked) groups failed\n"
                    + failures.prefix(5).joined(separator: "\n")
            )
        }
    }

    /// Cross-checks the RVZ junk generator against `JunkStream`, which
    /// reproduces the same disc padding from an entirely different seed —
    /// the four-character game ID rather than the 68 bytes an RVZ stores
    /// inline. They are independent implementations that must agree because
    /// they describe the same physical bytes, so a group that reproduces
    /// exactly is evidence neither one drifted.
    ///
    /// GameCube images only: on a Wii disc the junk lives inside the
    /// encrypted partitions, where `JunkStream`'s disc-offset addressing
    /// does not line up with partition data space.
    func testRegeneratedJunkAgreesWithTheNKitGenerator() throws {
        var imagesChecked = 0
        for url in try corpusImages() {
            let image = try RVZImage(binary: try GoDStreamedData(file: File(url.path)))
            guard image.disc.discType == .gamecube else { continue }
            let gameID = Array(image.disc.discHeader.prefix(4))
            let disc = image.disc.discHeader.count > 6 ? image.disc.discHeader[6] : 0
            let junk = JunkStream(gameID: gameID, disc: disc, length: image.header.isoFileSize)

            var fullyJunkGroups = 0
            var partialMatches = 0
            for entry in image.rawData {
                let skipped = Int(entry.discOffset) % RVZImage.clusterSize
                let offset = Int(entry.discOffset) - skipped
                let size = Int(entry.size) + skipped
                let stride = max(1, Int(entry.groupCount) / 60)
                for i in Swift.stride(from: 0, to: Int(entry.groupCount), by: stride) {
                    let offsetInEntry = i * image.chunkSize
                    guard offsetInEntry < size else { break }
                    let length = min(image.chunkSize, size - offsetInEntry)
                    guard let contents = try? image.readGroup(
                        index: Int(entry.firstGroupIndex) + i,
                        dataSize: length,
                        exceptionListCount: 0,
                        dataOffset: offsetInEntry
                    ) else { continue }
                    let expected = junk.read(at: UInt64(offset + offsetInEntry), count: length)
                    if contents.data == expected {
                        fullyJunkGroups += 1
                    } else if zip(contents.data, expected).prefix(0x400).allSatisfy(==) {
                        // Starts as junk and diverges: that is what a
                        // mis-seeded or mis-offset generator cannot produce,
                        // but a real group of junk-then-data can.
                        partialMatches += 1
                    }
                }
            }
            imagesChecked += 1
            XCTAssertGreaterThan(
                fullyJunkGroups, 0,
                "\(url.lastPathComponent): no sampled group reproduced the disc's junk exactly, "
                    + "so the packing PRNG and JunkStream disagree (\(partialMatches) partial matches)"
            )
        }
        try XCTSkipIf(imagesChecked == 0, "No GameCube images in the corpus.")
    }
}
