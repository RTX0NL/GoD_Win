//
//  ProgressReporter.swift
//  GODOps
//
//  Throttled `.taskStatus(…, .progress(_))` reporting for an operation that
//  works through a known number of items.
//

import GoDFoundation

/// Logs a task's progress once per whole percentage point.
///
/// Two reasons it is a type rather than a line inside each loop. One is the
/// throttle: a batch of 2,540 archives logging every item buries whatever
/// else the run has to say, and a batch of 3 that logs `33.3%` steps says
/// nothing a reader needs. The other is that `info` is suppressed unless the
/// project's `Settings.json` sets `verbose` — and the generated one doesn't —
/// so a long operation that reports only through `info` looks hung, while
/// `taskStatus` is always printed.
///
/// `total == 0` reports nothing: there is no progress through an empty batch,
/// and `0/0` is not 100 % done, it is undefined.
struct ProgressReporter {
    private let taskName: String
    private let total: Int
    private let logger: Logger?
    private var completed = 0
    private var lastReportedPercent = -1

    init(taskName: String, total: Int, logger: Logger?) {
        self.taskName = taskName
        self.total = total
        self.logger = logger
    }

    /// Counts one item done, logging only when the whole-number percentage
    /// changes — so the last item always reports 100 %.
    mutating func advance(by count: Int = 1) {
        guard total > 0, let logger else { return }
        completed = min(completed + count, total)
        let percent = completed * 100 / total
        guard percent != lastReportedPercent else { return }
        lastReportedPercent = percent
        logger.log(.taskStatus(taskName: taskName, status: .progress(Percentage(Double(percent)))))
    }
}
