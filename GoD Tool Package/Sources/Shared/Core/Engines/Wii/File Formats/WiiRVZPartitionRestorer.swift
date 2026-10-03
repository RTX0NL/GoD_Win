//
//  WiiRVZPartitionRestorer.swift
//
//  The Wii half of a WIA/RVZ restore.
//
//  `RVZImage` lives in the Dolphin engine and knows the container: which
//  groups cover which region, how a payload is layered, where the bytes go.
//  What it deliberately does not carry is the Wii hash tree and AES layer,
//  so it asks for a `WiiPartitionRestorer` and this type supplies one.
//
//  The dependency runs this way round because `Wii` already depends on
//  `Dolphin`; putting the container in `Wii` instead would drag WIA's
//  GameCube support along with it, and moving `WiiCrypto` down into
//  `Dolphin` would put Wii disc knowledge in the GameCube layer.
//

import Foundation
import GoDFoundation
import Dolphin

public struct WiiRVZPartitionRestorer: WiiPartitionRestorer {

    public init() {}

    public func encryptGroup(
        decryptedUserData: [UInt8],
        titleKey: [UInt8],
        hashExceptions: [WIAExceptionList.Exception]
    ) throws -> [UInt8] {
        WiiCrypto.encryptGroup(
            decryptedUserData: decryptedUserData,
            titleKey: titleKey,
            hashOverrides: hashExceptions.map { (offset: Int($0.offset), hash: $0.hash) }
        )
    }
}
