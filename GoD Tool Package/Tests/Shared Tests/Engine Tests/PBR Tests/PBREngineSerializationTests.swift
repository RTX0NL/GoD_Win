//
//  PBREngineSerializationTests.swift
//  PBRTests
//
//  `ProjectSetup` writes the PBR engine into every PBR project as JSON, and
//  every later run reloads it from there — so a definition that can't
//  survive that round trip would work in-process and break in a project.
//  These tests write the engine to an in-memory tree, read it back, and
//  check the reloaded definitions still resolve to the same layouts.
//

import XCTest
import GoDFoundation
import GoDEngine
import Structs
@testable import PBR

final class PBREngineSerializationTests: XCTestCase {

    private let root = Folder("/Engines")

    private func reloaded() throws -> PBREngine {
        let fst = InMemoryFST()
        try PBREngine.defaults().write(to: fst, in: root, overwrite: true)
        return try PBREngine(from: root.folder(PBREngine.defaultName), in: fst)
    }

    /// Every struct and enum must come back with the same name set and the
    /// same resolved byte length. Arrays of sub-structs and the `padding`
    /// runs are the fragile parts — both are encoded as type strings and
    /// re-parsed on load.
    func testEngineSurvivesAWriteAndReload() throws {
        let original = try PBREngine.defaults()
        let loaded = try reloaded()

        XCTAssertEqual(
            Set(loaded.structs.entries.map(\.name)),
            Set(original.structs.entries.map(\.name))
        )
        XCTAssertEqual(
            Set(loaded.enums.entries.map(\.name)),
            Set(original.enums.entries.map(\.name))
        )

        for map in original.structs.entries {
            let before = try original.getStruct(map.name).length
            let after = try loaded.getStruct(map.name).length
            XCTAssertEqual(after, before, "\(map.name) changed length across a reload")
        }
    }

    /// The model row is the one that exercises both sub-struct references
    /// and a fixed-size byte array in the same definition, so check its
    /// field offsets survive rather than just its total length.
    func testModelRowFieldOffsetsSurviveAReload() throws {
        let definition = try reloaded().getStruct("PBRPokemonModel")
        XCTAssertEqual(definition.offset(for: "parameters"), 0x00)
        XCTAssertEqual(definition.offset(for: "fsys_id"), 0x04)
        XCTAssertEqual(definition.offset(for: "model_file_id"), 0x08)
        XCTAssertEqual(definition.offset(for: "shiny_model_file_id"), 0x0C)
        XCTAssertEqual(definition.offset(for: "run_speed"), 0x10)
        XCTAssertEqual(definition.offset(for: "species"), 0x14)
        XCTAssertEqual(definition.offset(for: "form_index"), 0x18)
        XCTAssertEqual(definition.offset(for: "bones"), 0x19)
        XCTAssertEqual(definition.offset(for: "animations"), 0x32)

        // The camera targets are the slots a replacement model most needs
        // correct, so pin them through the sub-struct keypath too.
        XCTAssertEqual(definition.offset(for: "bones.camera_target_bust"), 0x19 + 0x15)
        XCTAssertEqual(definition.offset(for: "bones.camera_target_all"), 0x19 + 0x17)
        XCTAssertEqual(definition.offset(for: "animations.wake_up"), 0x32 + 0x15)
    }

    /// The item struct has five separate `padding` runs, which all serialize
    /// under the same reserved property name. They must reload as padding
    /// rather than collide as duplicate addressable properties.
    func testRepeatedPaddingRunsReloadWithoutColliding() throws {
        let definition = try reloaded().getStruct("PBRItem")
        XCTAssertEqual(definition.length, 0x28)
        XCTAssertTrue(definition.duplicatePropertyNames.isEmpty,
                      "padding runs collided: \(definition.duplicatePropertyNames)")
        XCTAssertEqual(definition.offset(for: "healing_parameter"), 0x21)
        XCTAssertEqual(definition.offset(for: "happiness_effects"), 0x23)
    }
}
