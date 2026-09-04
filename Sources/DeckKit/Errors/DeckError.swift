//
//  DeckError.swift
//  DeckKit
//

import Foundation

public enum DeckError: Error, LocalizedError, Equatable {
    case empty
    case noSuchDesign(String, available: [String])
    case missingImage(String)
    case unsupportedImage(String)
    case cannotWrite(String)
    case previewFailed(String)

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
        }
    }
}
