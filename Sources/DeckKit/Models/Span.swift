//
//  Span.swift
//  DeckKit
//
//  A line is made of spans, because half a sentence can be bold.
//

//

import Foundation

/// A stretch of text with one set of marks.
///
/// A paragraph used to be a single string, which meant `**bold**` inside a
/// bullet reached the slide with its asterisks intact. OOXML models this the
/// same way: one `<a:p>` holding several `<a:r>`.
public struct Span: Sendable, Equatable {
    /// The piece of the line, with its marks already stripped.
    public var text: String
    /// Whether this piece alone is bold.
    public var bold: Bool
    /// Whether this piece alone is italic.
    public var italic: Bool
    /// Monospaced, for a file name or a flag.
    public var code: Bool
    /// A link's target, which PowerPoint makes clickable.
    public var link: String?

    public init(_ text: String, bold: Bool = false, italic: Bool = false,
                code: Bool = false, link: String? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.code = code
        self.link = link
    }
}
