//
//  WindowsStdioTransport.swift
//  GODDESS
//
//  The MCP swift-sdk only ships `StdioTransport` for Darwin, Glibc and Musl:
//  it relies on `fcntl` non-blocking I/O, which Windows doesn't have. This is
//  the same newline-delimited JSON-RPC transport for Windows, built on
//  blocking reads on a dedicated thread instead.
//
//  Reads happen on their own `Thread` rather than in a `Task`, because a
//  blocking read would otherwise pin one of the cooperative pool's few
//  threads for the server's whole lifetime.
//

#if os(Windows)
import Foundation
import Logging
import MCP
import ucrt

actor WindowsStdioTransport: Transport {
    nonisolated let logger: Logger

    private let input: FileHandle
    private let output: FileHandle
    private var isConnected = false
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

    /// - Parameters:
    ///   - inputDescriptor: C runtime descriptor to read requests from.
    ///   - outputDescriptor: C runtime descriptor to write responses to.
    init(inputDescriptor: Int32 = 0, outputDescriptor: Int32 = 1, logger: Logger? = nil) {
        // Text mode would turn every "\n" we write into "\r\n" and strip "\r"
        // from what we read; JSON-RPC framing wants the bytes untouched.
        _ = _setmode(inputDescriptor, _O_BINARY)
        _ = _setmode(outputDescriptor, _O_BINARY)
        self.input = FileHandle(fileDescriptor: inputDescriptor, closeOnDealloc: false)
        self.output = FileHandle(fileDescriptor: outputDescriptor, closeOnDealloc: false)
        self.logger = logger ?? Logger(label: "goddess.transport.stdio", factory: { _ in SwiftLogNoOpLogHandler() })

        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation
    }

    func connect() async throws {
        guard !isConnected else { return }
        isConnected = true

        let input = self.input
        let continuation = self.messageContinuation
        let logger = self.logger
        let reader = Thread {
            Self.readLoop(input: input, continuation: continuation, logger: logger)
        }
        reader.name = "GODDESS.MCP.stdin"
        reader.start()
        logger.debug("Transport connected")
    }

    /// Splits stdin into newline-delimited messages until EOF.
    private static func readLoop(
        input: FileHandle,
        continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation,
        logger: Logger
    ) {
        var pending = Data()
        while true {
            // `availableData` blocks until bytes arrive and returns empty at EOF.
            let chunk = input.availableData
            if chunk.isEmpty {
                logger.notice("EOF received")
                break
            }
            pending.append(chunk)

            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                var message = pending[pending.startIndex..<newline]
                pending = Data(pending[pending.index(after: newline)...])
                // Tolerate clients that frame with CRLF.
                if message.last == UInt8(ascii: "\r") {
                    message = message.dropLast()
                }
                if !message.isEmpty {
                    continuation.yield(Data(message))
                }
            }
        }
        continuation.finish()
    }

    func disconnect() async {
        guard isConnected else { return }
        isConnected = false
        messageContinuation.finish()
        logger.debug("Transport disconnected")
    }

    func send(_ data: Data) async throws {
        guard isConnected else {
            throw MCPError.internalError("Transport is not connected")
        }
        var framed = data
        framed.append(UInt8(ascii: "\n"))
        do {
            try output.write(contentsOf: framed)
        } catch {
            throw MCPError.transportError(error)
        }
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        messageStream
    }
}
#endif
