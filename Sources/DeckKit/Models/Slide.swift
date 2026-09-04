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
public enum Slide: Sendable, Equatable {

    /// The opening slide.
    case title(String, subtitle: String?)

    /// A divider announcing what follows.
    case section(String, note: String?)

    /// A heading and some points.
    case points(String, items: [String], note: String?)

    /// A heading and a paragraph.
    case prose(String, body: String, note: String?)

    /// One sentence, set large. The slide people remember.
    case statement(String, attribution: String?)

    /// A quotation.
    case quote(String, attribution: String?)

    /// A picture, with an optional caption.
    case image(String, caption: String?, heading: String?)

    /// Two columns of points under one heading.
    case columns(String, left: [String], right: [String], note: String?)

    /// The heading, for a contents listing and for `deck check`.
    public var heading: String? {
        switch self {
        case let .title(text, _), let .section(text, _), let .points(text, _, _),
             let .prose(text, _, _): return text
        case let .statement(text, _), let .quote(text, _): return text
        case let .image(_, _, heading): return heading
        case let .columns(text, _, _, _): return text
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
        }
    }

    /// Every piece of text on the slide, for length checks.
    public var texts: [String] {
        switch self {
        case let .title(a, b): return [a] + [b].compactMap { $0 }
        case let .section(a, b): return [a] + [b].compactMap { $0 }
        case let .points(a, items, _): return [a] + items
        case let .prose(a, body, _): return [a, body]
        case let .statement(a, b), let .quote(a, b): return [a] + [b].compactMap { $0 }
        case let .image(_, caption, heading): return [caption, heading].compactMap { $0 }
        case let .columns(a, left, right, _): return [a] + left + right
        }
    }

    /// Presenter notes, when the author wrote any.
    public var note: String? {
        switch self {
        case let .section(_, note), let .points(_, _, note),
             let .prose(_, _, note), let .columns(_, _, _, note): return note
        default: return nil
        }
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
