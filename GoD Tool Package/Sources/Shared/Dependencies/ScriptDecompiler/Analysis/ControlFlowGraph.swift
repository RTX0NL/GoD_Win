import GoDFoundation

/// A basic block in the control flow graph
public struct BasicBlock {
    /// Unique block ID (sequential)
    public let id: Int
    /// Starting label offset (byte offset in original bytecode)
    public let startOffset: Int?
    /// Statements in this block (excluding the terminating jump)
    public var statements: [ScriptStatement]
    public var terminator: BlockTerminator

    public init(id: Int, startOffset: Int?, statements: [ScriptStatement], terminator: BlockTerminator) {
        self.id = id
        self.startOffset = startOffset
        self.statements = statements
        self.terminator = terminator
    }
}

/// How a basic block exits
public enum BlockTerminator: Equatable {
    case fallthrough_(nextBlockID: Int)
    /// Conditional branch: if condition is false, jump to falseBlock; otherwise fall through to trueBlock
    case conditional(condition: ScriptExpr, trueBlockID: Int, falseBlockID: Int)
    case jump(targetBlockID: Int)
    case returnVoid
    case returnValue(ScriptExpr)
    case exit
}

/// Control flow graph for a single function
public struct ControlFlowGraph {
    public var blocks: [BasicBlock]
    /// Maps byte offset → block ID for jump target resolution
    public let offsetToBlockID: [Int: Int]

    public init(blocks: [BasicBlock], offsetToBlockID: [Int: Int]) {
        self.blocks = blocks
        self.offsetToBlockID = offsetToBlockID
    }
}

/// Builds a control flow graph from a list of statements (with labels and jumps)
public struct CFGBuilder {

    public init() {}

    public func build(from statements: [ScriptStatement]) -> ControlFlowGraph {
        // Step 1: Find all label offsets (block boundaries)
        var labelOffsets = Set<Int>()
        for stmt in statements {
            switch stmt {
            case .label(let offset):
                labelOffsets.insert(offset)
            default:
                break
            }
        }

        // Step 2: Split into basic blocks at labels and after jumps
        var blocks = [BasicBlock]()
        var currentStatements = [ScriptStatement]()
        var currentStartOffset: Int? = nil
        var blockID = 0

        var offsetToBlockID = [Int: Int]()
        // Track jump targets per block for resolution in step 3
        var pendingJumpTargets = [(blockID: Int, targetOffset: Int, isConditional: Bool)]()

        for stmt in statements {
            switch stmt {
            case .label(let offset):
                if !currentStatements.isEmpty {
                    let block = BasicBlock(
                        id: blockID,
                        startOffset: currentStartOffset,
                        statements: currentStatements,
                        terminator: .fallthrough_(nextBlockID: blockID + 1)
                    )
                    blocks.append(block)
                    blockID += 1
                    currentStatements = []
                }
                currentStartOffset = offset
                offsetToBlockID[offset] = blockID

            case .jump(let target):
                pendingJumpTargets.append((blockID: blockID, targetOffset: target, isConditional: false))
                let block = BasicBlock(
                    id: blockID,
                    startOffset: currentStartOffset,
                    statements: currentStatements,
                    terminator: .jump(targetBlockID: -1)
                )
                blocks.append(block)
                blockID += 1
                currentStatements = []
                currentStartOffset = nil

            case .jumpIfFalse(let condition, let target):
                pendingJumpTargets.append((blockID: blockID, targetOffset: target, isConditional: true))
                let block = BasicBlock(
                    id: blockID,
                    startOffset: currentStartOffset,
                    statements: currentStatements,
                    terminator: .conditional(
                        condition: condition,
                        trueBlockID: blockID + 1,
                        falseBlockID: -1
                    )
                )
                blocks.append(block)
                blockID += 1
                currentStatements = []
                currentStartOffset = nil

            case .jumpIfTrue(let condition, let target):
                pendingJumpTargets.append((blockID: blockID, targetOffset: target, isConditional: true))
                let block = BasicBlock(
                    id: blockID,
                    startOffset: currentStartOffset,
                    statements: currentStatements,
                    terminator: .conditional(
                        condition: .unary(.not, condition),
                        trueBlockID: blockID + 1,
                        falseBlockID: -1
                    )
                )
                blocks.append(block)
                blockID += 1
                currentStatements = []
                currentStartOffset = nil

            case .returnVoid:
                let block = BasicBlock(
                    id: blockID,
                    startOffset: currentStartOffset,
                    statements: currentStatements,
                    terminator: .returnVoid
                )
                blocks.append(block)
                blockID += 1
                currentStatements = []
                currentStartOffset = nil

            case .returnValue(let expr):
                let block = BasicBlock(
                    id: blockID,
                    startOffset: currentStartOffset,
                    statements: currentStatements,
                    terminator: .returnValue(expr)
                )
                blocks.append(block)
                blockID += 1
                currentStatements = []
                currentStartOffset = nil

            case .exit:
                let block = BasicBlock(
                    id: blockID,
                    startOffset: currentStartOffset,
                    statements: currentStatements,
                    terminator: .exit
                )
                blocks.append(block)
                blockID += 1
                currentStatements = []
                currentStartOffset = nil

            default:
                currentStatements.append(stmt)
            }
        }

        if !currentStatements.isEmpty {
            blocks.append(BasicBlock(
                id: blockID,
                startOffset: currentStartOffset,
                statements: currentStatements,
                terminator: .exit
            ))
        }

        // Step 3: Resolve jump targets using pendingJumpTargets collected in step 2
        for jt in pendingJumpTargets {
            guard jt.blockID < blocks.count else { continue }
            let targetBlockID = offsetToBlockID[jt.targetOffset] ?? min(jt.blockID + 1, blocks.count - 1)
            let clampedTarget = min(max(targetBlockID, 0), blocks.count - 1)

            if jt.isConditional {
                if case .conditional(let cond, let trueID, _) = blocks[jt.blockID].terminator {
                    blocks[jt.blockID].terminator = .conditional(
                        condition: cond,
                        trueBlockID: min(trueID, blocks.count - 1),
                        falseBlockID: clampedTarget
                    )
                }
            } else {
                blocks[jt.blockID].terminator = .jump(targetBlockID: clampedTarget)
            }
        }

        return ControlFlowGraph(blocks: blocks, offsetToBlockID: offsetToBlockID)
    }
}
