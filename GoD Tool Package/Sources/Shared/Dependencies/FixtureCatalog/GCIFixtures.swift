//
//  GCIFixtures.swift
//
//  A single-block GCI memory-card save with a deterministic body.
//

import Foundation
import GoDFoundation
import GameCube

public enum GCIFixtures {
    public static let name = "gci_sample"

    /// `body` length must equal `blockCount * 0x2000` or encode throws.
    public static func model() -> GCIFile {
        let header = GCIFile.Header(
            gamecode: "GXXE",
            makercode: "01",
            bannerAndIconFlags: 0x02,
            filename: "pokemon_save_data",
            modtime: 0x1234_5678,
            imageOffset: 0x40,
            iconFmt: 0x0002,
            animSpeed: 0x0003,
            permissions: 0x04,
            copyCounter: 0x00,
            firstBlock: 0x0005,
            blockCount: 1,
            commentsAddr: 0x0000_0050
        )
        let body = GoDData(byteStream: deterministicBytes(0x2000, seed: 0x5A5A_1234),
                           byteOrder: .big)
        return GCIFile(name: name, header: header, body: body)
    }

    public static func files() throws -> [FixtureFile] {
        try fixtureFiles(for: model(), in: FixtureDir.gamecube)
    }
}
