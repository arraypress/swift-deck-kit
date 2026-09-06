//
//  Inline.swift
//  DeckKit
//
//  A line is made of spans, because half a sentence can be bold.
//

//

import Foundation

/// Reading the marks out of a line of Markdown.
public enum Inline {

    /// `**bold**`, `*italic*`, `` `code` `` and `[text](url)`.
    ///
    /// Deliberately small. A deck is not a document, and the marks people
    /// actually use in a bullet are these four — everything else would be a
    /// parser to maintain for text nobody writes on a slide.
    public static func spans(_ text: String) -> [Span] {
        var spans: [Span] = []
        var plain = ""
        var index = text.startIndex

        func flush() {
            if !plain.isEmpty { spans.append(Span(plain)); plain = "" }
        }

        while index < text.endIndex {
            let rest = text[index...]

            if rest.hasPrefix("**") {
                if let close = range(in: rest.dropFirst(2), of: "**"),
                   close.lowerBound > rest.dropFirst(2).startIndex {
                    flush()
                    spans.append(Span(String(rest.dropFirst(2)[..<close.lowerBound]), bold: true))
                    index = close.upperBound
                    continue
                }
                /// Unclosed. Both asterisks go through as literal text —
                /// falling through let the italic branch match the SECOND
                /// asterisk of the pair, which produced an empty italic span
                /// and silently ate the marks the author typed.
                plain += "**"
                index = text.index(index, offsetBy: 2)
                continue
            }
            if rest.hasPrefix("`"), let close = range(in: rest.dropFirst(1), of: "`"),
               close.lowerBound > rest.dropFirst(1).startIndex {
                flush()
                spans.append(Span(String(rest.dropFirst(1)[..<close.lowerBound]), code: true))
                index = close.upperBound
                continue
            }
            /// After `**`, so the opening of a bold run is never read as an
            /// italic one.
            if rest.hasPrefix("*"), let close = range(in: rest.dropFirst(1), of: "*"),
               close.lowerBound > rest.dropFirst(1).startIndex {
                flush()
                spans.append(Span(String(rest.dropFirst(1)[..<close.lowerBound]), italic: true))
                index = close.upperBound
                continue
            }
            if rest.hasPrefix("["), let closeBracket = range(in: rest.dropFirst(1), of: "]"),
               text[closeBracket.upperBound...].hasPrefix("("),
               let closeParen = range(in: text[closeBracket.upperBound...].dropFirst(1), of: ")") {
                flush()
                let label = String(rest.dropFirst(1)[..<closeBracket.lowerBound])
                let target = String(text[closeBracket.upperBound...].dropFirst(1)[..<closeParen.lowerBound])
                spans.append(Span(label, link: target))
                index = closeParen.upperBound
                continue
            }

            plain.append(text[index])
            index = text.index(after: index)
        }
        flush()
        return spans.isEmpty ? [Span(text)] : spans
    }

    /// The range of the first `marker`, and where to carry on after it.
    private static func range(in text: Substring, of marker: String) -> Range<String.Index>? {
        text.range(of: marker).map { $0.lowerBound..<$0.upperBound }
    }

    /// The text with its marks taken off, for counting and for a manifest.
    public static func plain(_ text: String) -> String {
        spans(text).map(\.text).joined()
    }
}
