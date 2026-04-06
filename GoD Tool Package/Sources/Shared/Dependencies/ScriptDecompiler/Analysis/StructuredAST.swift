import GoDFoundation

/// High-level structured AST nodes produced from CFG pattern matching
public indirect enum ASTNode: Equatable {
    /// A sequence of statements
    case block([ASTNode])
    /// Variable assignment
    case assign(target: IRVariable, value: ScriptExpr)
    /// Memory copy
    case copyMemory(dest: IRVariable, source: IRVariable, length: Int)
    /// Expression statement (function call for side effects)
    case expression(ScriptExpr)
    /// If-then
    case ifThen(condition: ScriptExpr, body: ASTNode)
    /// If-then-else
    case ifThenElse(condition: ScriptExpr, thenBody: ASTNode, elseBody: ASTNode)
    /// While loop
    case whileLoop(condition: ScriptExpr, body: ASTNode)
    /// Return void
    case returnVoid
    /// Return with value
    case returnValue(ScriptExpr)
    /// Yield
    case yield(frames: Int)
    /// Labeled goto (fallback for irreducible control flow)
    case label(String)
    case goto_(String)
    /// No-op
    case nop
}

/// A structured function definition
public struct ASTFunction {
    public let index: Int
    public let name: String
    public let argCount: Int
    public let body: ASTNode

    public init(index: Int, name: String, argCount: Int, body: ASTNode) {
        self.index = index
        self.name = name
        self.argCount = argCount
        self.body = body
    }
}

/// Converts a CFG into a structured AST by pattern-matching control flow constructs
public struct CFGStructurer {

    public init() {}

    /// Structure a CFG into an AST
    public func structure(_ cfg: ControlFlowGraph) -> ASTNode {
        guard !cfg.blocks.isEmpty else { return .block([]) }

        var visited = Set<Int>()
        return structureFrom(blockID: 0, cfg: cfg, visited: &visited, exitBlockID: nil)
    }

    private func structureFrom(
        blockID: Int,
        cfg: ControlFlowGraph,
        visited: inout Set<Int>,
        exitBlockID: Int?
    ) -> ASTNode {
        guard blockID >= 0, blockID < cfg.blocks.count, !visited.contains(blockID) else {
            return .block([])
        }

        // If we've reached the exit point of an enclosing structure, stop
        if let exit = exitBlockID, blockID == exit {
            return .block([])
        }

        visited.insert(blockID)
        let block = cfg.blocks[blockID]

        // Convert block statements to AST nodes
        var nodes = block.statements.compactMap { stmtToAST($0) }

        switch block.terminator {
        case .fallthrough_(let nextID):
            let rest = structureFrom(blockID: nextID, cfg: cfg, visited: &visited, exitBlockID: exitBlockID)
            nodes.append(rest)

        case .conditional(let condition, let trueID, let falseID):
            // Detect if-then, if-then-else, and while loops
            let ast = structureConditional(
                condition: condition,
                trueID: trueID,
                falseID: falseID,
                currentBlockID: blockID,
                cfg: cfg,
                visited: &visited,
                exitBlockID: exitBlockID
            )
            nodes.append(ast)

        case .jump(let targetID):
            // Check for back-edge (while loop detected at the conditional)
            if targetID <= blockID {
                // This is a loop back-edge — handled by the while detection
                // Don't recurse; the enclosing while structure handles continuation
            } else {
                // Forward jump — goto or break
                let rest = structureFrom(blockID: targetID, cfg: cfg, visited: &visited, exitBlockID: exitBlockID)
                nodes.append(rest)
            }

        case .returnVoid:
            nodes.append(.returnVoid)

        case .returnValue(let expr):
            nodes.append(.returnValue(expr))

        case .exit:
            break
        }

        return flattenBlock(nodes)
    }

