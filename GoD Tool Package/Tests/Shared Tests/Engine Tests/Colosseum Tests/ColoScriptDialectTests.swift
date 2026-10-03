import XCTest
import GoDFoundation
import ScriptDecompiler
import Structs
@testable import Colosseum

/// Dialect differences between the two script source flavours, and the way
/// back from each.
///
/// The Python flavour spells a builtin's arguments as keyword arguments —
/// `getDNASampleSpecies(sampleID=1)` rather than `getDNASampleSpecies(1)` —
/// because the signatures carry real parameter names and a bare integer says
/// nothing about which slot it fills. The Swift flavour leaves them
/// positional. Both have to compile to the same bytecode.
final class ColoScriptDialectTests: XCTestCase {

    private var builtins: [Int: ScriptFunctionDef] {
        ColosseumEngine.Data.defaultBuiltInFunctions.reduce(into: [:]) { result, pair in
            if let id = Int(pair.key) { result[id] = pair.value }
        }
    }

    private var enums: [String: Enum] {
        Dictionary(
            ColosseumEngine.Enums.allItems.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func swiftSource(body: String) -> String {
        """
        static let __scriptType = 0x100
        static let __compilerMetadata = 0x0

        func function_0() {
            \(body)
        }
        """
    }

    private func compile(_ source: String) throws -> GoDData {
        var parser = ColoScriptTextParser(builtInFunctions: builtins, enums: enums)
        return try ColoScriptCompiler().compile(parser.parse(source))
    }

    /// Compiles a Swift-flavoured body and re-emits it in `syntax`.
    private func reemit(body: String, as syntax: ColoScriptSourceHeader.Syntax) throws -> String {
        let script = try ColoScript(data: try compile(swiftSource(body: body)))
        return ColoScriptSourceEmitter(builtInFunctions: builtins, enums: enums)
            .decompileToText(script: script, fileName: "test.scd", syntax: syntax)
    }

    // MARK: - Emission

    func testPythonLabelsEveryNamedBuiltInArgument() throws {
        let text = try reemit(body: "dialogDisplaySilentMessage(7, true, false)", as: .python)
        XCTAssertTrue(
            text.contains("dialogDisplaySilentMessage(msgID=7, unk1=True, unk2=False)"),
            "emitted:\n\(text)"
        )
    }

    func testPythonLabelsSitAlongsideEnumCases() throws {
        let text = try reemit(body: "soundPlayPokemonCry(25)", as: .python)
        XCTAssertTrue(
            text.contains("soundPlayPokemonCry(pokemon=PokemonSpecies.PIKACHU)"),
            "emitted:\n\(text)"
        )
    }

    /// Swift stays positional, so the two flavours are genuinely different
    /// text — and both still have to rebuild the same bytes.
    func testSwiftLeavesArgumentsPositional() throws {
        let text = try reemit(body: "dialogDisplaySilentMessage(7, true, false)", as: .swift)
        XCTAssertTrue(text.contains("dialogDisplaySilentMessage(7, true, false)"), "emitted:\n\(text)")
        XCTAssertFalse(text.contains("msgID="))
    }

    // MARK: - Reading it back

    func testLabelledAndPositionalCompileToTheSameBytes() throws {
        let labelled = try compile("""
        __SCRIPT_TYPE__ = 0x100
        __COMPILER_METADATA__ = 0x0

        def function_0():
            dialogDisplaySilentMessage(msgID=7, unk1=True, unk2=False)
        """)
        let positional = try compile(swiftSource(body: "dialogDisplaySilentMessage(7, true, false)"))
        XCTAssertEqual(labelled.rawBytes, positional.rawBytes)
    }

    func testPythonRoundTripsThroughItsOwnLabelledForm() throws {
        let original = try compile(swiftSource(body: "characterTalk(0, 100, 12)"))
        let text = ColoScriptSourceEmitter(builtInFunctions: builtins, enums: enums)
            .decompileToText(script: try ColoScript(data: original), fileName: "t.scd", syntax: .python)
        // The labels and the enum cases are both in play here: groupID and
        // resourceID are enum-typed on every named character builtin.
        XCTAssertTrue(text.contains("characterTalk(groupID=GroupID.protagonists, resourceID=ResourceID.wes, msgID=12)"),
                      "emitted:\n\(text)")
        XCTAssertEqual(try compile(text).rawBytes, original.rawBytes)
    }

    /// A label that isn't the signature's name for that position is an error.
    /// Silently accepting it would let labels drift out of step with the
    /// arguments they document, which is the one way this feature could
    /// mislead rather than help.
    func testWrongArgumentLabelThrows() {
        XCTAssertThrowsError(try compile("""
        __SCRIPT_TYPE__ = 0x100
        __COMPILER_METADATA__ = 0x0

        def function_0():
            dialogDisplaySilentMessage(messageID=7, unk1=True, unk2=False)
        """)) { error in
            guard case ColoScriptTextParser.ParseError.argumentLabelMismatch(let expected, let got, _) = error else {
                return XCTFail("expected argumentLabelMismatch, got \(error)")
            }
            XCTAssertEqual(expected, "msgID")
            XCTAssertEqual(got, "messageID")
        }
    }

    /// Labels are optional in both directions, so a hand-written Python file
    /// that leaves them off still compiles.
    func testPythonWithoutLabelsStillCompiles() throws {
        let bare = try compile("""
        __SCRIPT_TYPE__ = 0x100
        __COMPILER_METADATA__ = 0x0

        def function_0():
            dialogDisplaySilentMessage(7, True, False)
        """)
        XCTAssertEqual(bare.rawBytes, try compile(swiftSource(body: "dialogDisplaySilentMessage(7, true, false)")).rawBytes)
    }
}
