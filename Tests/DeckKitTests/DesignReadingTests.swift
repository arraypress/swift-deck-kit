//
//  DesignReadingTests.swift
//  DeckKit
//
//  The bundled designs read strictly under their own names; a design file
//  with a misspelt key is refused, not quietly used; vars fill a design's
//  slots before it is read.
//

import XCTest
@testable import DeckKit

final class DesignReadingTests: XCTestCase {

    func testTheCatalogueReadsStrictlyUnderItsNames() throws {
        XCTAssertEqual(Designs.catalogueProblems, [])
        XCTAssertEqual(try Designs.all().map(\.name), ["aurora", "daylight", "mono", "slate", "studio", "warm"])
        XCTAssertEqual(Designs.names.count, 6)
    }

    private func refusal(_ json: String) -> String {
        do { _ = try DesignVars.decoded(Data(json.utf8), called: "mine.json"); return "(read)" } catch {
            return error.localizedDescription
        }
    }

    func testAMisspeltKeyIsRefusedWithTheOneItMeant() {
        XCTAssertEqual(refusal(#"{"name": "m", "acent": "FFFFFF"}"#),
                       "mine.json is not a design: acent is not a design field — did you mean accent?")
        XCTAssertEqual(refusal(#"{"name": "m", "card": {"fill": "FFFFFF", "fillAlpha": 1, "borderAlpha": 1, "borderWidth": 1, "radius": 0, "shadow": false, "shdow": true}}"#),
                       "mine.json is not a design: card.shdow is not a design field — did you mean card.shadow?")
        XCTAssertEqual(refusal(#"{"name": "m", "gradient": [{"colour": "000000", "position": 0}, {"color": "FFFFFF", "position": 1}]}"#),
                       "mine.json is not a design: gradient.1.color is not a design field — did you mean gradient.1.colour?")
        XCTAssertEqual(refusal(#"{"name": "m", "base": "big"}"#), "mine.json is not a design: base has the wrong type")
        XCTAssertEqual(refusal(#"{"description": "no name"}"#), "mine.json is not a design: name is missing")
        XCTAssertEqual(refusal("nope"), "mine.json is not a design: it is not JSON")
    }

    func testVarsFillTheSlotsBeforeTheDesignIsRead() throws {
        let plain = try Designs.named("studio")
        let tinted = try Designs.named("studio", vars: ["accent": "#7c6bf6", "typeface": "Futura"])
        XCTAssertEqual(tinted.accent, "7C6BF6")
        XCTAssertEqual(tinted.headingFont, "Futura")
        XCTAssertEqual(tinted.bodyFont, "Futura")
        if plain.kickerColour == plain.accent {
            XCTAssertEqual(tinted.kickerColour, "7C6BF6", "a kicker that follows the accent follows a new one")
        }
        let heading = try Designs.named("studio", vars: ["heading-font": "Futura"])
        XCTAssertEqual(heading.headingFont, "Futura")
        XCTAssertEqual(heading.bodyFont, plain.bodyFont)
    }

    func testABadVarIsRefusedByName() {
        func message(_ vars: [String: String]) -> String {
            do { _ = try Designs.named("aurora", vars: vars); return "(ok)" } catch { return error.localizedDescription }
        }
        XCTAssertEqual(message(["acent": "7C6BF6"]), "acent is not a var — did you mean accent?")
        XCTAssertEqual(message(["density": "compact"]), "density is not a var (accent, typeface, heading-font, body-font)")
        XCTAssertEqual(message(["accent": "violet"]), "accent is a hex colour, like 7C6BF6; not violet")
        XCTAssertEqual(message(["typeface": " "]), "typeface is a font family, like Avenir Next; it cannot be empty")
    }
}
