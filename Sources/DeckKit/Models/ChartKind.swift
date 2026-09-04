//
//  ChartKind.swift
//  DeckKit
//

import Foundation

/// The chart shapes a table can become.
public enum ChartKind: String, Sendable, Codable, CaseIterable {
    /// Horizontal bars.
    case bar
    /// Vertical bars — what most people mean by "bar chart".
    case column
    case line
    case pie
    case doughnut
    case area

    /// `bar`, `column`… and the aliases people type.
    public init?(word: String) {
        switch word.lowercased() {
        case "bar", "bars", "barh", "horizontal": self = .bar
        case "column", "columns", "col", "vertical": self = .column
        case "line", "lines": self = .line
        case "pie": self = .pie
        case "doughnut", "donut", "ring": self = .doughnut
        case "area": self = .area
        default: return nil
        }
    }
}