    private func structureConditional(
        condition: ScriptExpr,
        trueID: Int,
        falseID: Int,
        currentBlockID: Int,
        cfg: ControlFlowGraph,
        visited: inout Set<Int>,
        exitBlockID: Int?
    ) -> ASTNode {
        // Check for while loop: if the false branch jumps back to before the condition
        // Pattern: condition block has a back-edge from the end of the true branch
        if let lastTrueBlock = findBlockEndingWithJumpTo(currentBlockID, startingFrom: trueID, cfg: cfg) {
            // while loop detected
            var whileVisited = Set<Int>()
            let body = structureFrom(blockID: trueID, cfg: cfg, visited: &whileVisited, exitBlockID: falseID)
            visited.formUnion(whileVisited)

            var nodes = [ASTNode]()
            nodes.append(.whileLoop(condition: condition, body: body))

            // Continue after the loop
            let rest = structureFrom(blockID: falseID, cfg: cfg, visited: &visited, exitBlockID: exitBlockID)
            nodes.append(rest)

            return flattenBlock(nodes)
        }

        // Check for if-then-else: true branch and false branch converge at a common point
        // Simple heuristic: if false branch is after true branch, it's if-then
        if falseID > trueID {
            // Check if the true branch ends with a jump past the false branch → if-else
            if let trueEndBlock = findBlockEndingWithJumpPast(falseID, startingFrom: trueID, cfg: cfg) {
                // if-then-else
                let mergeID = jumpTargetOf(cfg.blocks[trueEndBlock])

                var thenVisited = Set<Int>()
                let thenBody = structureFrom(blockID: trueID, cfg: cfg, visited: &thenVisited, exitBlockID: falseID)
                visited.formUnion(thenVisited)

                var elseVisited = Set<Int>()
                let elseBody = structureFrom(blockID: falseID, cfg: cfg, visited: &elseVisited, exitBlockID: mergeID)
                visited.formUnion(elseVisited)

                var nodes = [ASTNode]()
                nodes.append(.ifThenElse(condition: condition, thenBody: thenBody, elseBody: elseBody))

                // Continue after merge point
                if let merge = mergeID {
                    let rest = structureFrom(blockID: merge, cfg: cfg, visited: &visited, exitBlockID: exitBlockID)
                    nodes.append(rest)
                }

                return flattenBlock(nodes)
            }

            // Simple if-then (false branch is the continuation)
            var thenVisited = Set<Int>()
            let thenBody = structureFrom(blockID: trueID, cfg: cfg, visited: &thenVisited, exitBlockID: falseID)
            visited.formUnion(thenVisited)

            var nodes = [ASTNode]()
            nodes.append(.ifThen(condition: condition, body: thenBody))

            let rest = structureFrom(blockID: falseID, cfg: cfg, visited: &visited, exitBlockID: exitBlockID)
            nodes.append(rest)

            return flattenBlock(nodes)
        }

        // Fallback: emit as labeled goto
        var nodes = [ASTNode]()
        let thenBody = structureFrom(blockID: trueID, cfg: cfg, visited: &visited, exitBlockID: exitBlockID)
        nodes.append(.ifThen(condition: condition, body: thenBody))
        let rest = structureFrom(blockID: falseID, cfg: cfg, visited: &visited, exitBlockID: exitBlockID)
        nodes.append(rest)
        return flattenBlock(nodes)
    }

    // MARK: - Helpers

    private func stmtToAST(_ stmt: ScriptStatement) -> ASTNode? {
        switch stmt {
        case .assign(let target, let value): return .assign(target: target, value: value)
        case .copyMemory(let d, let s, let l): return .copyMemory(dest: d, source: s, length: l)
        case .expression(let expr): return .expression(expr)
        case .yield(let frames): return .yield(frames: frames)
        case .nop: return nil
        case .label, .jump, .jumpIfFalse, .jumpIfTrue, .returnVoid, .returnValue, .exit:
            return nil  // handled by terminator processing
        }
    }

    private func flattenBlock(_ nodes: [ASTNode]) -> ASTNode {
        let flat = nodes.flatMap { node -> [ASTNode] in
            if case .block(let inner) = node { return inner }
            return [node]
        }.filter { node in
            if case .block(let inner) = node { return !inner.isEmpty }
            return true
        }
        if flat.count == 1 { return flat[0] }
        return .block(flat)
    }

    /// Find a block that ends with a jump back to targetID, reachable from startID
    private func findBlockEndingWithJumpTo(_ targetID: Int, startingFrom startID: Int, cfg: ControlFlowGraph) -> Int? {
        var current = startID
        var seen = Set<Int>()
        while current < cfg.blocks.count && !seen.contains(current) {
            seen.insert(current)
            let block = cfg.blocks[current]
            switch block.terminator {
            case .jump(let t) where t == targetID:
                return current
            case .fallthrough_(let next):
                current = next
            case .conditional(_, let trueID, _):
                // Check true branch
                if let found = findBlockEndingWithJumpTo(targetID, startingFrom: trueID, cfg: cfg) {
                    return found
                }
                return nil
            default:
                return nil
            }
        }
        return nil
    }

    /// Find a block that ends with a jump past pastID, reachable from startID
    private func findBlockEndingWithJumpPast(_ pastID: Int, startingFrom startID: Int, cfg: ControlFlowGraph) -> Int? {
        var current = startID
        var seen = Set<Int>()
        while current < cfg.blocks.count && current < pastID && !seen.contains(current) {
            seen.insert(current)
            let block = cfg.blocks[current]
            switch block.terminator {
            case .jump(let t) where t >= pastID:
                return current
            case .fallthrough_(let next):
                current = next
            default:
                return nil
            }
        }
        return nil
    }

    private func jumpTargetOf(_ block: BasicBlock) -> Int? {
        if case .jump(let t) = block.terminator { return t }
        return nil
    }
}
