//
//  MCPLogger.swift
//  GODDESS
//
//  Gets a running tool call's log lines and progress to the client.
//
//  An operation logs synchronously from the tool call's thread, but sending
//  is async. Each call gets an `MCPOutbox`: lines go into one stream and a
//  single task sends them, so they arrive in the order they were logged, and
//  the call waits for the outbox to empty before it returns, so its result
//  never overtakes its last lines.
//

import Foundation
import GoDFoundation
import GODOps
import MCP

/// One tool call's outgoing notifications, sent in order.
final class MCPOutbox: Sendable {
    enum Item: Sendable {
        case log(LogLevel, String)
        case progress(ProgressNotification.Parameters)
    }

    private let continuation: AsyncStream<Item>.Continuation
    private let sender: Task<Void, Never>

    init(server: Server, loggerName: String = "goddess") {
        let (stream, continuation) = AsyncStream<Item>.makeStream()
        self.continuation = continuation
        sender = Task {
            for await item in stream {
                switch item {
                case .log(let level, let text):
                    try? await server.log(level: level, logger: loggerName, data: .string(text))
                case .progress(let parameters):
                    try? await server.notify(ProgressNotification.message(parameters))
                }
            }
        }
    }

    func send(_ item: Item) {
        continuation.yield(item)
    }

    /// Sends what is queued, then stops taking more.
    func finish() async {
        continuation.finish()
        await sender.value
    }
}

final class MCPLogger: GoDFoundation.Logger {
    private let outbox: MCPOutbox

    init(outbox: MCPOutbox) {
        self.outbox = outbox
    }

    func log(_ log: GoDFoundation.Log) {
        let level: LogLevel
        let text: String
        switch log {
        case .info(let message):
            level = .info; text = message
        case .warning(let message):
            level = .warning; text = message
        case .error(let message):
            level = .error; text = message
        case .taskStatus(let taskName, let status):
            switch status {
            case .started:
                level = .info; text = "TASK \(taskName): STARTED"
            case .completed(let success):
                level = success ? .info : .error
                text = "TASK \(taskName): \(success ? "COMPLETED" : "FAILED")"
            default:
                level = .info; text = "TASK \(taskName): \(status)"
            }
        }
        outbox.send(.log(level, text))
    }
}

/// Turns a run's progress into `notifications/progress` for a call whose
/// client asked for them with a progress token.
///
/// The spec wants the value to rise with every notification and leaves the
/// total optional. A run has no honest total — an operation's file count
/// isn't known until it has run — so the value counts events, and the
/// message says what happened. Writes come thousands at a time, so they are
/// sent at most every half second; operation boundaries always are.
final class MCPProgress: @unchecked Sendable {
    private static let interval: TimeInterval = 0.5

    private let token: ProgressToken
    private let outbox: MCPOutbox
    private let lock = NSLock()
    private var events = 0
    private var lastSent = Date.distantPast

    init(token: ProgressToken, outbox: MCPOutbox) {
        self.token = token
        self.outbox = outbox
    }

    func report(_ progress: RunProgress) {
        lock.lock()
        defer { lock.unlock() }
        events += 1
        let now = Date()
        if case .fileWritten = progress.event, now.timeIntervalSince(lastSent) < Self.interval {
            return
        }
        lastSent = now
        outbox.send(.progress(.init(progressToken: token, progress: Double(events), message: progress.summary)))
    }
}
