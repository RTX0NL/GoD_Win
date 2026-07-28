//
//  OperationTestSupport.swift
//  GODOpsTests
//
//  Shared helpers for exercising GODOps operations against an InMemoryFST:
//  installing serialized engine folders, seeding JSON/binary inputs, and
//  synthesizing a minimal valid GameCube ISO.
//
//  InMemoryFST has no current-directory concept, so every path used in these
//  tests must be absolute.
//

import Foundation
import GoDFoundation
import GoDEngine
import Dolphin
import Structs
@testable import GODOps

/// Serialize an engine into `parent/<engine.name>/` and return that folder,
/// which is what operation configs expect for their engine-folder fields.
@discardableResult
func installEngine<E: Engine>(_ engine: E, under parent: Folder, in fst: FileSystemTree) -> Folder {
    _ = try? engine.write(to: fst, in: parent, overwrite: true)
    return parent.folder(engine.name)
}

/// Write a UTF-8 string (typically JSON) into the tree.
func writeText(_ text: String, at file: File, in fst: FileSystemTree) {
    try? fst.writeFile(GoDData(data: Data(text.utf8), byteOrder: .big), at: file, overwrite: true)
}

/// Build a minimal valid GameCube ISO: boot/bi2/apploader/DOL headers, an FST
/// with a single "test.bin" user file (64 bytes 0...63) at 0x8000.
/// Mirrors the fixture builder in GamecubeISOTests.
func buildMinimalGamecubeISO(dolphinEngine: DolphinEngine) throws -> GoDData {
    let isoData = GoDData(length: 0x100000, byteOrder: .big)

    let boot = StructData(definition: dolphinEngine.bootDataStruct, byteOrder: .big)
    isoData.write("TEST".data(format: .utf8), atAddress: 0)

    let bi2 = StructData(definition: dolphinEngine.bi2Struct, byteOrder: .big)
    isoData.write(struct: bi2, atAddress: 0x440)

    let apploader = StructData(definition: dolphinEngine.apploaderHeaderStruct, byteOrder: .big)
    apploader.date = "2024/01/01".data(format: .ascii_big)
    apploader.entry_point = UInt32(0x81200000)
    apploader.size = 64
    apploader.trailer_size = 0
    isoData.write(struct: apploader, atAddress: 0x2440)

    let dolOffset = 0x2500
    let dolStruct = dolphinEngine.dolHeaderStruct
    let dolHeader = StructData(definition: dolStruct, byteOrder: .big)
    dolHeader.entry_point = UInt32(0x80003100)
    dolHeader.BSS_size = UInt32(0)
    dolHeader.BSS_RAM_address = UInt32(0)
    dolHeader.text_sections_offsets = [UInt32](repeating: 0, count: 7)
    dolHeader.text_sections_sizes = [UInt32](repeating: 0, count: 7)
    dolHeader.text_sections_RAM_addresses = [UInt32](repeating: 0, count: 7)
    dolHeader.data_sections_offsets = [UInt32](repeating: 0, count: 11)
    dolHeader.data_sections_sizes = [UInt32](repeating: 0, count: 11)
    dolHeader.data_sections_RAM_addresses = [UInt32](repeating: 0, count: 11)
    isoData.write(struct: dolHeader, atAddress: dolOffset)

    let fstOffset = dolOffset + dolStruct.length

    let rootEntry = StructData(definition: dolphinEngine.fstRootEntryStruct, byteOrder: .big)
    rootEntry.is_directory = true
    rootEntry.entry_count = 2

    let fileEntry = StructData(definition: dolphinEngine.fstFileEntryStruct, byteOrder: .big)
    fileEntry.is_directory = false
    fileEntry.name_offset = 0
    fileEntry.file_offset = UInt32(0x8000)
    fileEntry.file_size = UInt32(64)

    isoData.write(struct: rootEntry, atAddress: fstOffset)
    isoData.write(struct: fileEntry, atAddress: fstOffset + 12)

    let stringTableOffset = fstOffset + 24
    isoData.write("test.bin".data(format: .utf8), atAddress: stringTableOffset)
    isoData.write(UInt8(0), atAddress: stringTableOffset + 8)

    let fstSize = 24 + 9

    let userOffset = 0x8000
    let testFileData = GoDData(byteStream: (0..<64).map { UInt8($0) }, byteOrder: .big)
    isoData.write(testFileData, atAddress: userOffset)

    boot.main_executable_offset = dolOffset
    boot.fst_offset = fstOffset
    boot.fst_size = fstSize
    boot.max_fst_size = fstSize
    boot.user_data_offset = userOffset
    boot.user_data_length = 64
    isoData.write(struct: boot, atAddress: 0)

    return isoData
}
