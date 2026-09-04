//
//  Resources.swift
//  DeckKit
//
//  Where the designs and the bundled font actually are.
//

import Foundation

/// The kit's resource bundle, found the way an installed tool needs.
///
/// SwiftPM's generated `Bundle.module` looks beside the path the executable
/// was **invoked** by. Homebrew installs the binary and its bundle in
/// `libexec/` and puts a symlink in `bin/`, so the accessor looked in `bin/`,
/// found nothing, and the installed tool trapped on its first `deck make` —
/// after every release probe had passed, because the probes run the binary
/// where it was built. This looks beside the executable's real path first.
enum Resources {

    static let bundle: Bundle = {
        let name = "DeckKit_DeckKit.bundle"
        var candidates: [URL] = []
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.resolvingSymlinksInPath().deletingLastPathComponent()
                .appendingPathComponent(name))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(name))
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path), let bundle = Bundle(url: url) {
                return bundle
            }
        }
        /// The build tree, and the trap with SwiftPM's own message when
        /// there is genuinely no bundle anywhere.
        return Bundle.module
    }()
}
