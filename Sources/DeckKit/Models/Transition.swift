//
//  Transition.swift
//  DeckKit
//

import Foundation

/// How one slide gives way to the next.
///
/// Three, and the quiet ones: a deck that pushes and wipes is a deck people
/// remember for pushing and wiping.
public enum Transition: String, Sendable, Codable, CaseIterable {
    case none, fade, push, wipe
}
