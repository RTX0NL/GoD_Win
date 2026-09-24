import XCTest
import Foundation
import GoDFoundation
import GeniusSonority
import GTX
import TestSupport

/// A format embedded in a bigger buffer — a DOL data section, an archive
/// member — has to say where it ends, because the container's own rule
/// ("a chunk runs to the next symbol") gets it wrong whenever a symbol
/// sits inside the file. Both cases below are real: XD's health-warning
/// texture names its palette, and XD JP has a symbol 776 bytes before the
/// end of one of its embedded string tables.
final class EmbeddedFormatLengthTests: XCTestCase {

    // MARK: - GTX

    /// 8x8 C4: 0x80 header, 32 bytes of indices, 32 bytes of palette.
    private func makeIndexedTexture(trailing: Int) -> GoDData {
        var bytes = [UInt8](repeating: 0, count: 0x80)
        bytes[0] = 0; bytes[1] = 8            // width
        bytes[2] = 0; bytes[3] = 8            // height
        bytes[4] = 4                          // bits per pixel
        bytes[5] = 1
        bytes[0x0B] = 0x00                    // C4
        bytes[0x0F] = 0x02                    // RGB5A3 palette
        bytes[0x2B] = 0x80                    // texture at +0x80
        bytes[0x48] = 0; bytes[0x49] = 0; bytes[0x4A] = 0x00; bytes[0x4B] = 0xA0
        bytes += [UInt8](repeating: 0x11, count: 32)   // 8x8 at 4bpp
        bytes += [UInt8](repeating: 0x22, count: 32)   // 16-entry palette
        bytes += [UInt8](repeating: 0xEE, count: trailing)
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    func testIndexedTextureMeasuresThroughItsPalette() {
        let measured = GXTextureDecoder().measuredLength(data: makeIndexedTexture(trailing: 0))
        XCTAssertEqual(measured, 0xA0 + 32, "an indexed texture ends where its palette does")
    }

    func testIndexedTextureMeasuresTheSameInsideALargerBuffer() {
        // This is the case that matters: the caller hands over everything
        // from the texture to the end of the section, and the answer must
        // not depend on how much of it there is.
        let measured = GXTextureDecoder().measuredLength(data: makeIndexedTexture(trailing: 4096))
        XCTAssertEqual(measured, 0xA0 + 32)
    }

    func testNonIndexedTextureMeasuresThroughItsPixels() {
        var bytes = [UInt8](repeating: 0, count: 0x80)
        bytes[1] = 8; bytes[3] = 8
        bytes[4] = 4
        bytes[0x0B] = 0x40                    // I4
        bytes[0x2B] = 0x80
        bytes += [UInt8](repeating: 0x33, count: 32)
        bytes += [UInt8](repeating: 0xEE, count: 500)
        let measured = GXTextureDecoder().measuredLength(
            data: GoDData(byteStream: bytes, byteOrder: .big)
        )
        XCTAssertEqual(measured, 0x80 + 32)
    }

    func testAGarbageHeaderMeasuresNothing() {
        let junk = GoDData(byteStream: [UInt8](repeating: 0xAB, count: 0x200), byteOrder: .big)
        XCTAssertNil(
            GXTextureDecoder().measuredLength(data: junk),
            "an unparseable header leaves the container's own bound in place"
        )
    }

    func testTheFormatAnswersThroughTheRegistry() {
        var registry = FileFormatRegistry()
        registry.register("gtx", GTXFile.self)
        XCTAssertEqual(
            registry.measuredLength(of: makeIndexedTexture(trailing: 1024), extension: "gtx"),
            0xA0 + 32
        )
    }

    func testAnUnregisteredExtensionMeasuresNothing() {
        let registry = FileFormatRegistry()
        XCTAssertNil(registry.measuredLength(of: makeIndexedTexture(trailing: 0), extension: "gtx"))
    }

    // MARK: - MSG

    /// Two entries, second string last in the pool, then filler.
    private func makeMessageTable(trailing: Int) -> GoDData {
        var bytes: [UInt8] = []
        bytes += [0x00, 0x00, 0x00, 0x01]              // reserved prefix
        bytes += [0x00, 0x02]                          // 2 entries
        bytes += [0x55, 0x53]                          // "US"
        bytes += [UInt8](repeating: 0, count: 8)
        let tableEnd = 0x10 + 2 * 8                    // 0x20
        bytes += [0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, UInt8(tableEnd)]
        bytes += [0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, UInt8(tableEnd + 6)]
        bytes += [0x00, 0x41, 0x00, 0x42, 0x00, 0x00]  // "AB\0" at 0x20
        bytes += [0x00, 0x43, 0x00, 0x00]              // "C\0"  at 0x26
        bytes += [UInt8](repeating: 0xEE, count: trailing)
        return GoDData(byteStream: bytes, byteOrder: .big)
    }

    func testMessageTableMeasuresToTheEndOfItsLastString() {
        XCTAssertEqual(MSGFile.measuredLength(of: makeMessageTable(trailing: 0)), 0x2A)
    }

    func testMessageTableMeasuresTheSameInsideALargerBuffer() {
        XCTAssertEqual(MSGFile.measuredLength(of: makeMessageTable(trailing: 2048)), 0x2A)
    }

    func testABattleRevolutionTableMeasuresNothing() {
        var bytes: [UInt8] = Array("MESG".utf8)
        bytes += [UInt8](repeating: 0, count: 0x40)
        XCTAssertNil(
            MSGFile.measuredLength(of: GoDData(byteStream: bytes, byteOrder: .big)),
            "MESG is a different format that shares the extension"
        )
    }

    func testAnEntryTablePastTheBufferMeasuresNothing() {
        var bytes: [UInt8] = [0x00, 0x00, 0x00, 0x00]
        bytes += [0xFF, 0xFF]                          // 65535 entries
        bytes += [0x55, 0x53]
        bytes += [UInt8](repeating: 0, count: 8)
        XCTAssertNil(MSGFile.measuredLength(of: GoDData(byteStream: bytes, byteOrder: .big)))
    }
}
