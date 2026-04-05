import Foundation
import Structs

extension WiiEngine.Structs.Defaults {
    /// Partition header, located at the start of each partition.
    /// Contains offsets to ticket, TMD, cert chain, H3, and encrypted data.
    static let wiiPartitionHeader = StructMap(
        name: "WiiPartitionHeader",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "tmd_size"),
            .uint32(name: "tmd_offset", description: "Offset >> 2 relative to partition start"),
            .uint32(name: "cert_chain_size"),
            .uint32(name: "cert_chain_offset", description: "Offset >> 2 relative to partition start"),
            .uint32(name: "h3_table_offset", description: "Offset >> 2 relative to partition start"),
            .uint32(name: "data_offset", description: "Offset >> 2 relative to partition start"),
            .uint32(name: "data_size", description: "Size >> 2 of encrypted partition data"),
        ]
    )
}
