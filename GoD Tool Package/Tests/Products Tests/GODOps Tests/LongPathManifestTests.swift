//
//  LongPathManifestTests.swift
//  GODOpsTests
//
//  GODDESS.exe only accepts paths past MAX_PATH because Package.swift links
//  Windows/GODDESS.exe.manifest into it. Dropping those linker flags would
//  not break the build; dumps would just start failing on long paths. This
//  checks the built exe still carries the manifest.
//

import XCTest
import Foundation

final class LongPathManifestTests: XCTestCase {

    func testGoddessExeEmbedsLongPathAwareManifest() throws {
        #if os(Windows)
        // The test runner is built into the same products folder as GODDESS.exe.
        let runner = try XCTUnwrap(Bundle.main.executableURL)
        let exe = runner.deletingLastPathComponent().appendingPathComponent("GODDESS.exe")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: exe.path), "GODDESS.exe not built at \(exe.path)")

        let bytes = try Data(contentsOf: exe)
        // The manifest is stored as plain UTF-8 XML in the RT_MANIFEST resource.
        let marker = Data("longPathAware>true</".utf8)
        XCTAssertNotNil(bytes.range(of: marker), "\(exe.path) has no longPathAware manifest; check the GODDESS linker settings in Package.swift")
        #else
        throw XCTSkip("Windows-only: the manifest is a Windows PE resource")
        #endif
    }
}
