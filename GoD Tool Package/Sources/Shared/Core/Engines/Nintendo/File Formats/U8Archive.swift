//
//  U8Archive.swift
//
//  The GameCube/Wii resource archive. A flat preorder table of nodes plus a
//  string table, then the file data.
//
//  Header (byte order per the magic — see `NintendoArchiveFormat`):
//
//      0x00  4  magic `U\xAA8-`
//      0x04  4  offset of the root node (0x20 in everything seen)
//      0x08  4  size of the node table + string table
//      0x0C  4  offset of the file data
//      0x10 16  reserved
//
//  Node (12 bytes): a packed word of `u8 type` + `u24 name offset`, then two
//  more words whose meaning depends on the type:
//
//      file       data offset (absolute), byte length
//      directory  index of its parent, index one past its last descendant
//
//  The root is node 0: an unnamed directory whose "one past last" is the
//  node count, which is how the count is discovered in the first place.
//  Because the table is preorder and a directory records where its subtree
//  ends, the whole tree is a flat ordered list — which is how it is modelled
//  here, so that ordering survives a round trip untouched.
//
//  Everything the writer needs is derivable from the entries plus the
//  engine's alignment: the data region starts at the first aligned boundary
//  after the tables, each file starts on that same boundary, gaps are zero,
//  and names are written in node order with no de-duplication. Verified
//  against Battle Revolution's `.arc` files.
//

import Foundation
import GoDFoundation

public struct U8Archive {

    public enum Kind {
        case directory
        case file(GoDData)

        public var isDirectory: Bool {
            if case .directory = self { return true }
            return false
        }
    }

    public struct Node {
        /// Slash-separated path within the archive, no leading slash.
        public let path: String
        public let kind: Kind

        public init(path: String, kind: Kind) {
            self.path = path
            self.kind = kind
        }

        public var name: String {
            String(path.split(separator: "/").last ?? "")
        }

        /// The containing directory's path, empty for a top-level node.
        public var parentPath: String {
            var parts = path.split(separator: "/")
            guard parts.count > 1 else { return "" }
            parts.removeLast()
            return parts.joined(separator: "/")
        }
    }

    public let byteOrder: ByteOrder
    /// Preorder, excluding the root.
    public let nodes: [Node]

    public init(byteOrder: ByteOrder, nodes: [Node]) {
        self.byteOrder = byteOrder
        self.nodes = nodes
    }

    public var files: [Node] {
        nodes.filter { !$0.kind.isDirectory }
    }

    // MARK: - Parse

    public init(data: GoDData, engine: NintendoEngine) throws {
        let bytes = data.rawBytes
        guard let signature = NintendoArchiveSignature.detect(data) else {
            throw NintendoArchiveError.unrecognizedMagic(found: Array(bytes.prefix(4)))
        }
        guard signature.format == .u8 else {
            throw NintendoArchiveError.wrongFormat(expected: .u8, found: signature.format)
        }

        let constants = engine.data.u8
        let reader = ArchiveReader(bytes: bytes, byteOrder: signature.byteOrder, format: "U8")

        let rootOffset = Int(try reader.u32(4))
        let nodeCount = Int(try reader.u32(rootOffset + 8))
        guard nodeCount >= 1 else {
            throw NintendoArchiveError.malformed(format: "U8", reason: "node count is zero")
        }
        let stringTable = rootOffset + nodeCount * constants.nodeLength

        var parsed: [Node] = []
        parsed.reserveCapacity(nodeCount - 1)

        // A directory records where its subtree ends, so the tree is walked
        // by popping any directory whose end index we have reached.
        var openDirectories: [(end: Int, path: String)] = [(nodeCount, "")]

        for index in 1 ..< nodeCount {
            let node = rootOffset + index * constants.nodeLength
            let packed = try reader.u32(node)
            let kind = packed >> 24
            let nameOffset = Int(packed & 0x00FF_FFFF)
            let first = Int(try reader.u32(node + 4))
            let second = Int(try reader.u32(node + 8))
            let name = try reader.cString(stringTable + nameOffset)

            while openDirectories.count > 1, index >= openDirectories[openDirectories.count - 1].end {
                openDirectories.removeLast()
            }
            let parent = openDirectories[openDirectories.count - 1].path
            let path = parent.isEmpty ? name : parent + "/" + name

            if kind == 1 {
                openDirectories.append((second, path))
                parsed.append(Node(path: path, kind: .directory))
            } else {
                let payload = try reader.slice(first, second)
                parsed.append(
                    Node(path: path, kind: .file(GoDData(byteStream: payload, byteOrder: signature.byteOrder)))
                )
            }
        }

        self.byteOrder = signature.byteOrder
        self.nodes = parsed
    }

