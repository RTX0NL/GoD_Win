import Foundation
import Structs

extension WiiEngine.Structs.Defaults {
    /// Partition info table header at 0x40000.
    /// Contains up to 4 partition table groups.
    /// Each group has a count and an offset (shifted right by 2) to its entries.
    static let wiiPartitionTableHeader = StructMap(
        name: "WiiPartitionTableHeader",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "partition_count_1"),
            .uint32(name: "partition_table_offset_1", description: "Offset >> 2 to partition info entries for table 1"),
            .uint32(name: "partition_count_2"),
            .uint32(name: "partition_table_offset_2"),
            .uint32(name: "partition_count_3"),
            .uint32(name: "partition_table_offset_3"),
            .uint32(name: "partition_count_4"),
            .uint32(name: "partition_table_offset_4"),
        ]
    )

    /// Individual partition info entry (8 bytes each).
    static let wiiPartitionInfo = StructMap(
        name: "WiiPartitionInfo",
        wordSize: 4,
        alignmentStyle: .none,
        properties: [
            .uint32(name: "partition_offset", description: "Offset >> 2 to the partition data"),
            .uint32(name: "partition_type", description: "0=DATA, 1=UPDATE, 2=CHANNEL"),
        ]
    )
}
