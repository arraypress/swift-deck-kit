//
//  Designs.swift
//  DeckKit
//
//  The designs that ship, and the one a caller wrote.
//

import Foundation

/// The bundled designs.
public enum Designs {

    /// Every design that ships, by name.
    public static let all: [Design] = {
        guard let urls = Resources.bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            return [.fallback]
        }
        let decoder = JSONDecoder()
        let found = urls.compactMap { url -> Design? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Design.self, from: data)
        }
        return found.isEmpty ? [.fallback] : found.sorted { $0.name < $1.name }
    }()

    /// Every built-in design name, for a listing or a `--design` error.
    public static var names: [String] { all.map(\.name) }

    /// One design by name, or the one at a path the caller wrote themselves.
    public static func named(_ name: String) throws -> Design {
        if name.hasSuffix(".json") {
            let url = URL(fileURLWithPath: (name as NSString).expandingTildeInPath)
            guard let data = try? Data(contentsOf: url) else { throw DeckError.noSuchDesign(name, available: names) }
            return try JSONDecoder().decode(Design.self, from: data)
        }
        guard let design = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw DeckError.noSuchDesign(name, available: names)
        }
        return design
    }
}
