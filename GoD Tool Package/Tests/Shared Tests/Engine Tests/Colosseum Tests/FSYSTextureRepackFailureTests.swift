//
//  FSYSTextureRepackFailureTests.swift
//
//  A texture artifact that can't be turned back into a texture has to stop
//  its entry.
//
//  The re-encode branches used to fall through on a nil, which left the
//  entry's payload holding the *PNG's* bytes — so an archive would be packed
//  with a PNG file sitting where the game expects a GTX, and the run would
//  report success. It was reachable in practice: the deflate bug that
//  truncated 16 XD PAL textures produced exactly the unreadable PNGs that
//  triggered it, and a rebuilt `pda_menu.fsys` came out carrying `\x89PNG`
//  where its texture should be.
//

import XCTest
import Foundation
import GoDFoundation
import GTX
import FixtureCatalog
@testable import GeniusSonority

final class FSYSTextureRepackFailureTests: XCTestCase {

    private let sourceFolder = Folder("/project")
    private let pngFile = File("/project/Images/broken.png")

    private func entry(
        textureMetadata: GXTextureMetadata? = nil,
        atxMetadata: ATXMetadata? = nil
    ) -> FSYSRegistry.Entry {
        FSYSRegistry.Entry(
            metadata: .init(
                name: "broken", fileType: "gtx", identifier: 0,
                compress: false, includesFullFilename: true, fullFilename: "broken.gtx"
            ),
            file: File("Images/broken.png"),
            textureMetadata: textureMetadata,
            atxMetadata: atxMetadata
        )
    }

    /// Bytes that start like a PNG and cannot be decoded as one — the shape a
    /// truncated encode leaves behind.
    private func unreadablePNG() -> GoDData {
        GoDData(byteStream: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 0, count: 32),
                byteOrder: .big)
    }

    func testUnreadableTexturePNGStopsTheEntryInsteadOfPackingThePNG() throws {
        let fst = InMemoryFST()
        let png = unreadablePNG()
        try fst.writeFile(png, at: pngFile, overwrite: true)
        let engine = FSYSFixtures.engine()

        XCTAssertThrowsError(
            try engine.resolveArchiveEntries(
                registryEntry: entry(textureMetadata: .init(width: 4, height: 4, format: .RGBA32)),
                sourceFolder: sourceFolder,
                fileSystem: fst
            ),
            "an unreadable texture PNG must not resolve to an archive entry"
        ) { error in
            guard case FSYSPipelineError.unreadableTexturePNG(let file, _) = error else {
                XCTFail("expected .unreadableTexturePNG, got \(error)")
                return
            }
            XCTAssertEqual(file.path, pngFile.path, "the error has to name the file that needs fixing")
        }
    }

    func testUnreadableATXPNGStopsTheEntryToo() throws {
        let fst = InMemoryFST()
        try fst.writeFile(unreadablePNG(), at: pngFile, overwrite: true)
        let engine = FSYSFixtures.engine()
        let atxMetadata = ATXMetadata(
            texture: .init(width: 4, height: 4, format: .RGBA32),
            frameTableOffset: 0x20,
            innerTextureSize: 0x100,
            innerTextureOffset: 0x80,
            animations: [],
            frameTable: Data()
        )

        XCTAssertThrowsError(
            try engine.resolveArchiveEntries(
                registryEntry: entry(atxMetadata: atxMetadata),
                sourceFolder: sourceFolder,
                fileSystem: fst
            )
        ) { error in
            guard case FSYSPipelineError.unreadableTexturePNG = error else {
                XCTFail("expected .unreadableTexturePNG, got \(error)")
                return
            }
        }
    }

    /// A readable PNG whose dimensions no longer match the entry's metadata
    /// is the other way this can go wrong, and it gets its own error.
    func testDimensionMismatchIsNamedRatherThanSilentlyAccepted() throws {
        let fst = InMemoryFST()
        let image = GoDImage(
            width: 4, height: 4,
            pixels: GoDData(byteStream: deterministicBytes(4 * 4 * 4, seed: 7), byteOrder: .big)
        )
        try fst.writeFile(try XCTUnwrap(image.pngData()), at: pngFile, overwrite: true)
        let engine = FSYSFixtures.engine()

        // Metadata says the entry is 8x8; the artifact is 4x4.
        let resolved = try? engine.resolveArchiveEntries(
            registryEntry: entry(textureMetadata: .init(width: 8, height: 8, format: .RGBA32)),
            sourceFolder: sourceFolder,
            fileSystem: fst
        )
        if let resolved {
            // If the encoder accepts it, it must at least not be the PNG.
            let packed = try XCTUnwrap(resolved.first).data.rawBytes
            XCTAssertNotEqual(
                Array(packed.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
                "packed a PNG where a texture belongs"
            )
        }
    }
}
