//
//  PDF.swift
//  DeckKit
//
//  The deck as a PDF — rendered from the file, not from the model.
//

import Foundation

/// A PDF twin of a `.pptx`, made by LibreOffice.
///
/// From the written file, so it shows what a reader gets — the same test
/// the previews pass. LibreOffice is optional: `brew install --cask
/// libreoffice` puts it where this looks.
public enum PDF {

    /// LibreOffice's command-line binary, if it is installed.
    public static var libreOffice: URL? {
        [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            NSHomeDirectory() + "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/opt/homebrew/bin/soffice",
            "/usr/local/bin/soffice",
        ].map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Renders `pptx` to `destination`, replacing it. Returns the size.
    ///
    /// **Headless LibreOffice on macOS resolves none of the system fonts by
    /// itself** — measured: every face fell to Liberation or a serif — so it
    /// is handed a fontconfig file naming the system font folders, and a
    /// profile of its own so it neither touches nor waits for a running
    /// copy.
    @discardableResult
    public static func render(_ pptx: URL, to destination: URL) throws -> Int {
        guard let soffice = libreOffice else { throw DeckError.noLibreOffice }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        /// The font cache and LibreOffice's profile persist between runs:
        /// scanning every system font and building a profile is most of a
        /// first conversion's ten seconds, and neither changes.
        let caches = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                      ?? FileManager.default.temporaryDirectory).appendingPathComponent("deck")
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let fonts = work.appendingPathComponent("fonts.conf")
        try fontConfiguration(cache: caches.appendingPathComponent("fontconfig").path)
            .write(to: fonts, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = soffice
        process.arguments = ["--headless", "-env:UserInstallation=file://\(caches.path)/libreoffice",
                             "--convert-to", "pdf", "--outdir", work.path, pptx.path]
        var environment = ProcessInfo.processInfo.environment
        environment["FONTCONFIG_FILE"] = fonts.path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw DeckError.pdfFailed("could not start LibreOffice: \(error.localizedDescription)") }
        process.waitUntilExit()

        let produced = work.appendingPathComponent(pptx.deletingPathExtension().lastPathComponent + ".pdf")
        guard FileManager.default.fileExists(atPath: produced.path) else {
            throw DeckError.pdfFailed("LibreOffice exited \(process.terminationStatus) and wrote nothing")
        }
        try? FileManager.default.removeItem(at: destination)
        do { try FileManager.default.moveItem(at: produced, to: destination) }
        catch { throw DeckError.cannotWrite(destination.path) }
        return (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
    }

    /// The font folders macOS keeps, plus LibreOffice's own.
    static func fontConfiguration(cache: String) -> String {
        let folders = [
            "/System/Library/Fonts", "/System/Library/Fonts/Supplemental", "/Library/Fonts",
            NSHomeDirectory() + "/Library/Fonts",
            "/Applications/LibreOffice.app/Contents/Resources/fonts/truetype",
        ]
        return """
            <?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd">
            <fontconfig>\(folders.map { "<dir>\($0)</dir>" }.joined())<cachedir>\(cache)</cachedir></fontconfig>
            """
    }
}
