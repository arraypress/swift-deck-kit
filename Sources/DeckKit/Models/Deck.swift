//
//  Deck.swift
//  DeckKit
//

//

import Foundation

/// A deck: slides, and what to call it.
public struct Deck: Sendable, Equatable {
    /// The deck's title, shown on the title slide.
    public var title: String?
    /// Every slide, in order.
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
