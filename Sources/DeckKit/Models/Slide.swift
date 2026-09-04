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

    /// A picture beside points — on the left when it was written before
    /// them, on the right when after.
    case split(String, items: [Bullet], image: String, caption: String?, imageLeft: Bool, note: String?)

    /// A full-bleed photograph behind a title or a section heading.
    case cover(String, subtitle: String?, image: String, first: Bool)

    /// The deck's sections, listed.
    case agenda(String?)

    /// A native chart, from a table whose first column is the categories
    /// and every other column a series.
    case chart(String?, kind: ChartKind, rows: [[String]], header: Bool, note: String?)

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
        case let .split(text, _, _, _, _, _): return text
        case let .cover(text, _, _, _): return text
        case let .agenda(text): return text
        case let .chart(text, _, _, _, _): return text
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
        case .split: return "split"
        case .cover: return "cover"
        case .agenda: return "agenda"
        case .chart: return "chart"
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
        case let .split(a, items, _, caption, _, _):
            return [a] + items.map(\.text) + [caption].compactMap { $0 }
        case let .cover(a, b, _, _): return [a] + [b].compactMap { $0 }
        case let .agenda(a): return [a].compactMap { $0 }
        case let .chart(a, _, rows, _, _):
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
        case let .split(_, _, _, _, _, note), let .chart(_, _, _, _, note):
            return note
        default: return nil
        }
    }

    /// The picture the slide needs, if any.
    public var image: String? {
        switch self {
        case let .image(path, _, _), let .split(_, _, path, _, _, _), let .cover(_, _, path, _):
            return path
        default: return nil
        }
    }

    /// Whether this slide divides the deck — a section, or a cover that is
    /// not the first slide.
    public var isSection: Bool {
        switch self {
        case .section: return true
        case let .cover(_, _, _, first): return !first
        default: return false
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

/// A deck: slides, and what to call it.
public struct Deck: Sendable, Equatable {
    public var title: String?
    public var slides: [Slide]
    /// The small label above a slide's heading, by slide index.
    ///
    /// Kept beside the slides rather than inside each case, so a kicker can
    /// sit on any shape without every pattern match in the layout growing a
    /// field it ignores.
    public var kickers: [Int: String]
    /// A brand mark, bottom left of every slide.
    public var logo: String?
    /// A line at the foot of every content slide.
    public var footer: String?
    /// How slides give way to each other.
    public var transition: Transition
    /// Whether lists appear one point per click.
    public var builds: Bool

    public init(title: String? = nil, slides: [Slide], kickers: [Int: String] = [:],
                logo: String? = nil, footer: String? = nil,
                transition: Transition = .none, builds: Bool = false) {
        self.title = title
        self.slides = slides
        self.kickers = kickers
        self.logo = logo
        self.footer = footer
        self.transition = transition
        self.builds = builds
    }

    /// The section headings, in order — what an agenda lists.
    public var sections: [String] {
        slides.compactMap { $0.isSection ? $0.heading : nil }
    }

    /// Whether the deck has an agenda slide, which is what puts the
    /// section list on every divider.
    public var hasAgenda: Bool {
        slides.contains { if case .agenda = $0 { return true }; return false }
    }

    /// Every picture the deck needs: the logo and each slide's own.
    public var imagePaths: [String] {
        var seen: [String] = []
        for path in [logo].compactMap({ $0 }) + slides.compactMap(\.image) where !seen.contains(path) {
            seen.append(path)
        }
        return seen
    }

    /// What the layout needs to know about a slide beyond the slide itself.
    public func context(for index: Int,
                        imageSizes: [String: (width: Int, height: Int)] = [:]) -> Layout.Context {
        let slide = slides[index]
        let sections = self.sections
        let sectionIndex = slide.isSection
            ? slides[...index].filter(\.isSection).count - 1
            : nil
        return Layout.Context(kicker: kickers[index], logo: logo, footer: footer,
                              sections: sections, sectionIndex: sectionIndex,
                              hasAgenda: hasAgenda, imageSizes: imageSizes)
    }
}
