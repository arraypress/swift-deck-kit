//
//  Slide.swift
//  DeckKit
//

import Foundation

/// One slide, as content rather than as layout.
///
/// The design decides where things go; this only says what they are. Keeping
/// them apart is what lets the same deck take a different design without the
/// author touching a word of it.
public enum Slide: Sendable {

    /// The opening slide.
    case title(String, subtitle: String?)

    /// A divider announcing what follows.
    ///
    /// `subtitle` is the line under the heading, on the slide. `note` is for
    /// the presenter only — they were one field, so a section's subtitle was
    /// shown AND written into the speaker notes, and a `???` note on a
    /// section was impossible to write.
    case section(String, subtitle: String?, note: String?)

    /// A heading and some points.
    case points(String, items: [Bullet], note: String?)

    /// A heading and a paragraph.
    case prose(String, body: String, note: String?)

    /// One sentence, set large. The slide people remember.
    case statement(String, attribution: String?)

    /// A quotation.
    case quote(String, attribution: String?)

    /// A picture, with an optional caption.
    case image(String, caption: String?, heading: String?)

    /// Two columns of points under one heading.
    case columns(String, left: [Bullet], right: [Bullet], note: String?)

    /// Figures with labels, set large. The shape a number deserves.
    case stat(String?, figures: [(figure: String, label: String)], note: String?)

    /// Panels side by side, each with a title and a line.
    case cards(String?, panels: [(title: String, body: String)], note: String?)

    /// Rows and columns. The first row is the header when there was one.
    case table(String?, rows: [[String]], header: Bool)

    /// The heading, for a contents listing and for `deck check`.
    public var heading: String? {
        switch self {
        case let .title(text, _), let .points(text, _, _),
             let .prose(text, _, _): return text
        case let .section(text, _, _): return text
        case let .statement(text, _), let .quote(text, _): return text
        case let .image(_, _, heading): return heading
        case let .columns(text, _, _, _): return text
        case let .stat(text, _, _), let .cards(text, _, _): return text
        case let .table(text, _, _): return text
        }
    }

    /// A short name for the shape, for reports.
    public var kind: String {
        switch self {
        case .title: return "title"
        case .section: return "section"
        case .points: return "points"
        case .prose: return "prose"
        case .statement: return "statement"
        case .quote: return "quote"
        case .image: return "image"
        case .columns: return "columns"
        case .stat: return "stat"
        case .cards: return "cards"
        case .table: return "table"
        }
    }

    /// Every piece of text on the slide, for length checks.
    public var texts: [String] {
        switch self {
        case let .title(a, b): return [a] + [b].compactMap { $0 }
        case let .section(a, b, _): return [a] + [b].compactMap { $0 }
        case let .points(a, items, _): return [a] + items.map(\.text)
        case let .prose(a, body, _): return [a, body]
        case let .statement(a, b), let .quote(a, b): return [a] + [b].compactMap { $0 }
        case let .image(_, caption, heading): return [caption, heading].compactMap { $0 }
        case let .columns(a, left, right, _): return [a] + (left + right).map(\.text)
        case let .stat(a, figures, _):
            return [a].compactMap { $0 } + figures.flatMap { [$0.figure, $0.label] }
        case let .cards(a, panels, _):
            return [a].compactMap { $0 } + panels.flatMap { [$0.title, $0.body] }
        case let .table(a, rows, _):
            return [a].compactMap { $0 } + rows.flatMap { $0 }
        }
    }

    /// Presenter notes, when the author wrote any.
    public var note: String? {
        switch self {
        case let .points(_, _, note), let .prose(_, _, note),
             let .columns(_, _, _, note): return note
        /// Every shape that can carry one. They were missing here, so a
        /// `???` written under a stat or a card block was parsed and then
        /// silently dropped — the same bug as notes never being written at
        /// all, one level in.
        case let .section(_, _, note), let .stat(_, _, note), let .cards(_, _, note):
            return note
        default: return nil
        }
    }
}

extension Slide: Equatable {
    /// Compared on what is written, since the tuple payloads block the
    /// synthesised version and the texts are what a test actually asserts.
    public static func == (lhs: Slide, rhs: Slide) -> Bool {
        lhs.kind == rhs.kind && lhs.heading == rhs.heading && lhs.texts == rhs.texts
    }
}

/// A small label above a heading — the most recognisable single mark of a
/// modern deck, and the cheapest.
public struct Kicked: Sendable, Equatable {
    public let kicker: String?
    public let slide: Slide

    public init(kicker: String?, slide: Slide) {
        self.kicker = kicker
        self.slide = slide
    }
}

/// A deck: slides, and what to call it.
public struct Deck: Sendable, Equatable {
    public var title: String?
    public var slides: [Slide]

    public init(title: String? = nil, slides: [Slide]) {
        self.title = title
        self.slides = slides
    }
}
