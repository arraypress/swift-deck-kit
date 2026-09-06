//
//  Run.swift
//  DeckKit
//
//  Where everything goes — one rhythm, applied to every slide shape.
//

//

import Foundation

/// One styled paragraph.
public struct Run: Sendable, Equatable {

    /// The pieces of the line, each with its own marks.
    ///
    /// A paragraph used to be one string, so `**bold**` inside a bullet
    /// reached the slide with its asterisks intact. OOXML models it the same
    /// way — one `<a:p>` holding several `<a:r>`.
    public let spans: [Span]

    /// The whole line, unmarked. For measuring and for a manifest.
    public var text: String { spans.map(\.text).joined() }
    /// Type size in points.
    public let size: Double
    /// Whether the whole paragraph is bold. A span can still be bold on its own.
    public let bold: Bool
    /// Six-digit hex, no `#`.
    public let colour: String
    /// Space before this line, in points.
    public let spaceBefore: Double
    /// Letter-spacing in points. Negative tightens large type, which is the
    /// single change that most separates a modern heading from a dated one.
    public let tracking: Double
    /// Line spacing as a multiple, or nil for the font's own.
    public let lineSpacing: Double?

    /// The bullet or number this paragraph carries, and how deep it sits.
    public let marker: Marker
    /// Indent depth, counting from 0.
    public let level: Int

    /// Which of the design's two faces sets this run.
    ///
    /// Named on the run because the writer names it on every `<a:r>`: a
    /// face that lives only in the theme never reached a text box in Quick
    /// Look, and every deck rendered in the viewer's fallback sans while the
    /// design said Avenir Next.
    public let face: Face

    /// What sits in front of a paragraph.
    public enum Marker: Sendable, Equatable {
        case none
        /// A literal character — a dash, a dot, whatever the design says.
        case character(String)
        /// 1. 2. 3., counted by PowerPoint so an inserted line renumbers.
        case number
    }

    /// The design's heading face or its body face.
    public enum Face: Sendable, Equatable { case body, heading }

    public init(_ text: String, size: Double, bold: Bool = false,
                colour: String, spaceBefore: Double = 0,
                tracking: Double = 0, lineSpacing: Double? = nil,
                marker: Marker = .none, level: Int = 0, face: Face = .body) {
        self.init(Inline.spans(text), size: size, bold: bold, colour: colour,
                  spaceBefore: spaceBefore, tracking: tracking,
                  lineSpacing: lineSpacing, marker: marker, level: level, face: face)
    }

    public init(_ spans: [Span], size: Double, bold: Bool = false,
                colour: String, spaceBefore: Double = 0,
                tracking: Double = 0, lineSpacing: Double? = nil,
                marker: Marker = .none, level: Int = 0, face: Face = .body) {
        self.spans = spans
        self.size = size
        self.bold = bold
        self.colour = colour
        self.spaceBefore = spaceBefore
        self.tracking = tracking
        self.lineSpacing = lineSpacing
        self.marker = marker
        self.level = level
        self.face = face
    }
}
