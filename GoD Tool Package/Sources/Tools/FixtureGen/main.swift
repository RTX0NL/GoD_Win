//
//  main.swift — FixtureGen
//
//  Standalone golden-fixture generator for the test suite. The fixtures'
//  content is defined by the `FixtureCatalog` library; this executable
//  materializes them into the test targets' `Fixtures/` folders.
//
//      swift run FixtureGen           # (re)write fixtures that changed
//      swift run FixtureGen --check   # verify committed fixtures match the
//                                     # catalog; exit 1 on drift (CI guard)
//
//  Hand-authored goldens (e.g. msg_minimal.*) are not in the catalog and
//  are never touched.
//

import Foundation
import FixtureCatalog

// Package root: this file lives at Sources/Tools/FixtureGen/main.swift.
let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // FixtureGen/
    .deletingLastPathComponent()   // Tools/
    .deletingLastPathComponent()   // Sources/
    .deletingLastPathComponent()   // package root

let checkOnly = CommandLine.arguments.contains("--check")

let fixtures: [FixtureFile]
do {
    fixtures = try FixtureCatalog.allFixtures()
} catch {
    print("error: failed to build fixture catalog: \(error)")
    exit(2)
}

var written = 0, unchanged = 0
var drifted: [String] = []

for fixture in fixtures {
    let url = packageRoot.appendingPathComponent(fixture.relativePath)
    let existing = (try? Data(contentsOf: url)).map { [UInt8]($0) }

    if existing == fixture.bytes {
        unchanged += 1
        continue
    }

    if checkOnly {
        drifted.append(fixture.relativePath + (existing == nil ? " (missing)" : " (differs)"))
        continue
    }

    do {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(fixture.bytes).write(to: url)
        written += 1
        print("wrote   \(fixture.relativePath) (\(fixture.bytes.count) bytes)")
    } catch {
        print("error: failed to write \(fixture.relativePath): \(error)")
        exit(2)
    }
}

if checkOnly {
    if drifted.isEmpty {
        print("all \(unchanged) fixtures match the catalog")
    } else {
        print("\(drifted.count) fixture(s) out of date — run `swift run FixtureGen`:")
        for path in drifted { print("  \(path)") }
        exit(1)
    }
} else {
    print("\(written) written, \(unchanged) unchanged")
}