    // MARK: - Serialize

    public func data(engine: NintendoEngine) throws -> GoDData {
        let constants = engine.data.u8
        let nodeCount = nodes.count + 1

        // File index of every directory, so a child can name its parent.
        // The root is 0 and is addressed by the empty path.
        var directoryIndex: [String: Int] = ["": 0]
        for (offset, node) in nodes.enumerated() where node.kind.isDirectory {
            directoryIndex[node.path] = offset + 1
        }
        for node in nodes where directoryIndex[node.parentPath] == nil {
            throw NintendoArchiveError.malformed(
                format: "U8",
                reason: "\(node.path) has no directory node for its parent \"\(node.parentPath)\""
            )
        }

        // Names, in node order and never shared — the root's empty name is
        // the leading NUL every real archive starts its string table with.
        var stringTable: [UInt8] = [0]
        var nameOffsets: [Int] = []
        for node in nodes {
            nameOffsets.append(stringTable.count)
            stringTable += encodeName(node.name) + [0]
        }

        let tablesLength = nodeCount * constants.nodeLength + stringTable.count
        let dataOffset = align(constants.headerLength + tablesLength, to: constants.dataAlignment)

        // File payloads, each starting on an alignment boundary.
        var fileOffsets: [Int] = []
        var payloads: [UInt8] = []
        for node in nodes {
            guard case let .file(payload) = node.kind else {
                fileOffsets.append(0)
                continue
            }
            let padding = align(payloads.count, to: constants.dataAlignment) - payloads.count
            payloads += [UInt8](repeating: constants.paddingByte, count: padding)
            fileOffsets.append(dataOffset + payloads.count)
            payloads += payload.rawBytes
        }

        var writer = ArchiveWriter(byteOrder: byteOrder, reserving: dataOffset + payloads.count)
        writer.append(raw: NintendoArchiveSignature(format: .u8, byteOrder: byteOrder).magic)
        writer.append(u32: UInt32(constants.headerLength))
        writer.append(u32: UInt32(tablesLength))
        writer.append(u32: UInt32(dataOffset))
        writer.pad(count: constants.headerLength - writer.bytes.count, with: 0)

        // Root: an unnamed directory whose end index is the node count.
        writer.append(u32: 1 << 24)
        writer.append(u32: 0)
        writer.append(u32: UInt32(nodeCount))

        for (offset, node) in nodes.enumerated() {
            let index = offset + 1
            let isDirectory = node.kind.isDirectory
            writer.append(u32: (isDirectory ? 1 << 24 : 0) | UInt32(nameOffsets[offset]))
            if isDirectory {
                writer.append(u32: UInt32(directoryIndex[node.parentPath] ?? 0))
                writer.append(u32: UInt32(subtreeEnd(ofDirectoryAt: offset, index: index)))
            } else {
                writer.append(u32: UInt32(fileOffsets[offset]))
                guard case let .file(payload) = node.kind else { continue }
                writer.append(u32: UInt32(payload.length))
            }
        }

        writer.append(raw: stringTable)
        writer.pad(count: dataOffset - writer.bytes.count, with: constants.paddingByte)
        writer.append(raw: payloads)

        return GoDData(byteStream: writer.bytes, byteOrder: byteOrder)
    }

    /// One past the last node nested under the directory at `offset`.
    ///
    /// The table is preorder, so a directory's descendants are exactly the
    /// run of nodes after it whose paths sit beneath its own — the run stops
    /// at the first that doesn't.
    private func subtreeEnd(ofDirectoryAt offset: Int, index: Int) -> Int {
        let prefix = nodes[offset].path + "/"
        var end = index + 1
        var scan = offset + 1
        while scan < nodes.count, nodes[scan].path.hasPrefix(prefix) {
            end += 1
            scan += 1
        }
        return end
    }
}

func align(_ value: Int, to boundary: Int) -> Int {
    guard boundary > 1 else { return value }
    let remainder = value % boundary
    return remainder == 0 ? value : value + (boundary - remainder)
}
