//
//  DeckError.swift
//  DeckKit
//

import Foundation

/// Why a deck could not be built or written.
public enum DeckError: Error, LocalizedError, Equatable {
    case empty
    case noSuchDesign(String, available: [String])
    case missingImage(String)
    case unsupportedImage(String)
    case cannotWrite(String)
    case previewFailed(String)
    case notAFont(String)
    case noLibreOffice
    case pdfFailed(String)

    /// A one-line reason, for a CLI or a log.
    public var errorDescription: String? {
        switch self {
        case .empty: return "the deck has no slides"
        case let .noSuchDesign(name, available):
            return "no design called \(name) — there is \(available.joined(separator: ", "))"
        case let .missingImage(path): return "no image at \(path)"
        case let .unsupportedImage(path):
            return "\(((path as NSString).pathExtension)) is not an image PowerPoint reads — use png, jpg or gif"
        case let .cannotWrite(path): return "could not write \(path)"
        case let .previewFailed(why): return "could not render the slides: \(why)"
        case let .notAFont(name): return "\(name) is not a TrueType or OpenType font"
        case .noLibreOffice: return "LibreOffice is not installed — brew install --cask libreoffice — so there is nothing to render a PDF with"
        case let .pdfFailed(why): return "could not render the PDF: \(why)"
        }
    }
}
