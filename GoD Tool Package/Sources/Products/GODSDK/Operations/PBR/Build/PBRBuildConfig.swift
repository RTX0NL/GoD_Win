import GoDFoundation

extension PBROps {
    struct BuildConfig: Codable {
        enum Operations: Codable {
            /// Repacks the unpacked project tree back into the disc's FSYS
            /// archives (including the typed `common.fsys`/`deck.fsys` tables,
            /// reconstructed from their CSV/header via the engine structs) and
            /// writes them into the DATA partition's `files/`. A following
            /// `wiiBuild`/`encryptISO` re-encrypts the disc.
            case packPBR(
                unpackedFolder: Folder,
                fstFolder: Folder,
                overwrite: Bool,
                geniusSonorityEngine: Folder,
                pbrEngine: Folder,
                engines: [Folder]
            )
        }
        let operations: [OperationConfig<Operations>]
    }
}
