//
//  GCISaveManifest.swift
//
//  What `gciDump` writes beside the save's region files, and what
//  `gciBuild` reads back.
//
//  The manifest carries no bytes. It holds the directory entry, the
//  region list the body was split on, and a description of the card
//  metadata — which images exist, in which formats, at what animation
//  speed, and what the two comment strings say. Every byte lives in a
//  file the manifest points at.
//

import Foundation
import GoDFoundation
import GameCube

extension GCIOps {

    struct SaveManifest: Codable {

        /// Where the region list came from. A derived layout finds the
        /// banner, icon and comments but leaves the game's own data in
        /// one undivided lump, because nothing in the save says where its
        /// internal boundaries are.
        enum LayoutSource: String, Codable {
            case declared
            case derived
        }

        struct Frame: Codable {
            /// Which of the eight 2-bit field positions this frame uses.
            /// Live frames need not be contiguous.
            var slot: Int
            var format: CardImageBlock.IconFormat
            var speed: CardImageBlock.AnimationSpeed
            /// `speed` in video frames, for readability only.
            var videoFrames: Int
            var file: String
        }

        struct Images: Codable {
            var bannerFormat: CardImageBlock.BannerFormat
            var animationOrder: CardImageBlock.AnimationOrder
            var offset: Int
            var length: Int
            var bannerFile: String?
            var frames: [Frame]
            /// Set when the two references disagree about how many icon
            /// frames this save has. Never true for a real save.
            var frameWalkIsAmbiguous: Bool?
        }

        struct Comments: Codable {
            var encoding: CardComments.TextEncoding
            var offset: Int
            var title: String
            var subtitle: String
        }

        /// Everything the metadata region is made of.
        ///
        /// No bytes, and no file holding the region itself: the rebuild
        /// fills the region with its declared fill byte and writes the
        /// images, the comments and any checksum over it. Nothing is
        /// carried across from the original save, so a rebuilt save is
        /// derived end to end rather than patched.
        struct Card: Codable {
            var images: Images?
            var comments: Comments?
        }

        /// A readable view of the directory entry. Informational only —
        /// it is rewritten from `header` on every dump and ignored on
        /// build, because `header` is what the rebuilt entry is made
        /// from and two editable copies of one fact would drift.
        struct Summary: Codable {
            var gamecode: String
            var makercode: String
            var filename: String
            var modified: String
            var blockCount: Int
            var totalBytes: Int
            var permissions: [String]

            init(header: GCIFile.Header) {
                gamecode = header.gamecode
                makercode = header.makercode
                filename = header.filename
                blockCount = Int(header.blockCount)
                totalBytes = GCIFile.headerSize + Int(header.blockCount) * GCIFile.blockSize

                // Seconds since 2000-01-01, the console's own epoch.
                let epoch = Date(timeIntervalSince1970: 946_684_800)
                let formatter = ISO8601DateFormatter()
                formatter.timeZone = TimeZone(identifier: "UTC")
                modified = formatter.string(
                    from: epoch.addingTimeInterval(TimeInterval(header.modtime))
                )

                var flags: [String] = []
                if header.permissions & 0x04 != 0 { flags.append("public") }
                if header.permissions & 0x08 != 0 { flags.append("noCopy") }
                if header.permissions & 0x10 != 0 { flags.append("noMove") }
                permissions = flags
            }
        }

        var header: GCIFile.Header
        var summary: Summary?
        var layoutSource: LayoutSource
        var regions: [CardSaveLayout.Region]
        var card: Card?
        var integrity: [CardIntegrityRule]

        init(
            header: GCIFile.Header,
            layoutSource: LayoutSource,
            regions: [CardSaveLayout.Region],
            card: Card?,
            integrity: [CardIntegrityRule]
        ) {
            self.header = header
            self.summary = Summary(header: header)
            self.layoutSource = layoutSource
            self.regions = regions
            self.card = card
            self.integrity = integrity
        }

        func layout(bodyLength: Int) throws -> CardSaveLayout {
            try CardSaveLayout(regions: regions, bodyLength: bodyLength)
        }
    }
}
