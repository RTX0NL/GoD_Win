import GoDFoundation

/// Swift-subset syntax for script output
public struct SwiftScriptSyntax: ScriptSyntax {

    public init() {}

    public func functionHeader(name: String, args: [String]) -> String {
        let argList = args.map { "\($0): Int" }.joined(separator: ", ")
        return "func \(name)(\(argList)) "
    }

    public func blockOpen() -> String { "{" }
    public func blockClose() -> String? { "}" }

    public func ifHeader(condition: String) -> String {
        "if \(condition) "
    }

    public func elseHeader() -> String { "else " }

    public func elseIfHeader(condition: String) -> String {
        "else if \(condition) "
    }

    public func whileHeader(condition: String) -> String {
        "while \(condition) "
    }

    public func returnStatement(value: String?) -> String {
        if let v = value {
            return "return \(v)"
        }
        return "return"
    }

    public var usesBraces: Bool { true }
}
