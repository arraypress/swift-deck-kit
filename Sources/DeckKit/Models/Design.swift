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

    /// Spelled out because a custom `init(from:)` suppresses the memberwise
    /// one Swift would otherwise synthesise.
    public init(name: String, description: String, background: String,
                featureBackground: String, heading: String, body: String,
                featureBody: String, featureHeading: String, accent: String,
                headingFont: String, bodyFont: String, base: Double, ratio: Double,
                leading: Double, headingBold: Bool, margin: Double, headingTop: Double,
                gap: Double, rule: Bool, bullet: String,
                gradient: [Stop]? = nil, bodyGradient: [Stop]? = nil,
                gradientAngle: Double = 135, cornerRadius: Double = 0,
                card: Panel? = nil, headingTracking: Double = 0,
                kickerTracking: Double = 1.2, lineSpacing: Double = 1,
                kickerPill: Panel? = nil, kickerColour: String? = nil,
                slideNumbers: Bool = false) {
        self.name = name
        self.description = description
        self.background = background
        self.featureBackground = featureBackground
        self.heading = heading
        self.body = body
        self.featureBody = featureBody
        self.featureHeading = featureHeading
        self.accent = accent
        self.headingFont = headingFont
        self.bodyFont = bodyFont
        self.base = base
        self.ratio = ratio
        self.leading = leading
        self.headingBold = headingBold
        self.margin = margin
        self.headingTop = headingTop
        self.gap = gap
        self.rule = rule
        self.bullet = bullet
        self.gradient = gradient
        self.bodyGradient = bodyGradient
        self.gradientAngle = gradientAngle
        self.cornerRadius = cornerRadius
        self.card = card
        self.headingTracking = headingTracking
        self.kickerTracking = kickerTracking
        self.lineSpacing = lineSpacing
        self.kickerPill = kickerPill
        self.kickerColour = kickerColour ?? accent
        self.slideNumbers = slideNumbers
    }

    /// Decoded with defaults, so a design written before the modern keys
    /// existed still loads — the four restrained designs predate them.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try box.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        name = try box.decode(String.self, forKey: .name)
        description = try value(.description, "")
        background = try value(.background, "FFFFFF")
        featureBackground = try value(.featureBackground, "111111")
        heading = try value(.heading, "111111")
        body = try value(.body, "3A3A3A")
        featureBody = try value(.featureBody, "B8B8B8")
        featureHeading = try value(.featureHeading, "FFFFFF")
        accent = try value(.accent, "2C6BED")
        headingFont = try value(.headingFont, "Helvetica Neue")
        bodyFont = try value(.bodyFont, "Helvetica Neue")
        base = try value(.base, 22.0)
        ratio = try value(.ratio, 1.3)
        leading = try value(.leading, 0.65)
        headingBold = try value(.headingBold, true)
        margin = try value(.margin, 0.075)
        headingTop = try value(.headingTop, 0.11)
        gap = try value(.gap, 1.5)
        rule = try value(.rule, true)
        bullet = try value(.bullet, "—")
        gradient = try box.decodeIfPresent([Stop].self, forKey: .gradient)
        bodyGradient = try box.decodeIfPresent([Stop].self, forKey: .bodyGradient)
        gradientAngle = try value(.gradientAngle, 135.0)
        cornerRadius = try value(.cornerRadius, 0.0)
        card = try box.decodeIfPresent(Panel.self, forKey: .card)
        headingTracking = try value(.headingTracking, 0.0)
        kickerTracking = try value(.kickerTracking, 1.2)
        lineSpacing = try value(.lineSpacing, 1.0)
        kickerPill = try box.decodeIfPresent(Panel.self, forKey: .kickerPill)
        kickerColour = try value(.kickerColour, accent)
        slideNumbers = try value(.slideNumbers, false)
    }


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

    // MARK: The modern half

    /// Stops for a feature slide's background. Nil for a flat colour.
    public var gradient: [Stop]?
    /// Stops for an ordinary slide's background.
    public var bodyGradient: [Stop]?
    /// Gradient direction in degrees, clockwise from "left to right".
    public var gradientAngle: Double
    /// Corner radius for cards, 0–0.5 of the shorter side.
    public var cornerRadius: Double
    /// The card a stat or a panel sits on.
    public var card: Panel?
    /// Letter-spacing for headings, in points. **Negative** for large type —
    /// which is the single change that most separates a modern heading from
    /// a dated one.
    public var headingTracking: Double
    /// Letter-spacing for a kicker, in points. Positive; small caps want air.
    public var kickerTracking: Double
    /// Line spacing as a multiple. Below 1 tightens large headings.
    public var lineSpacing: Double
    /// The pill behind a kicker, if the design uses one.
    public var kickerPill: Panel?
    /// Colour of kicker text.
    public var kickerColour: String
    /// Whether ordinary slides carry their number.
    public var slideNumbers: Bool

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
        /// `lineSpacing` is part of it: a design that tightens display type
        /// to 0.92 genuinely needs 8% less room, and a checker that ignored
        /// it flagged the title slide of every modern design.
        size * (1 + leading * 0.6) * lineSpacing
    }

    public static let fallback = Design(
        name: "plain", description: "Black on white, one accent.",
        background: "FFFFFF", featureBackground: "111111",
        heading: "111111", body: "3A3A3A",
        featureBody: "B8B8B8", featureHeading: "FFFFFF",
        accent: "2C6BED",
        headingFont: "Helvetica Neue", bodyFont: "Helvetica Neue",
        base: 20, ratio: 1.28, leading: 0.5, headingBold: true,
        margin: 0.075, headingTop: 0.13, gap: 1.4, rule: true, bullet: "—",
        gradient: nil, bodyGradient: nil, gradientAngle: 135, cornerRadius: 0,
        card: nil, headingTracking: 0, kickerTracking: 1.2, lineSpacing: 1,
        kickerPill: nil, kickerColour: "2C6BED", slideNumbers: false)
}
