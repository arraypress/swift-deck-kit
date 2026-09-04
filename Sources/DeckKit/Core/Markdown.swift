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
            /// A picture written straight under a heading belongs to that
            /// heading's slide — splitting there threw the heading away, and
            /// a captioned diagram with no title is not what the author
            /// typed. Anything else in the block, and the picture gets a
            /// slide of its own.
            let underOnlyAHeading = trimmed.hasPrefix("![")
                && current.allSatisfy { line in
                    let text = line.trimmingCharacters(in: .whitespaces)
                    return text.isEmpty || text.hasPrefix("#")
                }
            if starts(trimmed), !current.isEmpty, !isAttribution(trimmed),
               !continuingQuote, !underOnlyAHeading { flush() }
            current.append(line)
        }
        flush()
        return blocks
    }

    /// A list item: `- point`, `1. point`, or either indented under another.
    ///
    /// Indentation is counted in **twos**, which is what a Markdown editor
    /// inserts, and capped at four levels — deeper than that is an outline,
    /// not a slide.
    static func bullet(_ raw: String) -> Bullet? {
        let indent = raw.prefix { $0 == " " || $0 == "\t" }
            .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let line = raw.trimmingCharacters(in: .whitespaces)
        let level = min(4, indent / 2)

        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return Bullet(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces),
                          level: level)
        }
        /// `1.` or `1)` — the number itself is thrown away, because
        /// PowerPoint counts them and an author who renumbers by hand always
        /// ends up with two number sevens.
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3 {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return Bullet(String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces),
                              level: level, numbered: true)
            }
        }
        return nil
    }

    /// `| a | b |` — a row with at least two cells.
    ///
    /// Checked before the lone `|` that splits columns, and *after* it in the
    /// caller, so a bare pipe still means two columns and a pipe with content
    /// round it means a table.
    static func isRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.dropFirst().contains("|")
    }

    /// `|---|:--:|` — the separator under a header row.
    static func isRule(_ line: String) -> Bool {
        guard isRow(line) else { return false }
        return cells(line).allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
        }
    }

    /// The cells of a row, without the outer pipes.
    static func cells(_ line: String) -> [String] {
        var text = Substring(line)
        if text.hasPrefix("|") { text = text.dropFirst() }
        if text.hasSuffix("|") { text = text.dropLast() }
        return text.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
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
        var points: [Bullet] = []
        var figures: [(figure: String, label: String)] = []
        var panels: [(title: String, body: String)] = []
        var tableRows: [[String]] = []
        var tableHasHeader = false
        var rightPoints: [Bullet] = []
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
            } else if line.hasPrefix("= ") {
                /// `= 91 | tools installed` — a figure and what it counts.
                /// The pipe separates them because a label legitimately
                /// contains every other punctuation mark going.
                let parts = line.dropFirst(2).split(separator: "|", maxSplits: 1)
                figures.append((figure: parts[0].trimmingCharacters(in: .whitespaces),
                                label: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""))
            } else if line.hasPrefix(":: ") {
                /// `:: Title | a line about it` — one card.
                let parts = line.dropFirst(3).split(separator: "|", maxSplits: 1)
                panels.append((title: parts[0].trimmingCharacters(in: .whitespaces),
                               body: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""))
            } else if isRule(line) {
                /// `|---|---|` — the line that turns the row above it into a
                /// header. It carries no data of its own.
                tableHasHeader = !tableRows.isEmpty
            } else if isRow(line) {
                tableRows.append(cells(line))
            } else if line == "|" {
                /// A lone pipe splits the points into two columns. Without a
                /// grammar for it the `columns` layout could never fire, and
                /// a comparison came out as one long list.
                inRightColumn = true
            } else if let bullet = Self.bullet(raw) {
                if inRightColumn { rightPoints.append(bullet) } else { points.append(bullet) }
            } else if line.hasPrefix("— ") || line.hasPrefix("-- ") {
                /// An attribution line under a quote or statement.
                attribution = line.drop(while: { $0 == "—" || $0 == "-" })
                    .trimmingCharacters(in: .whitespaces)
            } else if !points.isEmpty || !rightPoints.isEmpty {
                /// Markdown's lazy continuation: a wrapped list item runs on
                /// to the next line. Without this the remainder was neither a
                /// bullet nor usable prose — a block with points ignores
                /// prose entirely — so half the sentence simply vanished.
                if inRightColumn, !rightPoints.isEmpty {
                    rightPoints[rightPoints.count - 1].text += " " + line
                } else if !points.isEmpty {
                    points[points.count - 1].text += " " + line
                }
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
        /// Before the heading guard: a stat or a card block is a slide in its
        /// own right, and checking after it meant `= 91` on a line by itself
        /// produced no slide at all.
        if !tableRows.isEmpty { return .table(heading, rows: tableRows, header: tableHasHeader) }
        if !figures.isEmpty { return .stat(heading, figures: figures, note: note) }
        if !panels.isEmpty { return .cards(heading, panels: panels, note: note) }

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
                : .section(heading, subtitle: prose.first, note: note)
        }
        if !prose.isEmpty {
            return .prose(heading, body: prose.joined(separator: " "), note: note)
        }
        return .section(heading, subtitle: nil, note: note)
    }
}
