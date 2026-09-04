//
//  Design.swift
//  DeckKit
//
//  One type scale and one rhythm, not a magic number per slide.
//

import Foundation

/// How a deck looks.
///
/// The scale and the rhythm are the whole design. Sizes are **derived from a
/// base**, and vertical positions from a small set of bands, because the last
/// time a layout in this fleet was built from per-slot magic numbers the
/// verdict was that nothing lined up — and the fix was exactly this.
public struct Design: Codable, Sendable, Equatable {

    public var name: String
    public var description: String

    // MARK: Colour

    /// Background of an ordinary slide.
    public var background: String
    /// Background of title and section slides.
    public var featureBackground: String
    /// Headings.
    public var heading: String
    /// Body text.
    public var body: String
    /// Body text on a feature slide.
    public var featureBody: String
    /// Headings on a feature slide.
    public var featureHeading: String
    /// The one colour that is not grey.
    public var accent: String

    // MARK: Type

    public var headingFont: String
    public var bodyFont: String
    /// Body size in points. Every other size comes from this.
    public var base: Double
    /// How much bigger each step is. 1.25 is a major third.
    public var ratio: Double
    /// Extra leading as a multiple of the size.
    public var leading: Double
    public var headingBold: Bool

    // MARK: Rhythm

    /// Side margin as a fraction of the slide width.
    public var margin: Double
    /// Where the heading's baseline band begins, as a fraction of the height.
    public var headingTop: Double
    /// Space between the heading and what follows, in body multiples.
    public var gap: Double
    /// Whether to draw the short accent rule under a heading.
    public var rule: Bool
    /// Bullet character, or empty for none.
    public var bullet: String

    // MARK: The scale

    /// `base × ratio^step`, rounded to a whole point.
    ///
    /// Whole points because PowerPoint stores hundredths and shows halves,
    /// and a scale of 27.34 pt is a scale nobody can reason about or match
    /// by hand when they edit the file.
    public func size(_ step: Int) -> Double {
        (base * pow(ratio, Double(step))).rounded()
    }

    /// Named steps, so a layout reads as intent rather than arithmetic.
    public var titleSize: Double { size(5) }
    public var sectionSize: Double { size(4) }
    /// Two steps, not three. At three the heading was more than twice the
    /// body and dominated every slide it was on.
    public var headingSize: Double { size(2) }
    /// A statement slide has nothing else on it, so it is the largest thing
    /// in the deck after the title — it was set at heading size, which made
    /// the slide meant to be remembered look like an ordinary one.
    public var statementSize: Double { size(4) }
    public var bodySize: Double { size(0) }
    public var captionSize: Double { size(-1) }

    /// The height one line occupies, in points.
    ///
    /// Defined once because the layout and the overflow check must agree: if
    /// they differ, the checker reports problems the layout does not have, or
    /// misses the ones it does.
    public func lineHeight(_ size: Double) -> Double {
        size * (1 + leading * 0.6)
    }

    public static let fallback = Design(
        name: "plain", description: "Black on white, one accent.",
        background: "FFFFFF", featureBackground: "111111",
        heading: "111111", body: "3A3A3A",
        featureBody: "B8B8B8", featureHeading: "FFFFFF",
        accent: "2C6BED",
        headingFont: "Helvetica Neue", bodyFont: "Helvetica Neue",
        base: 20, ratio: 1.28, leading: 0.5, headingBold: true,
        margin: 0.075, headingTop: 0.13, gap: 1.4, rule: true, bullet: "—")
}
