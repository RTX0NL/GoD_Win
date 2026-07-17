//
//  Canonicalized.swift
//
//  Reader-canonicalisation for fixture generation. We freeze
//  `reader(writer(model))` rather than the hand-built model so a golden's
//  section/chunk boundaries are already in the reader's canonical form —
//  otherwise decode tests would diverge over cosmetic differences.
//

import Foundation
import GoDFoundation

/// One `reader(writer(·))` pass over a `FileFormat` model.
public func readerCanonicalized<F: FileFormat>(_ model: F) throws -> F {
    try F(binaries: model.binaries)
}

/// Iterate `reader(writer(·))` until the serialized binaries stop changing,
/// returning a fixed-point instance. Lossy codecs (DSP-ADPCM, DXT) only
/// stabilize after one or more decode/encode cycles; byte-faithful formats
/// converge on iteration 1. Falls back to the last instance if it hasn't
/// converged within `maxIterations`.
public func canonicalized<F: FileFormat>(_ model: F, maxIterations: Int = 8) throws -> F {
    var current = try F(binaries: model.binaries)
    var previousBytes = try current.binaries.map { $0.data.rawBytes }
    for _ in 0..<maxIterations {
        let next = try F(binaries: current.binaries)
        let nextBytes = try next.binaries.map { $0.data.rawBytes }
        if nextBytes == previousBytes { return next }
        current = next
        previousBytes = nextBytes
    }
    return current
}

/// The frozen files for a canonicalized `FileFormat` model: every binary
/// piece plus every output artifact, destined for `dir`.
public func fixtureFiles<F: FileFormat>(
    for model: F,
    in dir: String
) throws -> [FixtureFile] {
    let canonical = try readerCanonicalized(model)
    var files: [FixtureFile] = []
    for piece in try canonical.binaries {
        files.append(FixtureFile(relativePath: "\(dir)/\(piece.file.name)", bytes: piece.data.rawBytes))
    }
    for artifact in try canonical.outputs {
        files.append(FixtureFile(relativePath: "\(dir)/\(artifact.file.name)", bytes: artifact.data.rawBytes))
    }
    return files
}
