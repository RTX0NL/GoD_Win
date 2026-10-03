import XCTest
import GoDFoundation
import ScriptDecompiler
import Structs
@testable import Colosseum

/// Enum-typed builtin arguments: `soundPlayPokemonCry(PokemonSpecies.PIKACHU)`
/// instead of `soundPlayPokemonCry(25)`.
///
/// The rendering half already existed; what these cover is the way back, and
/// the two properties that make the spelling safe to adopt:
///
/// * it is *free* — the enum form and the integer form compile to the same
///   bytes, because a raw value is all the bytecode carries;
/// * it never guesses — a name that doesn't resolve is an error, and a value
///   the enum doesn't name is written as the integer rather than as a
///   synthesized case.
final class ColoScriptEnumTests: XCTestCase {

    private var builtins: [Int: ScriptFunctionDef] {
        ColosseumEngine.Data.defaultBuiltInFunctions.reduce(into: [:]) { result, pair in
            if let id = Int(pair.key) { result[id] = pair.value }
        }
    }

    /// The enum set the operations resolve against by default: the game
    /// engine's own.
    private var enums: [String: Enum] {
        Dictionary(
            ColosseumEngine.Enums.allItems.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func source(body: String) -> String {
        """
        // test
        static let __scriptType = 0x100
        static let __compilerMetadata = 0x0

        func function_0() {
            \(body)
        }
        """
    }

    private func parse(_ body: String, withEnums: Bool = true) throws -> ColoScriptTextParser.ParsedScript {
        var parser = ColoScriptTextParser(
            builtInFunctions: builtins,
            enums: withEnums ? enums : [:]
        )
        return try parser.parse(source(body: body))
    }

    private func compiled(_ body: String) throws -> [UInt8] {
        try ColoScriptCompiler().compile(parse(body)).rawBytes
    }

    // MARK: - Resolution

    func testEnumCaseResolvesToItsRawValue() throws {
        let parsed = try parse("soundPlayPokemonCry(PokemonSpecies.PIKACHU)")
        // `ColoExpr` isn't Equatable, so the argument is read out rather than
        // compared as a tree.
        var resolved: Int32?
        for expr in parsed.functions[0].body {
            guard case .callBuiltIn(_, let args) = expr,
                  case .constant(.integer(let value))? = args.first else { continue }
            resolved = value
        }
        XCTAssertEqual(resolved, 25, "PIKACHU is species 25")
    }

    /// Case lookup goes through `Enum.get(_:)`, which folds case — so a
    /// hand-typed lowercase name resolves rather than failing on spelling.
    func testEnumCaseLookupIsCaseInsensitive() throws {
        XCTAssertEqual(
            try compiled("soundPlayPokemonCry(PokemonSpecies.pikachu)"),
            try compiled("soundPlayPokemonCry(PokemonSpecies.PIKACHU)")
        )
    }

    /// The property that makes the enum form free: it is the same push.
    func testEnumSpellingCompilesToTheSameBytesAsTheInteger() throws {
        XCTAssertEqual(
            try compiled("soundPlayPokemonCry(PokemonSpecies.PIKACHU)"),
            try compiled("soundPlayPokemonCry(25)")
        )
    }

    func testEnumArgumentsResolveOnEveryTypedParameter() throws {
        // GroupID.protagonists = 0, ResourceID.wes = 100 — the pair carried by
        // every named `character*` builtin, which is what the corpus exercises.
        XCTAssertEqual(
            try compiled("characterHide(ResourceID.wes)"),
            try compiled("characterHide(100)")
        )
        XCTAssertEqual(
            try compiled("characterEndSpeech(GroupID.protagonists, ResourceID.rui)"),
            try compiled("characterEndSpeech(0, 101)")
        )
    }

    /// text -> binary -> text: the bytes the enum spelling compiles to render
    /// back as the same enum spelling. Hand-built bytecode would prove less —
    /// the compiler is what produces a call shape the emitter will actually
    /// see on a real script.
    func testEnumArgumentSurvivesTextToBinaryToText() throws {
        let binary = try ColoScriptCompiler().compile(
            parse("soundPlayPokemonCry(PokemonSpecies.PIKACHU)")
        )
        let script = try ColoScript(data: binary)
        let text = ColoScriptSourceEmitter(builtInFunctions: builtins, enums: enums)
            .decompileToText(script: script, fileName: "test.scd", syntax: .swift)
        XCTAssertTrue(
            text.contains("soundPlayPokemonCry(PokemonSpecies.PIKACHU)"),
            "emitted source was:\n\(text)"
        )

        // ...and compiling that text again reproduces the same bytes, which is
        // the property the corpus checks at scale.
        var reparse = ColoScriptTextParser(builtInFunctions: builtins, enums: enums)
        XCTAssertEqual(
            try ColoScriptCompiler().compile(reparse.parse(text)).rawBytes,
            binary.rawBytes
        )
    }

    // MARK: - Failures

    func testUnknownEnumNameThrows() {
        XCTAssertThrowsError(try parse("soundPlayPokemonCry(Pokemon.PIKACHU)")) { error in
            guard case ColoScriptTextParser.ParseError.unknownEnum(let name, _) = error else {
                return XCTFail("expected unknownEnum, got \(error)")
            }
            XCTAssertEqual(name, "Pokemon")
        }
    }

    func testUnknownEnumCaseThrows() {
        XCTAssertThrowsError(try parse("soundPlayPokemonCry(PokemonSpecies.MISSINGNO)")) { error in
            guard case ColoScriptTextParser.ParseError.unknownEnumCase(let enumName, let caseName, _) = error else {
                return XCTFail("expected unknownEnumCase, got \(error)")
            }
            XCTAssertEqual(enumName, "PokemonSpecies")
            XCTAssertEqual(caseName, "MISSINGNO")
        }
    }

    /// A build configured with no engines can't resolve anything, and says so
    /// rather than treating the name as an unknown identifier or a zero.
    func testEnumConstantWithoutAnEngineThrows() {
        XCTAssertThrowsError(
            try parse("soundPlayPokemonCry(PokemonSpecies.PIKACHU)", withEnums: false)
        ) { error in
            guard case ColoScriptTextParser.ParseError.unknownEnum = error else {
                return XCTFail("expected unknownEnum, got \(error)")
            }
        }
    }

    // MARK: - Rendering

    func testTypedParameterRendersAsAnEnumCase() {
        let formatter = ColoExprFormatter(builtInFunctions: builtins, enums: enums)
        let call = ColoExpr.callBuiltIn(.constant(.integer(218)), [.constant(.integer(25))])
        XCTAssertEqual(formatter.formatExpr(call), "soundPlayPokemonCry(PokemonSpecies.PIKACHU)")
    }

    /// A value no case names stays a number. A synthesized `PokemonSpecies_999`
    /// would be indistinguishable from a real case name in the source text,
    /// and would start meaning something else the moment the enum gained a
    /// case at that value.
    func testUnnamedValueFallsBackToTheInteger() {
        let formatter = ColoExprFormatter(builtInFunctions: builtins, enums: enums)
        let call = ColoExpr.callBuiltIn(.constant(.integer(218)), [.constant(.integer(9999))])
        // Hex because that is how the formatter prints a large literal; what
        // matters is that it is a number and not a name.
        let text = formatter.formatExpr(call)
        XCTAssertEqual(text, "soundPlayPokemonCry(0x270F)")
        XCTAssertFalse(text.contains("PokemonSpecies"))
    }

    /// Rendering needs the enum to be reachable; without it the argument is
    /// the integer, which still round-trips.
    func testUnresolvableEnumRendersAsTheInteger() {
        let formatter = ColoExprFormatter(builtInFunctions: builtins, enums: [:])
        let call = ColoExpr.callBuiltIn(.constant(.integer(218)), [.constant(.integer(25))])
        XCTAssertEqual(formatter.formatExpr(call), "soundPlayPokemonCry(25)")
    }
}
