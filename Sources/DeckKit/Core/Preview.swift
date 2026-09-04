//
//  Preview.swift
//  DeckKit
//
//  Looking at what was written, rather than at what was meant.
//

import Foundation

/// Renders slides to PNG.
///
/// Through Quick Look, which previews `.pptx` on any Mac — **no Keynote,
/// PowerPoint or LibreOffice needed**, measured on a machine with none of
/// them installed. Quick Look renders only the first slide of a file, so each
/// slide is rendered by writing a one-slide copy of the deck and previewing
/// that.
///
/// This matters more than it sounds. A PDF drawn from the same layout model
/// would only ever show what the model *intended*; this shows what a reader
/// will actually see, including PowerPoint's own line breaking, which is the
/// part a generator does not control.
public enum Preview {

    /// Writes one PNG per slide and returns their paths, in order.
    public static func render(
        deck: Deck,
        design: Design,
        canvas: Canvas = .sixteenByNine,
        images: [String: Data] = [:],
        width: Int = 1600,
        into directory: URL,
        namedBy name: String = "slide"
    ) throws -> [URL] {

        guard !deck.slides.isEmpty else { throw DeckError.empty }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        var rendered: [URL] = []
        let sizes = images.compactMapValues(ImageSize.of)
        for (index, slide) in deck.slides.enumerated() {
            /// A one-slide copy, given the WHOLE deck's context — its
            /// sections, its logo, its footer — or a divider would list one
            /// section and the agenda none.
            let single = Deck(title: deck.title, slides: [slide],
                              kickers: deck.kickers[index].map { [0: $0] } ?? [:],
                              logo: deck.logo, footer: deck.footer,
                              transition: deck.transition, builds: deck.builds)
            let context = deck.context(for: index, imageSizes: sizes)
            let file = work.appendingPathComponent(String(format: "%03d.pptx", index + 1))
            /// The real slide number, not 1. Each preview is a one-slide
            /// copy, so without this every rendered page showed "1" while
            /// the deck itself was numbered correctly — a preview that
            /// disagrees with the file is worse than none.
            try PPTX.data(deck: single, design: design, canvas: canvas,
                          images: images, firstSlideNumber: index + 1, contexts: [context])
                .write(to: file, options: .atomic)

            try quickLook(file, width: width, into: work)

            /// qlmanage names its output `<input>.png`, beside the input.
            let produced = work.appendingPathComponent(file.lastPathComponent + ".png")
            guard FileManager.default.fileExists(atPath: produced.path) else {
                throw DeckError.previewFailed("Quick Look produced nothing for slide \(index + 1)")
            }
            let destination = directory
                .appendingPathComponent(String(format: "%@-%02d.png", name, index + 1))
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: produced, to: destination)
            rendered.append(destination)
        }
        return rendered
    }

    private static func quickLook(_ file: URL, width: Int, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-t", "-s", String(width), "-o", directory.path, file.path]
        /// Silenced: qlmanage is chatty on stdout and writes plugin warnings
        /// to stderr even when it succeeds.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DeckError.previewFailed("qlmanage exited \(process.terminationStatus)")
        }
    }
}
