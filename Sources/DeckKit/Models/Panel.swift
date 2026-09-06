//
//  Panel.swift
//  DeckKit
//
//  The modern vocabulary: gradients, rounded cards, soft shadows.
//

//

import Foundation

/// A filled shape — flat, rounded, translucent or shadowed.
///
/// Every one of these is in OOXML and none of it was used at first, which is
/// most of why the first decks looked a decade old: flat fills, square
/// corners, no depth and no transparency.
public struct Panel: Codable, Sendable, Equatable {

    /// Six-digit hex, no `#`.
    public var fill: String
    /// 0–1. Below 1 the card sits *on* the background rather than covering it.
    public var fillAlpha: Double
    /// Six-digit hex, or nil for no border.
    public var border: String?
    /// 0–1. Below 1 the border softens into the ground behind it.
    public var borderAlpha: Double
    /// In points. A hairline at 1 is what reads as modern; 3 reads as a box.
    public var borderWidth: Double
    /// 0–0.5 of the shorter side. PowerPoint's own adjust is a percentage.
    public var radius: Double
    /// Whether the card casts a shadow — the cheapest way to give it depth.
    public var shadow: Bool

    public init(fill: String, fillAlpha: Double = 1, border: String? = nil,
                borderAlpha: Double = 1, borderWidth: Double = 1,
                radius: Double = 0, shadow: Bool = false) {
        self.fill = fill
        self.fillAlpha = fillAlpha
        self.border = border
        self.borderAlpha = borderAlpha
        self.borderWidth = borderWidth
        self.radius = radius
        self.shadow = shadow
    }

    /// A plain rectangle of one colour.
    public static func flat(_ colour: String) -> Panel {
        Panel(fill: colour, fillAlpha: 1, radius: 0, shadow: false)
    }
}
