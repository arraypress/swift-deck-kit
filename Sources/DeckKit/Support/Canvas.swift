//
//  Canvas.swift
//  DeckKit
//
//  OOXML measures in English Metric Units: 914,400 to the inch.
//

import Foundation

/// The slide, and how to place things on it.
public struct Canvas: Sendable, Equatable {

    /// 914,400 EMU to the inch — the unit every OOXML coordinate is in.
    public static let perInch = 914_400.0

    /// Slide width in EMU.
    public let width: Int
    /// Slide height in EMU.
    public let height: Int

    /// 13⅓ × 7½ inches, which is what 16:9 means in PowerPoint.
    public static let sixteenByNine = Canvas(width: 12_192_000, height: 6_858_000)
    /// 10 × 7½ inches, for a deck that has to project on old hardware.
    public static let fourByThree = Canvas(width: 9_144_000, height: 6_858_000)

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// A fraction of the width, as EMU.
    public func across(_ fraction: Double) -> Int { Int(Double(width) * fraction) }
    /// A fraction of the height, as EMU.
    public func down(_ fraction: Double) -> Int { Int(Double(height) * fraction) }
    /// Points to EMU. A point is 1/72 inch.
    public static func points(_ value: Double) -> Int { Int(value / 72 * perInch) }
}

extension Int {
    /// The value as a quoted XML attribute.
    var quoted: String { "\"\(self)\"" }
}
