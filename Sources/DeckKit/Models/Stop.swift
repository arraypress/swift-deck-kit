//
//  Stop.swift
//  DeckKit
//
//  The modern vocabulary: gradients, rounded cards, soft shadows.
//

//

import Foundation

/// One stop in a gradient.
public struct Stop: Codable, Sendable, Equatable {
    /// `rrggbb`, no hash.
    public let colour: String
    /// 0–1 along the gradient.
    public let position: Double

    public init(colour: String, position: Double) {
        self.colour = colour
        self.position = position
    }
}
