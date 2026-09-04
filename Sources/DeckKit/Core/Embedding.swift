//
//  Embedding.swift
//  DeckKit
//
//  Carrying the typeface, because a .pptx only names one.
//

import Foundation

/// Embedding a font in the file.
///
/// A `.pptx` **names** fonts; it does not carry them. So a deck set in a face
/// the recipient has not got renders in whatever their machine substitutes —
/// which is why `SF Pro` is not an option here and why `Avenir Next`, lovely
/// as it is on a Mac, degrades on Windows.
///
/// Embedding fixes that for **PowerPoint**, which honours an embedded font.
/// Keynote and Google Slides largely ignore it, and no format solves those —
/// so this is offered, not assumed, and the fallback face still matters.
///
/// The bundled family is [Inter](https://github.com/rsms/inter), SIL OFL 1.1,
/// which explicitly permits embedding and redistribution. A licence that did
/// not would make this illegal rather than merely unhelpful.
public enum Embedding {

    /// The four faces PowerPoint asks for.
    public enum Face: String, Sendable, CaseIterable {
        case regular, bold, italic, boldItalic

        var fileName: String {
            switch self {
            case .regular: return "Inter-Regular"
            case .bold: return "Inter-Bold"
            case .italic: return "Inter-Italic"
            case .boldItalic: return "Inter-BoldItalic"
            }
        }
        /// The element name in `p:embeddedFont`, which is not the raw value
        /// for every case.
        var element: String { rawValue }
    }

    /// The typeface the bundled files are.
    public static let bundledTypeface = "Inter"

    /// The bundled faces, or nothing if the resources are missing.
    public static func bundled() -> [(face: Face, data: Data)] {
        Face.allCases.compactMap { face in
            guard let url = Resources.bundle.url(forResource: face.fileName, withExtension: "ttf"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return (face, data)
        }
    }

    /// A caller's own font: one file for every face they have.
    ///
    /// Only accepts files that look like a font, because a `.pptx` carrying
    /// a text file named `.ttf` opens and then renders nothing, with no
    /// error anywhere.
    public static func read(_ paths: [Face: URL]) throws -> [(face: Face, data: Data)] {
        try Face.allCases.compactMap { face in
            guard let url = paths[face] else { return nil }
            let data = try Data(contentsOf: url)
            guard isFont(data) else { throw DeckError.notAFont(url.lastPathComponent) }
            return (face, data)
        }
    }

    /// TrueType, OpenType or a collection, by its first four bytes.
    static func isFont(_ data: Data) -> Bool {
        let tags: [[UInt8]] = [
            [0x00, 0x01, 0x00, 0x00],       // TrueType
            Array("OTTO".utf8),             // OpenType with CFF outlines
            Array("true".utf8),             // older Apple TrueType
            Array("ttcf".utf8),             // a collection
        ]
        let head = Array(data.prefix(4))
        return head.count == 4 && tags.contains(head)
    }
}
