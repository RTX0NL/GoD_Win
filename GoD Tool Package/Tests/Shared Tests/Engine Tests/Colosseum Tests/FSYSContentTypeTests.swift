//
//  FSYSContentTypeTests.swift
//  ColosseumTests
//
//  GeniusSonorityEngine.projectFileType: the project extension follows the
//  archive's type, except where the bytes plainly contradict it (PBR US:
//  untyped MESG string tables, and a 3D font typed `fnt`).
//

import XCTest
import GoDFoundation
@testable import GeniusSonority

final class FSYSContentTypeTests: XCTestCase {

    private func data(_ bytes: [UInt8]) -> GoDData {
        GoDData(byteStream: bytes + [UInt8](repeating: 0, count: 12), byteOrder: .big)
    }

    func testAnUntypedMESGTableBecomesMsg() {
        XCTAssertEqual(GeniusSonorityEngine.projectFileType(archiveType: nil, data: data(Array("MESG".utf8))), "msg")
    }

    func testAFontWithTheF3MagicBecomesF3d() {
        XCTAssertEqual(GeniusSonorityEngine.projectFileType(archiveType: "fnt", data: data(Array("F3".utf8) + [1, 0xE6])), "f3d")
    }

    func testTheArchiveTypeWinsWhenNothingContradictsIt() {
        XCTAssertEqual(GeniusSonorityEngine.projectFileType(archiveType: "fnt", data: data(Array("FONT".utf8))), "fnt")
        XCTAssertEqual(GeniusSonorityEngine.projectFileType(archiveType: "gtx", data: data(Array("MESG".utf8))), "gtx")
        XCTAssertEqual(GeniusSonorityEngine.projectFileType(archiveType: nil, data: data([1, 2, 3, 4])), "bin")
    }

    func testAnEmptyEntryKeepsItsType() {
        let empty = GoDData(byteStream: [UInt8](), byteOrder: .big)
        XCTAssertEqual(GeniusSonorityEngine.projectFileType(archiveType: nil, data: empty), "bin")
    }
}
