import GoDFoundation
import ScriptDecompiler

/// Parses decompiled Colosseum script source (the Swift-flavoured dialect
/// emitted by `ColoExprFormatter` + `ColoScriptSourceHeader`) back into
/// expression trees for compilation.
///
/// The parser reconstructs the exact expression shapes
/// `ColoExpressionBuilder` produces from bytecode, using the measured GS
/// code-generation rules:
/// - bare variable references in operator/assignment-source positions become
///   direct-mask operand wraps; anywhere else they are pushMultiVar reads
/// - assignment/return source masks are `0x80 | the RHS variable's own mask`
///   for bare variable sources, else `0x80 | value type`
/// - `&` marks the rare pushVar read form; `globals`/`globalsF`/`globalsO`
///   spell computed-access masks; declarations spell slot types
public struct ColoScriptTextParser {

    public struct ParsedFunction {
        public var index: Int
        public var argCount: Int
        public var returnsValue: Bool
        public var isStub: Bool
        public var body: [ColoExpr]
    }

    public struct ParsedScript {
        public var scriptTypeID: UInt16 = 0x100
        public var compilerMetadata: UInt16 = 0
        public var headerField2: UInt16 = 0x0101
        public var gvarTypes: [ColoValueType] = []
        /// Functions in source (= file emission) order
        public var functions: [ParsedFunction] = []
        /// String literals referenced by printf, in first-use order
        public var strings: [String] = []
    }

    public enum ParseError: Error, CustomStringConvertible {
        case unexpected(String, line: Int)
        public var description: String {
            switch self {
            case .unexpected(let what, let line): return "parse error at line \(line): \(what)"
            }
        }
    }

    /// Built-in name → function ID (reverse of the engine's definition table)
    private let builtinIDs: [String: Int]
    /// Function index → declared `-> Int` (filled by the signature pre-pass)
    private var functionReturns = [Int: Bool]()
    private var gvarTypes = [ColoValueType]()
    private var strings = [String]()
    private var stringIndices = [String: Int]()
    /// goto label name → symbolic label ID (per function). Parser labels use
    /// a distinct negative range so they never collide with the fresh labels
    /// `ColoExprUncompound` allocates from -1 downwards.
    private var labelIDs = [String: Int]()
    private static let parserLabelBase = -1_000_000
    /// Declared argument types of the function being parsed (by display index)
    private var currentArgTypes = [ColoValueType]()

    public init(builtInFunctions: [Int: ScriptFunctionDef]) {
        var ids = [String: Int]()
        for (id, def) in builtInFunctions { ids[def.name] = id }
        self.builtinIDs = ids
    }

    // MARK: - Lexer

    private struct Token {
        enum Kind: Equatable {
            case identifier(String)
            case integer(Int32)
            case float(Float)
            case string(String)
            case symbol(String)   // punctuation and operators
            case newline
        }
        let kind: Kind
        let line: Int
    }

    private static let multiCharSymbols = ["->", "==", "!=", "<=", ">=", "&&", "||"]

