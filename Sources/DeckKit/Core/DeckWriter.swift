//
//  DeckWriter.swift
//  DeckKit
//
//  Markdown in, PowerPoint out.
//

import Foundation

/// Building a deck from text.
public enum DeckWriter {

    /// The image formats PowerPoint reads.
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif"]

    /// Reads the pictures a deck refers to.
    ///
    /// Separate from writing so a missing picture is reported **before**
    /// anything is written — a half-built deck with a hole where a diagram
    /// should be is worse than a refusal.
    public static func images(for deck: Deck, relativeTo base: URL) throws -> [String: Data] {
        var found: [String: Data] = [:]
        /// The logo and every slide's picture — a cover, a split, a plain
        /// image — through one door.
        for path in deck.imagePaths {
            let url = path.hasPrefix("/")
                ? URL(fileURLWithPath: path)
                : base.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw DeckError.missingImage(path)
            }
            guard imageExtensions.contains(url.pathExtension.lowercased()) else {
                throw DeckError.unsupportedImage(path)
            }
            found[path] = try Data(contentsOf: url)
        }
        return found
    }

    /// Writes the `.pptx`.
    @discardableResult
    public static func write(
        _ deck: Deck,
        design: Design,
        canvas: Canvas = .sixteenByNine,
        images: [String: Data] = [:],
        embed: [(face: Embedding.Face, data: Data)] = [],
        embedTypeface: String = Embedding.bundledTypeface,
        to url: URL
    ) throws -> Int {
        let data = try PPTX.data(deck: deck, design: design, canvas: canvas,
                                 images: images, embed: embed, embedTypeface: embedTypeface)
        do { try data.write(to: url, options: .atomic) }
        catch { throw DeckError.cannotWrite(url.path) }
        return data.count
    }
}
