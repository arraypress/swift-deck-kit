//
//  Bullet.swift
//  DeckKit
//
//  A point, how deep it sits, and whether it is counted.
//

import Foundation

/// One item in a list.
public struct Bullet: Sendable, Equatable, ExpressibleByStringLiteral {
    /// The line, with its Markdown marks still in it.
    public var text: String
    /// 0 for a top-level point, 1 for one indented under it.
    public var level: Int
    /// Numbered rather than bulleted. PowerPoint does the counting, so
    /// inserting a line renumbers the rest.
    public var numbered: Bool

    public init(_ text: String, level: Int = 0, numbered: Bool = false) {
        self.text = text
        self.level = level
        self.numbered = numbered
    }

    /// So a caller — and every existing test — can still write a plain string.
    public init(stringLiteral value: String) {
        self.init(value)
    }
}
