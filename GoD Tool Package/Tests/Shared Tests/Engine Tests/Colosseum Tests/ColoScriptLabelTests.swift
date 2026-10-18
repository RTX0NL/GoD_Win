import XCTest
import GoDFoundation
import ScriptDecompiler
import Structs
@testable import Colosseum

/// `goto` labels in script source.
///
/// A `goto` to a label the function never declares used to reach the
/// lowering pass, which trapped in a debug build (taking the MCP server down
/// with it) and in a release build compiled a jump to offset 0. A label
/// declared twice silently kept only the last position. Both are mistakes in
/// the source, so the parser reports them with the line they're on.
final class ColoScriptLabelTests: XCTestCase {

    private var builtins: [Int: ScriptFunctionDef] {
        ColosseumEngine.Data.defaultBuiltInFunctions.reduce(into: [:]) { result, pair in
            if let id = Int(pair.key) { result[id] = pair.value }
        }
    }

    private func source(body: String) -> String {
        """
        static let __scriptType = 0x100
        static let __compilerMetadata = 0x0

        func function_0() {
        \(body)
        }
        """
    }

    private func parse(_ body: String) throws -> ColoScriptTextParser.ParsedScript {
        var parser = ColoScriptTextParser(builtInFunctions: builtins)
        return try parser.parse(source(body: body))
    }

    func testAGotoToADeclaredLabelCompiles() throws {
        let script = try parse("""
            L_0001:
            goto L_0001
        """)
        XCTAssertNoThrow(try ColoScriptCompiler().compile(script))
    }

    func testAGotoToAnUndeclaredLabelIsAParseError() {
        XCTAssertThrowsError(try parse("""
            L_0001:
            goto L_nowhere
        """)) { error in
            guard case ColoScriptTextParser.ParseError.undefinedLabel(let name, let line) = error else {
                return XCTFail("expected undefinedLabel, got \(error)")
            }
            XCTAssertEqual(name, "L_nowhere")
            XCTAssertEqual(line, 6)
        }
    }

    func testALabelDeclaredTwiceIsAParseError() {
        XCTAssertThrowsError(try parse("""
            L_0001:
            goto L_0001
            L_0001:
        """)) { error in
            guard case ColoScriptTextParser.ParseError.duplicateLabel(let name, let line) = error else {
                return XCTFail("expected duplicateLabel, got \(error)")
            }
            XCTAssertEqual(name, "L_0001")
            XCTAssertEqual(line, 7)
        }
    }

    /// Below the parser, the lowering pass reports a jump to a label nothing
    /// declares instead of trapping or compiling a jump to offset 0.
    func testLoweringAJumpToAnUndeclaredLabelThrows() {
        XCTAssertThrowsError(try ColoExprLowering().lower([.jump(-1_000_000)], startOffset: 0)) { error in
            guard case ColoExprLowering.LoweringError.undefinedLabel(-1_000_000) = error else {
                return XCTFail("expected undefinedLabel, got \(error)")
            }
        }
    }

    /// Labels belong to one function: the same name in two functions is two
    /// labels, and one function can't jump into another.
    func testLabelsDoNotCrossFunctions() throws {
        var parser = ColoScriptTextParser(builtInFunctions: builtins)
        XCTAssertNoThrow(try parser.parse("""
            static let __scriptType = 0x100
            static let __compilerMetadata = 0x0

            func function_0() {
                L_0001:
                goto L_0001
            }

            func function_1() {
                L_0001:
                goto L_0001
            }
            """))
        XCTAssertThrowsError(try parser.parse("""
            static let __scriptType = 0x100
            static let __compilerMetadata = 0x0

            func function_0() {
                L_0001:
            }

            func function_1() {
                goto L_0001
            }
            """))
    }
}
