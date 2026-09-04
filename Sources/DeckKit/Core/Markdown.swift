//
//  Markdown.swift
//  DeckKit
//
//  The slide grammar: what a heading means, and where a slide ends.
//

import Foundation

/// Reads a deck out of Markdown.
///
/// The grammar is small on purpose — an author should be able to hold it in
/// their head:
///
/// ```
/// # Section divider
/// ## Slide heading
/// - a point
/// > a quote
/// ! a statement, set large
/// ![](picture.png)
/// ??? presenter notes
/// ---
/// ```
///
/// The **first** `#` becomes the title slide when nothing follows it but a
/// line of prose, because that is how everybody writes the top of a document
/// and making them learn otherwise buys nothing.
public enum Markdown {

    public static func deck(from text: String) -> Deck {
        var slides: [Slide] = []
        var title: String?

        for block in blocks(in: text) {
            guard let slide = self.slide(from: block, isFirst: slides.isEmpty) else { continue }
            if case let .title(text, _) = slide, title == nil { title = text }
            slides.append(slide)
        }
        return Deck(title: title, slides: slides)
    }

    /// Splits on `---` **and** on any heading, so an author who never types a
    /// separator still gets one slide per heading rather than one long slide.
    static func blocks(in text: String) -> [[String]] {
        var blocks: [[String]] = []
        var current: [String] = []

        func flush() {
            if current.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                blocks.append(current)
            }
            current = []
        }

        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" {
                flush()
                continue
            }
            /// A heading, a statement and a quote each begin a slide, the
            /// same way. Only splitting on headings meant a `!` statement and
            /// a `>` quote written under one heading all landed in a single
            /// block, and `slide(from:)` returned ONE of them — silently
            /// dropping the rest of the author's words, which is the one
            /// thing a converter must never do.
            let continuingQuote = trimmed.hasPrefix(">")
                && current.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
            if starts(trimmed), !current.isEmpty, !isAttribution(trimmed), !continuingQuote { flush() }
            current.append(line)
        }
        flush()
        return blocks
    }

    /// Whether a line begins a new slide.
    static func starts(_ line: String) -> Bool {
        line.hasPrefix("#") || line.hasPrefix(">") || line.hasPrefix("![")
            || (line.hasPrefix("!") && !line.hasPrefix("!["))
    }

    /// An attribution belongs to the quote or statement above it, not to a
    /// slide of its own.
    static func isAttribution(_ line: String) -> Bool {
        line.hasPrefix("\u{2014} ") || line.hasPrefix("-- ")
    }

    static func slide(from block: [String], isFirst: Bool) -> Slide? {
        var heading: String?
        var level = 0
        var points: [String] = []
        var rightPoints: [String] = []
        var inRightColumn = false
        var prose: [String] = []
        var quote: [String] = []
        var statement: String?
        var attribution: String?
        var image: (path: String, caption: String?)?
        var notes: [String] = []

        for raw in block {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("???") {
                notes.append(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("##") {
                heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                level = 2
            } else if line.hasPrefix("#") {
                heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                level = 1
            } else if line.hasPrefix("![") {
                /// `![caption](path)`
                let caption = line.dropFirst(2).prefix { $0 != "]" }
                if let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close {
                    image = (String(line[line.index(after: open)..<close]),
                             caption.isEmpty ? nil : String(caption))
                }
            } else if line.hasPrefix(">") {
                quote.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("!") {
                statement = line.dropFirst().trimmingCharacters(in: .whitespaces)
            } else if line == "|" {
                /// A lone pipe splits the points into two columns. Without a
                /// grammar for it the `columns` layout could never fire, and
                /// a comparison came out as one long list.
                inRightColumn = true
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                let item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if inRightColumn { rightPoints.append(item) } else { points.append(item) }
            } else if line.hasPrefix("— ") || line.hasPrefix("-- ") {
                /// An attribution line under a quote or statement.
                attribution = line.drop(while: { $0 == "—" || $0 == "-" })
                    .trimmingCharacters(in: .whitespaces)
            } else {
                prose.append(line)
            }
        }

        let note = notes.isEmpty ? nil : notes.joined(separator: " ")

        if let image {
            return .image(image.path, caption: image.caption, heading: heading)
        }
        if !quote.isEmpty {
            return .quote(quote.joined(separator: " "), attribution: attribution ?? prose.first)
        }
        if let statement {
            return .statement(statement, attribution: attribution ?? prose.first)
        }
        guard let heading else {
            /// A block of prose with no heading at all is still worth a
            /// slide — dropping the author's words silently is the one thing
            /// a converter must never do.
            guard !prose.isEmpty else { return nil }
            return .statement(prose.joined(separator: " "), attribution: attribution)
        }
        if !points.isEmpty {
            return rightPoints.isEmpty
                ? .points(heading, items: points, note: note)
                : .columns(heading, left: points, right: rightPoints, note: note)
        }
        if level == 1 {
            /// The first `#` with a line under it is how everyone writes the
            /// top of a document.
            return isFirst
                ? .title(heading, subtitle: prose.first)
                : .section(heading, note: prose.first ?? note)
        }
        if !prose.isEmpty {
            return .prose(heading, body: prose.joined(separator: " "), note: note)
        }
        return .section(heading, note: note)
    }
}
