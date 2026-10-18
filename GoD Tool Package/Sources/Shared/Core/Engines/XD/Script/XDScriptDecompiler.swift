import GoDFoundation

/// An XD script (`.scd`) as readable source text.
///
/// Decompile only: there is no XD script compiler, so the text documents
/// what a script does and can't be built back into a `.scd`. Each function
/// goes through the expression builder, the if/while compounder and the
/// formatter; class and method names come from `XDScriptNames`. A jump the
/// compounder can't fold into structure is printed as a `goto` to an
/// `L_<word offset>` label rather than left out.
public struct XDScriptDecompiler {

    public init() {}

    /// The name a function is printed under, and called by.
    static func functionName(_ function: XDScript.FunctionEntry, index: Int) -> String {
        function.name.flatMap { $0.isEmpty ? nil : $0 } ?? "function_\(index)"
    }

    public func decompile(_ script: XDScript, fileName: String) -> String {
        var lines = [
            "// \(fileName), decompiled by GODDESS. XD scripts can't be rebuilt from this text.",
            "// \(script.functionCount) functions, \(script.globalVars.count) globals, "
                + "\(script.strings.count) strings, \(script.vectors.count) vectors, "
                + "\(script.characterRefs.count) characters.",
            "",
        ]
        if !script.globalVars.isEmpty {
            for (index, global) in script.globalVars.enumerated() {
                lines.append("// gvar\(index): type \(global.type), 0x\(String(global.value, radix: 16, uppercase: true))")
            }
            lines.append("")
        }
        if !script.vectors.isEmpty {
            for (index, vector) in script.vectors.enumerated() {
                lines.append("// vector(\(index)) = <\(vector.0), \(vector.1), \(vector.2)>")
            }
            lines.append("")
        }
        if !script.characterRefs.isEmpty {
            for (index, character) in script.characterRefs.enumerated() {
                lines.append("// character(\(index)): group \(character.groupID), resource \(character.resourceID)")
            }
            lines.append("")
        }

        let formatter = XDExprFormatter(
            classNames: XDScriptNames.classes,
            methodNames: XDScriptNames.methods.mapValues { $0.mapValues(\.name) },
            functionNames: Dictionary(
                script.functions.enumerated().map { ($1.codeOffset, Self.functionName($1, index: $0)) },
                uniquingKeysWith: { first, _ in first }
            )
        )
        let builder = XDExpressionBuilder()
        let compound = XDExpressionCompound()
        for (index, function) in script.functions.enumerated() {
            let (expressions, argCount) = builder.buildExpressions(
                instructions: script.functionInstructions[index], script: script
            )
            let name = Self.functionName(function, index: index)
            lines.append("// @ word 0x\(String(function.codeOffset, radix: 16, uppercase: true))")
            lines.append(formatter.formatFunction(name: name, argCount: argCount, body: compound.compound(expressions)))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
