//
//  DesignVars.swift
//  DeckKit
//
//  `--var name=value`: a design's slots, filled before it is read — so a
//  design whose kicker follows its accent still follows a new one. And the
//  strict read itself: a key a design does not have, a value of the wrong
//  type, refused by its path.
//

import Foundation
import RecipeKit

public enum DesignVars {

    /// What `--var` can set: the accent, and the faces.
    public static let names = ["accent", "typeface", "heading-font", "body-font"]

    /// What each takes, for help text.
    public static let help = "accent: a hex colour, like 7C6BF6; typeface: a font family for headings and body; "
        + "heading-font, body-font: one of the two."

    /// The design in `data` with each of `vars` set, read strictly. `called`
    /// names it in a message.
    public static func applied(_ vars: [String: String], to data: Data, called name: String) throws(DeckError) -> Design {
        guard !vars.isEmpty else { return try decoded(data, called: name) }
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw .badDesign(name, reason: "it is not a JSON object")
        }
        for (key, value) in vars.sorted(by: { $0.key < $1.key }) {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "accent":
                var hex = Substring(text)
                if hex.hasPrefix("#") { hex = hex.dropFirst() }
                guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else {
                    throw .badVar("accent is a hex colour, like 7C6BF6; not \(value)")
                }
                object["accent"] = hex.uppercased()
            case "typeface", "heading-font", "body-font":
                guard !text.isEmpty else { throw .badVar("\(key) is a font family, like Avenir Next; it cannot be empty") }
                if key != "body-font" { object["headingFont"] = text }
                if key != "heading-font" { object["bodyFont"] = text }
            default:
                let close = FieldPaths.closest(key, among: names).map { " — did you mean \($0)?" }
                    ?? " (\(names.joined(separator: ", ")))"
                throw .badVar("\(key) is not a var\(close)")
            }
        }
        guard let filled = try? JSONSerialization.data(withJSONObject: object) else {
            throw .badDesign(name, reason: "it could not be written back")
        }
        return try decoded(filled, called: name)
    }

    /// A design from JSON, strictly: a key a design does not have is refused
    /// with the one it was probably meant to be, a wrong type by its path.
    public static func decoded(_ data: Data, called name: String) throws(DeckError) -> Design {
        do { return try JSONDecoder().decode(Design.self, from: data) } catch let error as RecipeError {
            throw .badDesign(name, reason: error.message)
        } catch let DecodingError.typeMismatch(_, context) {
            throw .badDesign(name, reason: "\(RecipeJSON.path(context.codingPath)) has the wrong type")
        } catch let DecodingError.keyNotFound(key, context) {
            throw .badDesign(name, reason: "\(RecipeJSON.path(context.codingPath + [key])) is missing")
        } catch let DecodingError.valueNotFound(_, context) {
            throw .badDesign(name, reason: "\(RecipeJSON.path(context.codingPath)) is null")
        } catch let DecodingError.dataCorrupted(context) {
            throw .badDesign(name, reason: context.codingPath.isEmpty ? "it is not JSON" : "\(RecipeJSON.path(context.codingPath)) — \(context.debugDescription)")
        } catch {
            throw .badDesign(name, reason: error.localizedDescription)
        }
    }
}
