//
//  Fixtures.swift
//
//  Loads checked-in golden fixtures for encode/decode tests.
//
//  Fixtures live in a `Fixtures/` folder next to the test file that uses
//  them (so a format's sample data sits as close as possible to that
//  format's tests). They are resolved relative to the *caller's* source
//  path via `#filePath`, exactly like the existing absolute-path samples
//  — but checked into the repo so the tests always run, never `XCTSkip`.
//
//  Because we read straight from the source tree, the `Fixtures/` folders
//  should be added to each test target's `exclude:` list so SwiftPM does
//  not treat them as unhandled resources.
//

import Foundation
import GoDFoundation

public enum Fixtures {

    /// Absolute URL of `name` inside the `Fixtures/` folder beside the
    /// calling source file. `file` defaults to the call site, so a test in
    /// `.../Colosseum Tests/MSGGoldenTests.swift` resolves against
    /// `.../Colosseum Tests/Fixtures/`.
    public static func url(_ name: String, file: StaticString = #filePath) -> URL {
        let caller = URL(fileURLWithPath: "\(file)")
        return caller
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }

    /// Raw bytes of a fixture as big-endian `GoDData` (the codebase's
    /// near-universal default byte order).
    public static func data(
        _ name: String,
        byteOrder: ByteOrder = .big,
        file: StaticString = #filePath
    ) throws -> GoDData {
        let raw = try Data(contentsOf: url(name, file: file))
        return GoDData(data: raw, byteOrder: byteOrder)
    }

    /// A fixture wrapped as `FileData`, keyed by `name` so a `FileFormat`
    /// can recover its name stem the same way it would from a real file.
    public static func fileData(
        _ name: String,
        byteOrder: ByteOrder = .big,
        file: StaticString = #filePath
    ) throws -> FileData {
        FileData(file: File(name), data: try data(name, byteOrder: byteOrder, file: file))
    }

    /// Load a whole artifact bundle (a `.json` manifest plus companions) as
    /// an ordered `[FileData]`, keyed by the given names. The first name is
    /// conventionally the JSON manifest.
    public static func artifacts(
        _ names: [String],
        file: StaticString = #filePath
    ) throws -> [FileData] {
        try names.map { try fileData($0, file: file) }
    }
}
