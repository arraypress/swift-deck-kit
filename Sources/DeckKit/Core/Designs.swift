//
//  Designs.swift
//  DeckKit
//
//  The designs that ship, and the one a caller wrote. A design that will
//  not read is an error that says which and why — never dropped from the
//  list without a word.
//

import Foundation
import RecipeKit

/// The bundled designs.
public enum Designs {

    /// Every design that ships, by name — or the reason one will not read.
    /// A design is part of the package, so ``catalogueProblems`` is asserted
    /// empty by a test; this is what a run sees if one slips through anyway.
    public static func all() throws(DeckError) -> [Design] {
        let read = bundled
        if let failure = read.failure { throw failure }
        return read.designs
    }

    /// Every built-in design name, for a listing or a `--design` error.
    public static var names: [String] { bundled.designs.map(\.name) }

    /// One design by name, or the one at a path the caller wrote themselves,
    /// with `vars` filled in: `["accent": "1F3A5F"]` (see ``DesignVars``).
    public static func named(_ name: String, vars: [String: String] = [:]) throws(DeckError) -> Design {
        if name.hasSuffix(".json") {
            let url = URL(fileURLWithPath: (name as NSString).expandingTildeInPath)
            guard let data = try? Data(contentsOf: url) else { throw .noSuchDesign(name, available: names) }
            return try DesignVars.applied(vars, to: data, called: name)
        }
        let designs = try all()
        guard let index = designs.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw .noSuchDesign(name, available: names)
        }
        guard !vars.isEmpty else { return designs[index] }
        return try DesignVars.applied(vars, to: bundled.files[index].data, called: designs[index].name)
    }

    /// A design's JSON, for somebody to start their own from.
    public static func blueprint(_ name: String) throws(DeckError) -> Data {
        let designs = try all()
        guard let index = designs.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw .noSuchDesign(name, available: names)
        }
        return bundled.files[index].data
    }

    /// Every problem with the bundled designs: none found, one that does not
    /// read strictly, a name that is not kebab-case, is listed twice, or is
    /// not its file's name. A test asserts there are none.
    public static var catalogueProblems: [String] {
        guard !bundled.files.isEmpty else { return ["the designs are not in the package's resources"] }
        var seen = Set<String>()
        return bundled.files.flatMap { file -> [String] in
            var problems = StyleCatalogs.nameProblems(file.name, seen: &seen)
            do {
                let design = try DesignVars.decoded(file.data, called: file.name)
                if design.name != file.name { problems.append("\(file.name).json calls itself \(design.name)") }
            } catch {
                problems.append(error.localizedDescription)
            }
            return problems
        }
    }

    // MARK: Reading the package's

    /// The files, read once, in name order: their bytes, the designs, and
    /// the first that failed.
    private static let bundled: (files: [(name: String, data: Data)], designs: [Design], failure: DeckError?) = {
        let urls = (Resources.bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else {
            return ([], [], .badDesign("the package", reason: "its designs are missing from the resources — the bundle did not travel with the binary"))
        }
        var files: [(name: String, data: Data)] = []
        var designs: [Design] = []
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            do {
                let data = try Data(contentsOf: url)
                let design = try DesignVars.decoded(data, called: name)
                files.append((name, data))
                designs.append(design)
            } catch let error as DeckError {
                return (files, designs, error)
            } catch {
                return (files, designs, .badDesign(name, reason: error.localizedDescription))
            }
        }
        let order = designs.indices.sorted { designs[$0].name < designs[$1].name }
        return (order.map { files[$0] }, order.map { designs[$0] }, nil)
    }()
}
