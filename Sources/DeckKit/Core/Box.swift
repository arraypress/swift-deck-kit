//
//  Box.swift
//  DeckKit
//
//  Where everything goes — one rhythm, applied to every slide shape.
//

//

import Foundation

/// A positioned box of text or colour.
public struct Box: Sendable, Equatable {
    /// What the box holds.
    public enum Content: Sendable, Equatable {
        case text([Run], align: Align, anchor: Anchor)
        case fill(String)
        /// A rounded, possibly translucent and shadowed card.
        case panel(Panel)
        /// A gradient ground, which is what a flat colour used to be.
        case gradient([Stop], angle: Double)
        case picture(String, fit: Fit = .contain)
        /// A real table, editable in PowerPoint rather than a picture of one.
        case table(rows: [[String]], header: Bool)
        /// A chart: native and editable, or drawn and placed as a picture.
        case chart(kind: ChartKind, rows: [[String]], header: Bool, native: Bool)
        /// The slide's own number, as a field rather than a typed digit.
        case slideNumber(Int, size: Double, colour: String)
    }
    /// How text sits across the box.
    public enum Align: String, Sendable { case left, centre, right }
    /// How a picture sits in a box that is not its shape.
    public enum Fit: Sendable, Equatable {
        /// Largest size that fits, centred.
        case contain
        /// Largest size that fits, against the left edge — a logo.
        case leading
        /// Largest size that fits, against the top edge — a picture beside text.
        case top
        /// Fills the box, cropped, and darkened by `dim` (0–1) — a cover.
        case cover(dim: Double)
    }
    /// How text sits down the box.
    public enum Anchor: String, Sendable { case top, middle, bottom }

    /// Position and size, in EMU — see ``Canvas``.
    public let x: Int, y: Int, width: Int, height: Int
    /// What is drawn in it.
    public let content: Content
    /// The placeholder this box fills, if any.
    ///
    /// A slide's title has to sit in a `title` placeholder or the outline
    /// pane shows nothing — the text is there, but PowerPoint has no idea
    /// which of the boxes is the heading.
    public var placeholder: String?

    public init(x: Int, y: Int, width: Int, height: Int,
                content: Content, placeholder: String? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.content = content
        self.placeholder = placeholder
    }
}
