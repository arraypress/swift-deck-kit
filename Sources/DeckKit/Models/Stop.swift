//
//  Stop.swift
//  DeckKit
//
//  The modern vocabulary: gradients, rounded cards, soft shadows.
//

//

import Foundation
import RecipeKit

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

    /// Both fields required; a key a stop does not have is refused.
    public init(from decoder: Decoder) throws {
        try decoder.refuseUnknownKeys(CodingKeys.self, noun: "design")
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(colour: try box.decode(String.self, forKey: .colour), position: try box.decode(Double.self, forKey: .position))
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case colour, position }
}
