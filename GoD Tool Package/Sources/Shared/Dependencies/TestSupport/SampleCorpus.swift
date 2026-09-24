//
//  SampleCorpus.swift
//
//  Where the real-file samples live. Several format tests read one sample
//  per case — a C8 texture, an animated ATX, a flash menu — out of a legacy
//  GoD tool dump of XD's game files. They each carried the same absolute
//  path, and when that folder was renamed every one of them started
//  skipping silently, which is the failure mode corpus tests are supposed to
//  avoid: a test that skips proves nothing and says so quietly.
//
//  One name for the root, one environment override per corpus, and a
//  missing sample still skips rather than fails — a machine without the
//  dump should not be blocked.
//

import Foundation

public enum SampleCorpus {

    /// A legacy GoD tool dump of Pokémon XD's game files: one folder per
    /// archive, holding the members the old tool extracted.
    /// Override with `GODDESS_XD_FILES`.
    public static var xdGameFiles: String {
        ProcessInfo.processInfo.environment["GODDESS_XD_FILES"]
            ?? NSHomeDirectory() + "/Documents/GoD Tool/XD GoD Tool dumped/Game Files"
    }

    /// `relative` resolved inside `xdGameFiles`.
    public static func xdGameFile(_ relative: String) -> String {
        xdGameFiles + "/" + relative
    }
}
