import GoDFoundation

/// Python-subset syntax for script output
public struct PythonScriptSyntax: ScriptSyntax {

    public init() {}

    public func functionHeader(name: String, args: [String]) -> String {
        let argList = args.joined(separator: ", ")
        return "def \(name)(\(argList))"
    }

    public func blockOpen() -> String { ":" }
    public func blockClose() -> String? { nil }

    public func ifHeader(condition: String) -> String {
        "if \(condition)"
    }

    public func elseHeader() -> String { "else" }

    public func elseIfHeader(condition: String) -> String {
        "elif \(condition)"
    }

    public func whileHeader(condition: String) -> String {
        "while \(condition)"
    }

    public func returnStatement(value: String?) -> String {
        if let v = value {
            return "return \(v)"
        }
        return "return"
    }

    public var usesBraces: Bool { false }
}