    private func tokenize(_ source: String) throws -> [Token] {
        var tokens = [Token]()
        var line = 1
        var i = source.startIndex
        let end = source.endIndex

        func peek(_ offset: Int = 0) -> Character? {
            guard let idx = source.index(i, offsetBy: offset, limitedBy: end), idx < end else { return nil }
            return source[idx]
        }

        while i < end {
            let c = source[i]
            if c == "\n" {
                tokens.append(Token(kind: .newline, line: line))
                line += 1
                i = source.index(after: i)
                continue
            }
            if c == " " || c == "\t" || c == "\r" {
                i = source.index(after: i)
                continue
            }
            if (c == "/" && peek(1) == "/") || c == "#" {
                while i < end, source[i] != "\n" { i = source.index(after: i) }
                continue
            }
            if c == "\"" {
                i = source.index(after: i)
                var text = ""
                while i < end, source[i] != "\"" {
                    if source[i] == "\\", let next = peek(1) {
                        switch next {
                        case "n": text.append("\n")
                        case "t": text.append("\t")
                        case "\\": text.append("\\")
                        case "\"": text.append("\"")
                        default: text.append(next)
                        }
                        i = source.index(i, offsetBy: 2)
                    } else {
                        text.append(source[i])
                        i = source.index(after: i)
                    }
                }
                if i < end { i = source.index(after: i) }
                tokens.append(Token(kind: .string(text), line: line))
                continue
            }
            if c.isNumber || (c == "-" && (peek(1)?.isNumber ?? false) && startsNumberContext(tokens)) {
                var text = String(c)
                i = source.index(after: i)
                var isFloat = false
                var isHex = false
                while i < end {
                    let ch = source[i]
                    if ch == "x" || ch == "X", text == "0" || text == "-0" { isHex = true }
                    else if ch == "." && !isHex { isFloat = true }
                    else if (ch == "e" || ch == "E") && !isHex { isFloat = true }
                    else if (ch == "+" || ch == "-") && (text.last == "e" || text.last == "E") { /* exponent sign */ }
                    else if !ch.isHexDigit { break }
                    text.append(ch)
                    i = source.index(after: i)
                }
                if isFloat {
                    guard let value = Float(text) else { throw ParseError.unexpected("bad float \(text)", line: line) }
                    tokens.append(Token(kind: .float(value), line: line))
                } else if isHex {
                    let negative = text.hasPrefix("-")
                    let digits = String(text.dropFirst(negative ? 3 : 2))
                    guard let value = UInt32(digits, radix: 16) else { throw ParseError.unexpected("bad hex \(text)", line: line) }
                    let signed = Int32(bitPattern: value)
                    tokens.append(Token(kind: .integer(negative ? -signed : signed), line: line))
                } else {
                    guard let value = Int32(text) else { throw ParseError.unexpected("bad int \(text)", line: line) }
                    tokens.append(Token(kind: .integer(value), line: line))
                }
                continue
            }
            if c.isLetter || c == "_" {
                var text = String(c)
                i = source.index(after: i)
                while i < end, source[i].isLetter || source[i].isNumber || source[i] == "_" {
                    text.append(source[i])
                    i = source.index(after: i)
                }
                tokens.append(Token(kind: .identifier(text), line: line))
                continue
            }
            // symbols
            var matched = false
            for sym in Self.multiCharSymbols {
                if source[i...].hasPrefix(sym) {
                    tokens.append(Token(kind: .symbol(sym), line: line))
                    i = source.index(i, offsetBy: sym.count)
                    matched = true
                    break
                }
            }
            if matched { continue }
            tokens.append(Token(kind: .symbol(String(c)), line: line))
            i = source.index(after: i)
        }
        return tokens
    }

    /// `-` starts a negative literal only where a value is expected
    /// (start of line, after an operator/open paren/comma), not after an
    /// operand — the corpus never uses the negate opcode, so a leading
    /// minus always folds into the literal.
    private func startsNumberContext(_ tokens: [Token]) -> Bool {
        for token in tokens.reversed() {
            switch token.kind {
            case .newline: return true
            case .symbol(let s):
                return !(s == ")" || s == "]")
            case .identifier(let name):
                // Keywords precede values; other identifiers are operands
                return ["return", "if", "while", "else", "in"].contains(name)
            case .integer, .float, .string:
                return false
            }
        }
        return true
    }

    /// Python mode: synthesize `{`/`}` from indentation so block parsing
    /// is shared with the Swift dialect. Indent grows only after `:` lines
    /// in the emitted dialect, so a plain indent stack suffices.
    private static func insertingIndentBraces(_ tokens: [Token], source: String) -> [Token] {
        // Indent (in spaces) of each 1-based line; nil for blank/comment-only
        var lineIndents = [Int: Int]()
        for (index, lineText) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = lineText.drop(while: { $0 == " " })
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            lineIndents[index + 1] = lineText.count - trimmed.count
        }

