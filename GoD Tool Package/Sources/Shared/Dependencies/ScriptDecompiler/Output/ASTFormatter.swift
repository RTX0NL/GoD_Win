import GoDFoundation

/// Protocol for language-specific formatting of AST nodes
public protocol ScriptSyntax {
    func functionHeader(name: String, args: [String]) -> String
    /// Format a block opening (e.g., "{" or ":")
    func blockOpen() -> String
    /// Format a block closing (e.g., "}")
    func blockClose() -> String?
    func ifHeader(condition: String) -> String
    func elseHeader() -> String
    func elseIfHeader(condition: String) -> String
    func whileHeader(condition: String) -> String
    func returnStatement(value: String?) -> String
    /// Uses braces (true) or indentation (false) for blocks
    var usesBraces: Bool { get }
}

/// Formats an AST into readable text using a given syntax
public struct ASTFormatter {

    public let syntax: ScriptSyntax
    public let builtInNames: [Int: String]
    public let indent: String

    public init(syntax: ScriptSyntax, builtInNames: [Int: String] = [:], indent: String = "    ") {
        self.syntax = syntax
        self.builtInNames = builtInNames
        self.indent = indent
    }

    public func format(function: ASTFunction) -> String {
        var lines = [String]()
        let args = (0..<function.argCount).map { "arg\($0)" }
        lines.append(syntax.functionHeader(name: function.name, args: args) + syntax.blockOpen())
        lines += formatNode(function.body, depth: 1)
        if let close = syntax.blockClose() {
            lines.append(close)
        }
        return lines.joined(separator: "\n")
    }

    public func format(functions: [ASTFunction]) -> String {
        functions.map { format(function: $0) }.joined(separator: "\n\n")
    }

    // MARK: - Node Formatting

    private func formatNode(_ node: ASTNode, depth: Int) -> [String] {
        let prefix = String(repeating: indent, count: depth)

        switch node {
        case .block(let nodes):
            return nodes.flatMap { formatNode($0, depth: depth) }

        case .assign(let target, let value):
            return ["\(prefix)\(formatVariable(target)) = \(formatExpr(value))"]

        case .copyMemory(let dest, let source, let length):
            return ["\(prefix)memcpy(\(formatVariable(dest)), \(formatVariable(source)), \(length))"]

        case .expression(let expr):
            return ["\(prefix)\(formatExpr(expr))"]

        case .ifThen(let condition, let body):
            var lines = [String]()
            lines.append("\(prefix)\(syntax.ifHeader(condition: formatExpr(condition)))\(syntax.blockOpen())")
            lines += formatNode(body, depth: depth + 1)
            if let close = syntax.blockClose() {
                lines.append("\(prefix)\(close)")
            }
            return lines

        case .ifThenElse(let condition, let thenBody, let elseBody):
            var lines = [String]()
            lines.append("\(prefix)\(syntax.ifHeader(condition: formatExpr(condition)))\(syntax.blockOpen())")
            lines += formatNode(thenBody, depth: depth + 1)
            if syntax.usesBraces {
                lines.append("\(prefix)\(syntax.blockClose()!) \(syntax.elseHeader())\(syntax.blockOpen())")
            } else {
                lines.append("\(prefix)\(syntax.elseHeader())\(syntax.blockOpen())")
            }
            lines += formatNode(elseBody, depth: depth + 1)
            if let close = syntax.blockClose() {
                lines.append("\(prefix)\(close)")
            }
            return lines

        case .whileLoop(let condition, let body):
            var lines = [String]()
            lines.append("\(prefix)\(syntax.whileHeader(condition: formatExpr(condition)))\(syntax.blockOpen())")
            lines += formatNode(body, depth: depth + 1)
            if let close = syntax.blockClose() {
                lines.append("\(prefix)\(close)")
            }
            return lines

        case .returnVoid:
            return ["\(prefix)\(syntax.returnStatement(value: nil))"]

        case .returnValue(let expr):
            return ["\(prefix)\(syntax.returnStatement(value: formatExpr(expr)))"]

        case .yield(let frames):
            return ["\(prefix)yield(\(frames))"]

        case .label(let name):
            return ["\(prefix)// \(name):"]

        case .goto_(let name):
            return ["\(prefix)goto \(name)"]

        case .nop:
            return []
        }
    }

    // MARK: - Expression Formatting

    public func formatExpr(_ expr: ScriptExpr) -> String {
        switch expr {
        case .constant(let c):
            return formatConstant(c)
        case .variable(let v):
            return formatVariable(v)
        case .lastResult:
            return "result"
        case .binary(let op, let lhs, let rhs):
            return "(\(formatExpr(lhs)) \(op.rawValue) \(formatExpr(rhs)))"
        case .unary(let op, let operand):
            return "\(op.rawValue)\(formatExpr(operand))"
        case .callScript(let i, let args, let name):
            let argStr = args.map { formatExpr($0) }.joined(separator: ", ")
            return "\(name ?? "function_\(i)")(\(argStr))"
        case .callBuiltIn(let i, let args, let name):
            let resolvedName = name ?? builtInNames[i] ?? "builtin_\(i)"
            let argStr = args.map { formatExpr($0) }.joined(separator: ", ")
            return "\(resolvedName)(\(argStr))"
        case .printf(let args):
            let argStr = args.map { formatExpr($0) }.joined(separator: ", ")
            return "printf(\(argStr))"
        }
    }

    private func formatConstant(_ c: IRConstant) -> String {
        switch c {
        case .integer(let v):
            if v >= -256 && v <= 0xFF { return "\(v)" }
            return "0x\(String(UInt32(bitPattern: v), radix: 16, uppercase: true))"
        case .float(let v):
            return "\(v)"
        case .void:
            return "void"
        case .string(let i):
            return "string(\(i))"
        case .unknown(let t, let v):
            return "raw(\(t), 0x\(String(v, radix: 16)))"
        }
    }

    private func formatVariable(_ v: IRVariable) -> String {
        switch v.storage {
        case .global(let i): return "global_\(i)"
        case .local(let i): return i >= 0 ? "arg\(i)" : "local_\(abs(i))"
        case .literal: return "lit"
        case .lastResult: return "result"
        }
    }
}
