//
//  MCPLogger.swift
//  GODDESS
//
//  Bridges GODOps' synchronous `Logger` seam to MCP `notifications/message`
//  log events, so a client watching the session sees an operation's progress
//  as it runs. Best-effort and fire-and-forget: each line is forwarded on a
//  detached task (the operation itself blocks synchronously), so ordering is
//  not guaranteed — this is a live activity feed, not an audit log.
//

import Foundation
import GoDFoundation
import MCP

final class MCPLogger: GoDFoundation.Logger {
    private let server: Server
    private let loggerName: String

    init(server: Server, loggerName: String = "goddess") {
        self.server = server
        self.loggerName = loggerName
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

        let server = self.server
        let name = self.loggerName
        Task { try? await server.log(level: level, logger: name, data: .string(text)) }
    }
}