        var result = [Token]()
        var stack = [0]
        var currentLine = 0
        for token in tokens {
            if token.line != currentLine, let indent = lineIndents[token.line], case .newline = token.kind {} else if token.line != currentLine, let indent = lineIndents[token.line] {
                while indent < stack.last! {
                    stack.removeLast()
                    result.append(Token(kind: .symbol("}"), line: token.line))
                }
                if indent > stack.last! {
                    stack.append(indent)
                    result.append(Token(kind: .symbol("{"), line: token.line))
                }
                currentLine = token.line
            }
            result.append(token)
        }
        while stack.count > 1 {
            stack.removeLast()
            result.append(Token(kind: .symbol("}"), line: currentLine + 1))
        }
        return result
    }

    // MARK: - Token stream

    private struct Stream {
        var tokens: [Token]
        var pos = 0
        init(_ tokens: [Token]) { self.tokens = tokens }

        var current: Token? { pos < tokens.count ? tokens[pos] : nil }
        var line: Int { current?.line ?? -1 }

        mutating func advance() -> Token? {
            defer { pos += 1 }
            return current
        }
        mutating func skipNewlines() {
            while case .newline = current?.kind { pos += 1 }
        }
        func peekKind(_ offset: Int = 0) -> Token.Kind? {
            let index = pos + offset
            return index < tokens.count ? tokens[index].kind : nil
        }
        mutating func matchSymbol(_ s: String) -> Bool {
            if case .symbol(let v) = current?.kind, v == s { pos += 1; return true }
            return false
        }
        mutating func matchIdentifier(_ name: String) -> Bool {
            if case .identifier(let v) = current?.kind, v == name { pos += 1; return true }
            return false
        }
        mutating func expectSymbol(_ s: String) throws {
            guard matchSymbol(s) else {
                throw ParseError.unexpected("expected '\(s)' got \(String(describing: current?.kind))", line: line)
            }
        }
        mutating func expectIdentifier() throws -> String {
            if case .identifier(let v) = current?.kind { pos += 1; return v }
            throw ParseError.unexpected("expected identifier got \(String(describing: current?.kind))", line: line)
        }
        mutating func expectInteger() throws -> Int32 {
            if case .integer(let v) = current?.kind { pos += 1; return v }
            throw ParseError.unexpected("expected integer got \(String(describing: current?.kind))", line: line)
        }
    }

    // MARK: - Parse

    public mutating func parse(_ source: String) throws -> ParsedScript {
        var script = ParsedScript()
        gvarTypes = []
        strings = []
        stringIndices = [:]
        functionReturns = [:]

        var tokens = try tokenize(source)
        let isPython = source.contains("\ndef ") || source.hasPrefix("#")
        if isPython {
            tokens = Self.insertingIndentBraces(tokens, source: source)
        }

        // Signature pre-pass: function_N declared `-> Int` returns a value
        var scan = Stream(tokens)
        while let token = scan.advance() {
            guard case .identifier(let kw) = token.kind, kw == "func" || kw == "def" else { continue }
            guard case .identifier(let name)? = scan.current?.kind, name.hasPrefix("function_"),
                  let index = Int(name.dropFirst(9)) else { continue }
            var lookahead = scan
            _ = lookahead.advance()  // name
            var depth = 0
            var returns = false
            while let k = lookahead.peekKind() {
                if case .symbol("(") = k { depth += 1 }
                if case .symbol(")") = k { depth -= 1; if depth == 0 {
                    _ = lookahead.advance()
                    if case .symbol("->")? = lookahead.peekKind() { returns = true }
                    break
                }}
                _ = lookahead.advance()
            }
            functionReturns[index] = returns
        }

        var stream = Stream(tokens)
        var currentLocalArgBase = 0

        while true {
            stream.skipNewlines()
            guard let token = stream.current else { break }

            switch token.kind {
            case .identifier("static"):
                // static let __name = value
                _ = stream.advance()
                _ = stream.matchIdentifier("let")
                let name = try stream.expectIdentifier()
                try stream.expectSymbol("=")
                let value = try stream.expectInteger()
                switch name {
                case "__scriptType": script.scriptTypeID = UInt16(truncatingIfNeeded: value)
                case "__compilerMetadata": script.compilerMetadata = UInt16(truncatingIfNeeded: value)
                case "__headerField2": script.headerField2 = UInt16(truncatingIfNeeded: value)
                default:
                    throw ParseError.unexpected("unknown script constant \(name)", line: token.line)
                }

            case .identifier(let topName) where topName.hasPrefix("__") && topName.hasSuffix("__"):
                // Python module constant: __SCRIPT_TYPE__ = 0x100
                _ = stream.advance()
                try stream.expectSymbol("=")
                let value = try stream.expectInteger()
                switch topName {
                case "__SCRIPT_TYPE__": script.scriptTypeID = UInt16(truncatingIfNeeded: value)
                case "__COMPILER_METADATA__": script.compilerMetadata = UInt16(truncatingIfNeeded: value)
                case "__HEADER_FIELD2__": script.headerField2 = UInt16(truncatingIfNeeded: value)
                default:
                    throw ParseError.unexpected("unknown script constant \(topName)", line: token.line)
                }

            case .identifier(let topName) where topName.hasPrefix("gvar"):
                // Python declaration: gvarN = 0 | gvarN = 0.0 | gvarN: Object = 0
                _ = stream.advance()
                guard topName == "gvar\(gvarTypes.count)" else {
                    throw ParseError.unexpected("global declarations must be gvar0, gvar1, … in order (got \(topName))", line: token.line)
                }
                if stream.matchSymbol(":") {
                    _ = try stream.expectIdentifier()  // Object
                    try stream.expectSymbol("=")
                    _ = stream.advance()
                    gvarTypes.append(.void)
                } else {
                    try stream.expectSymbol("=")
                    switch stream.advance()?.kind {
                    case .float: gvarTypes.append(.float)
                    case .integer: gvarTypes.append(.integer)
                    default: throw ParseError.unexpected("bad global initializer", line: token.line)
                    }
                }

            case .identifier("var"):
                // var gvarN = 0 | var gvarN = 0.0 | var gvarN: Object = 0
                _ = stream.advance()
                let name = try stream.expectIdentifier()
                guard name == "gvar\(gvarTypes.count)" else {
                    throw ParseError.unexpected("global declarations must be gvar0, gvar1, … in order (got \(name))", line: token.line)
                }
                if stream.matchSymbol(":") {
                    let typeName = try stream.expectIdentifier()
                    guard typeName == "Object" else {
                        throw ParseError.unexpected("unknown global type \(typeName)", line: token.line)
                    }
                    try stream.expectSymbol("=")
                    _ = stream.advance()  // initializer value
                    gvarTypes.append(.void)
                } else {
                    try stream.expectSymbol("=")
                    switch stream.advance()?.kind {
                    case .float: gvarTypes.append(.float)
                    case .integer: gvarTypes.append(.integer)
                    default: throw ParseError.unexpected("bad global initializer", line: token.line)
                    }
                }

            case .identifier("func"), .identifier("def"):
                _ = stream.advance()
                let name = try stream.expectIdentifier()
                guard name.hasPrefix("function_"), let index = Int(name.dropFirst(9)) else {
                    throw ParseError.unexpected("bad function name \(name)", line: token.line)
                }
                try stream.expectSymbol("(")
                var argCount = 0
                var argTypes = [ColoValueType]()
                while !stream.matchSymbol(")") {
                    _ = try stream.expectIdentifier()
                    if stream.matchSymbol(":") {
                        let typeName = try stream.expectIdentifier()
                        argTypes.append(typeName.lowercased() == "float" ? .float : .integer)
                    } else {
                        argTypes.append(.integer)
                    }
                    argCount += 1
                    _ = stream.matchSymbol(",")
                }
                var returns = false
                if stream.matchSymbol("->") {
                    _ = try stream.expectIdentifier()  // Int / int
                    returns = true
                }
                // Python: `def f():` opens a block; `def f(): ...` is a stub
                var pythonStub = false
                if stream.matchSymbol(":") {
                    if stream.matchSymbol(".") {
                        _ = stream.matchSymbol(".")
                        _ = stream.matchSymbol(".")
                        pythonStub = true
                    }
                }
                stream.skipNewlines()
                if !pythonStub, stream.matchSymbol("{") {
                    currentLocalArgBase = returns ? 1 : 0
                    labelIDs = [:]
                    currentArgTypes = argTypes
                    let body = try parseBlock(&stream, localArgBase: currentLocalArgBase)
                    script.functions.append(ParsedFunction(
                        index: index, argCount: argCount, returnsValue: returns,
                        isStub: false, body: body))
                } else {
                    // Bodyless declaration = null table entry
                    script.functions.append(ParsedFunction(
                        index: index, argCount: argCount, returnsValue: returns,
                        isStub: true, body: []))
                }

            default:
                throw ParseError.unexpected("unexpected top-level token \(token.kind)", line: token.line)
            }
        }

        script.gvarTypes = gvarTypes
        script.strings = strings
        return script
    }

    /// Consume a block opener: `{` (Swift) or `:` + synthesized `{` (Python)
    private func expectBlockOpen(_ stream: inout Stream) throws {
        if stream.matchSymbol("{") { return }
        try stream.expectSymbol(":")
        stream.skipNewlines()
        try stream.expectSymbol("{")
    }

    // MARK: - Statements

    private mutating func parseBlock(_ stream: inout Stream, localArgBase: Int) throws -> [ColoExpr] {
        var statements = [ColoExpr]()
        while true {
            stream.skipNewlines()
            if stream.matchSymbol("}") { break }
            guard stream.current != nil else {
                throw ParseError.unexpected("unterminated block", line: stream.line)
            }
            statements.append(contentsOf: try parseStatement(&stream, localArgBase: localArgBase))
        }
        return statements
    }

    private mutating func parseStatement(_ stream: inout Stream, localArgBase: Int) throws -> [ColoExpr] {
        let line = stream.line

        if stream.matchIdentifier("return") {
            if case .newline? = stream.current?.kind {
                return [.returnVoid]
            }
            let value = try parseExpression(&stream, localArgBase: localArgBase)
            return [.returnResult(sourceWrap(value))]
        }

        if stream.matchIdentifier("pass") {
            return []
        }

        if stream.matchIdentifier("if") {
            var branches = [(ColoExpr, [ColoExpr])]()
            let condition = try parseExpression(&stream, localArgBase: localArgBase)
            try expectBlockOpen(&stream)
            branches.append((conditionValue(condition), try parseBlock(&stream, localArgBase: localArgBase)))
            while true {
                var isElif = false
                stream.skipNewlines()
                if stream.matchIdentifier("elif") { isElif = true }
                else if stream.matchIdentifier("else") {
                    if stream.matchIdentifier("if") { isElif = true }
                } else { break }
                if isElif {
                    let elifCondition = try parseExpression(&stream, localArgBase: localArgBase)
                    try expectBlockOpen(&stream)
                    branches.append((conditionValue(elifCondition), try parseBlock(&stream, localArgBase: localArgBase)))
                } else {
                    try expectBlockOpen(&stream)
                    branches.append((.constant(.integer(1)), try parseBlock(&stream, localArgBase: localArgBase)))
                    break
                }
            }
            return [.ifStatement(branches)]
        }

        if stream.matchIdentifier("while") {
            let condition = try parseExpression(&stream, localArgBase: localArgBase)
            try expectBlockOpen(&stream)
            let body = try parseBlock(&stream, localArgBase: localArgBase)
            return [.whileLoop(conditionValue(condition), body)]
        }

        if stream.matchIdentifier("exit") {
            try stream.expectSymbol("(")
            try stream.expectSymbol(")")
            return [.exit]
        }

        if stream.matchIdentifier("goto") {
            let label = try stream.expectIdentifier()
            return [.jump(labelID(label))]
        }

        // Label statement: `L_xxxx:`
        if case .identifier(let name)? = stream.current?.kind, name.hasPrefix("L_"),
           case .symbol(":")? = stream.peekKind(1) {
            _ = stream.advance()
            _ = stream.advance()
            return [.location(labelID(name))]
        }

        if stream.matchIdentifier("yield") {
            try stream.expectSymbol("(")
            let frames = try parseExpression(&stream, localArgBase: localArgBase)
            try stream.expectSymbol(")")
            return [.yield(frames)]
        }

        if stream.matchIdentifier("printf") {
            try stream.expectSymbol("(")
            guard case .string(let format)? = stream.advance()?.kind else {
                throw ParseError.unexpected("printf needs a string literal", line: line)
            }
            var args = [ColoExpr]()
            while stream.matchSymbol(",") {
                args.append(try parseExpression(&stream, localArgBase: localArgBase))
            }
            try stream.expectSymbol(")")
            return [.printf(formatToken(for: format), args)]
        }

        // Expression statement: assignment or call
        let expr = try parseExpression(&stream, localArgBase: localArgBase)
        switch expr {
        case .variableAssignment, .call, .callBuiltIn:
            return [expr]
        default:
            throw ParseError.unexpected("expression is not a statement: \(expr)", line: line)
        }
    }

    // MARK: - Expressions (precedence climbing)

    private static let binaryOps: [String: ColoOperator] = [
        "*": .multiply, "/": .divide, "%": .mod, "+": .add, "-": .subtract,
        "<": .lessThan, "<=": .lessThanEqual, ">": .greaterThan, ">=": .greaterThanEqual,
        "==": .equal, "!=": .notEqual, "&": .and, "|": .or, "&&": .logicalAnd, "||": .logicalOr,
    ]

    private mutating func parseExpression(_ stream: inout Stream, localArgBase: Int, minPrecedence: Int = 0, inIndex: Bool = false) throws -> ColoExpr {
        var lhs = try parseUnary(&stream, localArgBase: localArgBase, inIndex: inIndex)

        // Assignment (right-associative, lowest precedence)
        if minPrecedence == 0, stream.matchSymbol("=") {
            let value = try parseExpression(&stream, localArgBase: localArgBase)
            return makeAssignment(target: lhs, value: value)
        }

        while true {
            var matchedOp: ColoOperator?
            if case .symbol(let symbol)? = stream.current?.kind, let op = Self.binaryOps[symbol] {
                matchedOp = op
            } else if case .identifier("and")? = stream.current?.kind {
                matchedOp = .logicalAnd
            } else if case .identifier("or")? = stream.current?.kind {
                matchedOp = .logicalOr
            }
            guard let op = matchedOp, op.precedence >= minPrecedence else { break }
            _ = stream.advance()
            let rhs = try parseExpression(&stream, localArgBase: localArgBase, minPrecedence: op.precedence + 1, inIndex: inIndex)
            lhs = .operation(op, [operandWrap(rhs, inIndex: inIndex), operandWrap(lhs, inIndex: inIndex)])
        }
        return lhs
    }

    private mutating func parseUnary(_ stream: inout Stream, localArgBase: Int, inIndex: Bool = false) throws -> ColoExpr {
        if stream.matchSymbol("!") || stream.matchIdentifier("not") {
            let operand = try parseUnary(&stream, localArgBase: localArgBase, inIndex: inIndex)
            return .operation(.not, [operandWrap(operand, inIndex: inIndex)])
        }
        if stream.matchSymbol("-") {
            let operand = try parseUnary(&stream, localArgBase: localArgBase, inIndex: inIndex)
            return .operation(.negate, [operandWrap(operand, inIndex: inIndex)])
        }
        var form = ColoVarPushForm.multi(1)
        if stream.matchSymbol("&") {
            form = .single
        }
        return try parsePrimary(&stream, localArgBase: localArgBase, form: form, inIndex: inIndex)
    }

    private mutating func parsePrimary(_ stream: inout Stream, localArgBase: Int, form: ColoVarPushForm, inIndex: Bool = false) throws -> ColoExpr {
        let line = stream.line
        guard let token = stream.advance() else {
            throw ParseError.unexpected("unexpected end of input", line: line)
        }

        switch token.kind {
        case .integer(let value):
            return .constant(.integer(value))
        case .float(let value):
            return .constant(.float(value))
        case .symbol("("):
            let inner = try parseExpression(&stream, localArgBase: localArgBase, inIndex: inIndex)
            try stream.expectSymbol(")")
            // Parenthesized bare read = materialized (pushed) value: the
            // wrap is applied here so operand construction keeps it pushed
            if let bare = bareVariable(inner) {
                let mask = ColoScriptVar(
                    valueType: bare.variable.valueType,
                    isLocal: bare.variable.isLocal,
                    isLiteral: true,
                    isPointer: false,
                    flag0x20: bare.variable.flag0x20)
                return .variable(mask, inner, .wrap)
            }
            return inner

        case .identifier(let name):
            switch name {
            case "true", "True": return .constant(.integer(1))
            case "false", "False": return .constant(.integer(0))
            case "globals", "globalsF", "globalsO", "locals":
                try stream.expectSymbol("[")
                let index = try parseExpression(&stream, localArgBase: localArgBase, inIndex: true)
                try stream.expectSymbol("]")
                let variable: ColoScriptVar
                switch name {
                case "globalsF": variable = makeVar(type: .float, local: false)
                case "globalsO": variable = ColoScriptVar(valueType: .void, isLocal: false, isLiteral: false, isPointer: false, flag0x20: true)
                case "locals": variable = makeVar(type: .integer, local: true)
                default: variable = makeVar(type: .integer, local: false)
                }
                return .variable(variable, index, form)
            case "builtin":
                // builtin[expr](args) — computed function ID
                try stream.expectSymbol("[")
                let id = try parseExpression(&stream, localArgBase: localArgBase)
                try stream.expectSymbol("]")
                let args = try parseCallArgs(&stream, localArgBase: localArgBase)
                return .callBuiltIn(id, args)
            case "yield":
                try stream.expectSymbol("(")
                let frames = try parseExpression(&stream, localArgBase: localArgBase)
                try stream.expectSymbol(")")
                return .yield(frames)
            default:
                break
            }

            if name.hasPrefix("gvar"), let index = Int(name.dropFirst(4)) {
                let type = index < gvarTypes.count ? gvarTypes[index] : .integer
                return .variable(
                    ColoScriptVar(valueType: type, isLocal: false, isLiteral: false, isPointer: false, flag0x20: type == .void),
                    .constant(.integer(Int32(index))), form)
            }
            if name.hasPrefix("arg"), let index = Int(name.dropFirst(3)) {
                let type = index < currentArgTypes.count ? currentArgTypes[index] : .integer
                return .variable(makeVar(type: type, local: true),
                                 .constant(.integer(Int32(index + localArgBase))), form)
            }
            if name == "__returnSlot" {
                return .variable(makeVar(type: .integer, local: true), .constant(.integer(0)), form)
            }
            if name.hasPrefix("function_"), let index = Int(name.dropFirst(9)) {
                let args = try parseCallArgs(&stream, localArgBase: localArgBase)
                let returns = functionReturns[index] ?? false
                return .call(index, returnCount: returns ? 1 : 0, args)
            }
            if name.hasPrefix("builtin_"), let id = Int(name.dropFirst(8)) {
                let args = try parseCallArgs(&stream, localArgBase: localArgBase)
                return .callBuiltIn(.constant(.integer(Int32(id))), args)
            }
            if let id = builtinIDs[name] {
                let args = try parseCallArgs(&stream, localArgBase: localArgBase)
                return .callBuiltIn(.constant(.integer(Int32(id))), args)
            }
            throw ParseError.unexpected("unknown identifier \(name)", line: line)

        default:
            throw ParseError.unexpected("unexpected token \(token.kind)", line: line)
        }
    }

    private mutating func parseCallArgs(_ stream: inout Stream, localArgBase: Int) throws -> [ColoExpr] {
        try stream.expectSymbol("(")
        var args = [ColoExpr]()
        while !stream.matchSymbol(")") {
            // dup(expr, n): one pushMultiVar read filling n argument slots
            if case .identifier("dup")? = stream.current?.kind, case .symbol("(")? = stream.peekKind(1) {
                _ = stream.advance()
                _ = stream.advance()
                let expr = try parseExpression(&stream, localArgBase: localArgBase)
                try stream.expectSymbol(",")
                let count = try stream.expectInteger()
                try stream.expectSymbol(")")
                guard case .variable(let v, let index, _) = expr else {
                    throw ParseError.unexpected("dup() needs a variable read", line: stream.line)
                }
                let read = ColoExpr.variable(v, index, .multi(UInt16(count)))
                for _ in 0..<count { args.append(read) }
            } else {
                args.append(try parseExpression(&stream, localArgBase: localArgBase))
            }
            _ = stream.matchSymbol(",")
        }
        return args
    }

    // MARK: - Expression-shape rules

    private func makeVar(type: ColoValueType, local: Bool, literal: Bool = false) -> ColoScriptVar {
        ColoScriptVar(valueType: type, isLocal: local, isLiteral: literal, isPointer: false, flag0x20: false)
    }

    /// A bare variable read (pushMultiVar/pushVar form)
    private func bareVariable(_ expr: ColoExpr) -> (variable: ColoScriptVar, index: ColoExpr, form: ColoVarPushForm)? {
        if case .variable(let v, let index, let form) = expr, form != .wrap, !v.isLiteral {
            return (v, index, form)
        }
        return nil
    }

    /// Static value type of an expression (for literal-mask selection)
    private func valueType(of expr: ColoExpr) -> ColoValueType {
        switch expr {
        case .constant(.float): return .float
        case .variable(let v, _, _): return v.isLiteral ? valueTypeOfInner(expr) : v.valueType
        case .operation(let op, let operands):
            switch op {
            case .add, .subtract, .multiply, .divide, .mod, .negate:
                for operand in operands {
                    if case .variable(let v, let inner, .wrap) = operand {
                        let t = v.isLiteral ? valueType(of: inner) : v.valueType
                        if t == .float { return .float }
                    }
                }
                return .integer
            default:
                return .integer  // comparisons, logical, not
            }
        default:
            return .integer  // calls, yields — int results
        }
    }

    private func valueTypeOfInner(_ expr: ColoExpr) -> ColoValueType {
        if case .variable(let v, let inner, _) = expr {
            return v.isLiteral ? valueType(of: inner) : v.valueType
        }
        return valueType(of: expr)
    }

    /// Operand wrap for binary/unary operators: bare variable references use
    /// their own mask directly (the index is what gets pushed); any other
    /// expression is a pushed value with a literal mask of its type.
    private func operandWrap(_ expr: ColoExpr, inIndex: Bool = false) -> ColoExpr {
        // Already a pushed-value wrap (parenthesized bare read) — the parens
        // carry the pushed/direct distinction in every context
        if case .variable(let v, _, .wrap) = expr, v.isLiteral { return expr }
        if let bare = bareVariable(expr), case .multi(1) = bare.form {
            return .variable(bare.variable, bare.index, .wrap)
        }
        // Pushed operands use the same mask rule as assignment sources:
        // 0x80 | the variable's own mask for bare reads, else 0x80 | type
        return sourceWrap(expr)
    }

    /// Assignment/return source wrap: `0x80 | RHS variable's own mask` for
    /// bare variable sources (the read stays inside the wrap), else
    /// `0x80 | value type`.
    private func sourceWrap(_ expr: ColoExpr) -> ColoExpr {
        // Already a pushed-value wrap (parenthesized bare read)
        if case .variable(let v, _, .wrap) = expr, v.isLiteral { return expr }
        if let bare = bareVariable(expr) {
            let mask = ColoScriptVar(
                valueType: bare.variable.valueType,
                isLocal: bare.variable.isLocal,
                isLiteral: true,
                isPointer: false,
                flag0x20: bare.variable.flag0x20)
            return .variable(mask, expr, .wrap)
        }
        return .variable(makeVar(type: valueType(of: expr), local: false, literal: true), expr, .wrap)
    }

    private func makeAssignment(target: ColoExpr, value: ColoExpr) -> ColoExpr {
        guard let bare = bareVariable(target) else {
            // Should not occur: assignment targets are always variable refs
            return .variableAssignment(target, sourceWrap(value))
        }
        return .variableAssignment(
            .variable(bare.variable, bare.index, .wrap),
            sourceWrap(value))
    }

    /// Conditions are plain pushed values — a bare variable read stays a read
    private func conditionValue(_ expr: ColoExpr) -> ColoExpr { expr }

    private mutating func labelID(_ name: String) -> Int {
        if let existing = labelIDs[name] { return existing }
        let id = Self.parserLabelBase - labelIDs.count
        labelIDs[name] = id
        return id
    }

    /// Register a printf string literal and return the placeholder token the
    /// compiler resolves during layout (`stringlit:<index>`)
    private mutating func formatToken(for text: String) -> String {
        if text.hasPrefix("string@") { return text }  // unresolved legacy token
        let index: Int
        if let existing = stringIndices[text] {
            index = existing
        } else {
            index = strings.count
            strings.append(text)
            stringIndices[text] = index
        }
        return "stringlit:\(index)"
    }
}
