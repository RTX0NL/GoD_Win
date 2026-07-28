import GoDFoundation

/// Inverts `ColoExpressionCompound`: turns structured `ifStatement` /
/// `whileLoop` expressions back into flat `jumpFalse` / `jump` / `location`
/// sequences. Jump targets are emitted as fresh *symbolic labels* (negative
/// integers) — `ColoExprLowering.lower` resolves them to byte offsets during
/// layout, exactly as a text recompiler must.
public struct ColoExprUncompound {

    public init() {}

    public func uncompound(_ expressions: [ColoExpr]) -> [ColoExpr] {
        var nextLabel = -1
        return uncompound(expressions, nextLabel: &nextLabel)
    }

    private func uncompound(_ expressions: [ColoExpr], nextLabel: inout Int) -> [ColoExpr] {
        var result = [ColoExpr]()

        for expression in expressions {
            switch expression {
            case .ifStatement(let branches):
                lowerIf(branches: branches, into: &result, nextLabel: &nextLabel)

            case .whileLoop(let condition, let body):
                // while c { b } == L_top: jumpFalse(c, L_end); b; jump L_top; L_end:
                let top = allocateLabel(&nextLabel)
                let end = allocateLabel(&nextLabel)
                result.append(.location(top))
                result.append(.jumpFalse(condition, end))
                result.append(contentsOf: uncompound(body, nextLabel: &nextLabel))
                result.append(.jump(top))
                result.append(.location(end))

            default:
                result.append(expression)
            }
        }

        return result
    }

    private func lowerIf(branches: [(ColoExpr, [ColoExpr])], into result: inout [ColoExpr], nextLabel: inout Int) {
        guard !branches.isEmpty else { return }

        // Compounding builds:
        //  - plain if:        jumpFalse(c, L); body; L:
        //  - if/else:         jumpFalse(c, L1); then; jump L2; L1: else; L2:
        //    (the else branch carries condition `constant(1)`)
        let endLabel = allocateLabel(&nextLabel)

        for (index, branch) in branches.enumerated() {
            let isLast = index == branches.count - 1
            // A literal `if 1 { … }` is real (dead conditionals exist in the
            // data) — only non-first branches marked with constant(1) are else
            let isElse = index > 0 && isElseCondition(branch.0)

            if isElse {
                result.append(contentsOf: uncompound(branch.1, nextLabel: &nextLabel))
            } else {
                let skipLabel = isLast ? endLabel : allocateLabel(&nextLabel)
                result.append(.jumpFalse(branch.0, skipLabel))
                result.append(contentsOf: uncompound(branch.1, nextLabel: &nextLabel))
                if !isLast {
                    result.append(.jump(endLabel))
                    result.append(.location(skipLabel))
                }
            }
        }

        result.append(.location(endLabel))
    }

    private func isElseCondition(_ condition: ColoExpr) -> Bool {
        if case .constant(.integer(1)) = condition { return true }
        return false
    }

    private func allocateLabel(_ nextLabel: inout Int) -> Int {
        defer { nextLabel -= 1 }
        return nextLabel
    }
}
