//
//  DeckKitTests.swift
//  DeckKit
//
//  The structure of a .pptx is checked against the ECMA-376 schemas and an
//  independent reader outside these tests; what is checked here is that the
//  grammar keeps the author's words and the layout keeps its rhythm.
//

import Foundation
import XCTest
@testable import DeckKit

final class MarkdownTests: XCTestCase {

    func testTheFirstHeadingIsTheTitleSlide() {
        let deck = Markdown.deck(from: "# A deck\nwith a subtitle\n\n## Then a slide\n- one")
        XCTAssertEqual(deck.title, "A deck")
        guard case let .title(text, subtitle) = deck.slides.first else { return XCTFail() }
        XCTAssertEqual(text, "A deck")
        XCTAssertEqual(subtitle, "with a subtitle")
    }

    func testALaterTopLevelHeadingIsASectionNotAnotherTitle() {
        let deck = Markdown.deck(from: "# One\n\n## Two\n- x\n\n# Three")
        XCTAssertEqual(deck.slides.map(\.kind), ["title", "points", "section"])
    }

    func testAStatementAndAQuoteEachGetTheirOwnSlide() {
        // The bug this pins: only splitting on headings put a heading, a
        // statement and a quote in one block, and the parser returned ONE of
        // them — silently dropping the author's other words.
        let deck = Markdown.deck(from: """
            ## A heading
            some prose
            ! A statement
            > A quote
            """)
        XCTAssertEqual(deck.slides.map(\.kind), ["prose", "statement", "quote"])
    }

    func testARunOfQuoteLinesIsOneQuote() {
        let deck = Markdown.deck(from: "> first line\n> second line")
        XCTAssertEqual(deck.slides.count, 1)
        guard case let .quote(text, _) = deck.slides[0] else { return XCTFail() }
        XCTAssertEqual(text, "first line second line")
    }

    func testAnAttributionBelongsToTheQuoteAboveIt() {
        let deck = Markdown.deck(from: "> A quote\n\u{2014} Someone")
        XCTAssertEqual(deck.slides.count, 1, "the attribution took a slide of its own")
        guard case let .quote(_, attribution) = deck.slides[0] else { return XCTFail() }
        XCTAssertEqual(attribution, "Someone")
    }

    func testALonePipeMakesTwoColumns() {
        // Without a grammar for it the columns layout could never fire, and a
        // comparison came out as one long list.
        let deck = Markdown.deck(from: "## Compare\n- a\n- b\n|\n- c\n- d")
        guard case let .columns(_, left, right, _) = deck.slides[0] else {
            return XCTFail("got \(deck.slides[0].kind)")
        }
        XCTAssertEqual(left, ["a", "b"])
        XCTAssertEqual(right, ["c", "d"])
    }

    func testNoWordsAreLost() {
        // The one thing a converter must never do.
        let source = """
            # Title
            subtitle here

            ## Points
            - alpha
            - beta

            ## Prose
            a paragraph of prose

            ! a statement

            > a quotation
            """
        let deck = Markdown.deck(from: source)
        let written = deck.slides.flatMap(\.texts).joined(separator: " ")
        for word in ["Title", "subtitle", "alpha", "beta", "paragraph", "statement", "quotation"] {
            XCTAssertTrue(written.contains(word), "\(word) was dropped")
        }
    }

    func testNotesAreKeptOffTheSlide() {
        let deck = Markdown.deck(from: "## A slide\n- one\n??? say this out loud")
        XCTAssertEqual(deck.slides[0].note, "say this out loud")
        XCTAssertFalse(deck.slides[0].texts.contains { $0.contains("out loud") })
    }

    func testAnImageBecomesAnImageSlide() {
        let deck = Markdown.deck(from: "## A picture\n![the caption](chart.png)")
        guard case let .image(path, caption, heading) = deck.slides[0] else { return XCTFail() }
        XCTAssertEqual(path, "chart.png")
        XCTAssertEqual(caption, "the caption")
        XCTAssertEqual(heading, "A picture")
    }

    func testEmptyInputGivesAnEmptyDeck() {
        XCTAssertTrue(Markdown.deck(from: "\n\n   \n").slides.isEmpty)
    }
}

final class DesignTests: XCTestCase {

    func testTheScaleIsDerivedFromOneNumber() {
        var design = Design.fallback
        design.base = 20
        design.ratio = 1.5
        XCTAssertEqual(design.size(0), 20)
        XCTAssertEqual(design.size(1), 30)
        XCTAssertEqual(design.size(2), 45)
        XCTAssertEqual(design.size(-1), 13, "rounded to a whole point")
    }

    func testAStatementIsBiggerThanAHeading() {
        // It was set at heading size, which made the slide meant to be
        // remembered look like an ordinary one.
        let design = Design.fallback
        XCTAssertGreaterThan(design.statementSize, design.headingSize)
        XCTAssertGreaterThan(design.titleSize, design.statementSize)
    }

    func testEveryBundledDesignLoads() {
        XCTAssertGreaterThanOrEqual(Designs.all.count, 4)
        XCTAssertTrue(Designs.names.contains("studio"))
        for design in Designs.all {
            XCTAssertFalse(design.name.isEmpty)
            XCTAssertEqual(design.background.count, 6, "\(design.name): colours are bare rrggbb")
            XCTAssertGreaterThan(design.base, 8, design.name)
            XCTAssertGreaterThan(design.ratio, 1, design.name)
        }
    }

    func testAnUnknownDesignNamesTheOnesThatExist() {
        XCTAssertThrowsError(try Designs.named("chartreuse")) { error in
            guard case let DeckError.noSuchDesign(_, available) = error else { return XCTFail() }
            XCTAssertTrue(available.contains("studio"))
        }
    }
}

final class LayoutTests: XCTestCase {

    private let layout = Layout(design: .fallback)

    func testTheHeadingSitsInTheSamePlaceOnEverySlide() {
        // The whole difference between a deck that looks designed and one
        // that looks assembled.
        func headingY(_ slide: Slide) -> Int? {
            layout.boxes(for: slide).first { if case .text = $0.content { return true }; return false }?.y
        }
        let one = headingY(.points("A", items: ["x"], note: nil))
        let two = headingY(.prose("B", body: "y", note: nil))
        let three = headingY(.columns("C", left: ["x"], right: ["y"], note: nil))
        XCTAssertEqual(one, two)
        XCTAssertEqual(two, three)
    }

    func testTheHeadingBandIsTwoLinesDeep() {
        // A heading that wraps used to run straight through the accent rule.
        let design = Design.fallback
        let boxes = layout.boxes(for: .points("A heading", items: ["x"], note: nil))
        guard let heading = boxes.first else { return XCTFail() }
        let needed = Canvas.points(design.lineHeight(design.headingSize) * 2)
        XCTAssertGreaterThanOrEqual(heading.height, Int(Double(needed) * 0.95))
    }

    func testNothingIsPlacedOutsideTheSlide() {
        let canvas = Canvas.sixteenByNine
        let slides: [Slide] = [
            .title("T", subtitle: "s"), .section("S", note: nil),
            .points("P", items: ["a", "b"], note: nil), .prose("R", body: "text", note: nil),
            .statement("Big", attribution: "who"), .quote("Q", attribution: "who"),
            .columns("C", left: ["a"], right: ["b"], note: nil),
        ]
        for slide in slides {
            for box in layout.boxes(for: slide) {
                XCTAssertGreaterThanOrEqual(box.x, 0, slide.kind)
                XCTAssertGreaterThanOrEqual(box.y, 0, slide.kind)
                XCTAssertLessThanOrEqual(box.x + box.width, canvas.width + 1, slide.kind)
                XCTAssertLessThanOrEqual(box.y + box.height, canvas.height + 1, slide.kind)
            }
        }
    }

    func testAFeatureSlideFillsTheWholeCanvas() {
        guard case let .fill(colour) = layout.boxes(for: .title("T", subtitle: nil))[0].content else {
            return XCTFail("the title slide has no background")
        }
        XCTAssertEqual(colour, Design.fallback.featureBackground)
    }
}

final class CheckTests: XCTestCase {

    func testAReasonableSlidePasses() {
        let deck = Deck(slides: [.points("A heading", items: ["one", "two", "three"], note: nil)])
        XCTAssertTrue(Check.problems(in: deck, design: .fallback).isEmpty)
    }

    func testAnOverlongSlideIsCaught() {
        let deck = Deck(slides: [.points("A heading", items: (1...20).map {
            "Point \($0), written at enough length that it wraps onto a second line by itself"
        }, note: nil)])
        let problems = Check.problems(in: deck, design: .fallback)
        XCTAssertFalse(problems.isEmpty)
        XCTAssertEqual(problems.first?.slide, 1)
        XCTAssertGreaterThan(problems.first?.overflow ?? 0, 1.5)
    }

    func testTheCheckerAgreesWithTheLayout() {
        // They share one line-height formula on purpose: when they differed,
        // the checker reported a problem the layout did not have — a two-line
        // heading that fitted fine because its box grows upward.
        let deck = Markdown.deck(from: """
            # A deck
            a subtitle

            ## A heading long enough that it wraps onto a second line on the slide
            - one
            - two
            - three
            """)
        for design in Designs.all {
            XCTAssertTrue(Check.problems(in: deck, design: design).isEmpty,
                          "\(design.name) reported a problem on a deck that fits")
        }
    }
}

final class PPTXTests: XCTestCase {

    private let deck = Markdown.deck(from: "# T\nsub\n\n## H\n- a\n- b")

    func testItWritesAZipWithTheRequiredParts() throws {
        let data = try PPTX.data(deck: deck, design: .fallback)
        XCTAssertEqual(data.prefix(2).map { $0 }, Array("PK".utf8))
        let text = String(decoding: data, as: UTF8.self)
        for part in ["[Content_Types].xml", "ppt/presentation.xml",
                     "ppt/slideMasters/slideMaster1.xml", "ppt/slideLayouts/slideLayout1.xml",
                     "ppt/theme/theme1.xml", "ppt/slides/slide1.xml", "ppt/slides/slide2.xml"] {
            XCTAssertTrue(text.contains(part), "missing \(part)")
        }
    }

    func testAnEmptyDeckIsRefused() {
        XCTAssertThrowsError(try PPTX.data(deck: Deck(slides: []), design: .fallback))
    }

    func testTheSameDeckWritesTheSameBytes() throws {
        // The zip pins its timestamps, so a deck in version control does not
        // churn on every build.
        let one = try PPTX.data(deck: deck, design: .fallback)
        let two = try PPTX.data(deck: deck, design: .fallback)
        XCTAssertEqual(one, two)
    }

    func testMarkupInTheAuthorsTextIsEscaped() throws {
        let awkward = Markdown.deck(from: "## R&D <not a tag>\n- a & b")
        let text = String(decoding: try PPTX.data(deck: awkward, design: .fallback), as: UTF8.self)
        XCTAssertTrue(text.contains("R&amp;D &lt;not a tag&gt;"))
        XCTAssertFalse(text.contains("<not a tag>"))
    }

    func testTypographicQuotesAreNotEscaped() throws {
        // Escaping them shows &quot; in the editor a person opens this in.
        let quoted = Deck(slides: [.quote("hello", attribution: nil)])
        let text = String(decoding: try PPTX.data(deck: quoted, design: .fallback), as: UTF8.self)
        XCTAssertTrue(text.contains("\u{201C}hello\u{201D}"))
    }

    func testAMissingImageIsReportedBeforeAnythingIsWritten() {
        let deck = Markdown.deck(from: "## P\n![](nowhere.png)")
        XCTAssertThrowsError(try DeckWriter.images(for: deck, relativeTo: URL(fileURLWithPath: "/tmp"))) { error in
            guard case DeckError.missingImage = error else { return XCTFail("got \(error)") }
        }
    }

    func testAnUnreadableImageFormatIsRefused() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("x".utf8).write(to: directory.appendingPathComponent("a.tiff"))

        let deck = Markdown.deck(from: "## P\n![](a.tiff)")
        XCTAssertThrowsError(try DeckWriter.images(for: deck, relativeTo: directory)) { error in
            guard case DeckError.unsupportedImage = error else { return XCTFail("got \(error)") }
        }
    }
}

// MARK: - The modern half

final class ModernGrammarTests: XCTestCase {

    func testAnEqualsLineMakesAStat() {
        let deck = Markdown.deck(from: "## Numbers\n= 91 | tools installed\n= 0 | keys required")
        guard case let .stat(heading, figures) = deck.slides[0] else {
            return XCTFail("got \(deck.slides[0].kind)")
        }
        XCTAssertEqual(heading, "Numbers")
        XCTAssertEqual(figures.map(\.figure), ["91", "0"])
        XCTAssertEqual(figures.map(\.label), ["tools installed", "keys required"])
    }

    func testAStatWithNoLabelIsStillAStat() {
        let deck = Markdown.deck(from: "= 91")
        guard case let .stat(_, figures) = deck.slides[0] else { return XCTFail() }
        XCTAssertEqual(figures[0].figure, "91")
        XCTAssertEqual(figures[0].label, "")
    }

    func testADoubleColonMakesACard() {
        let deck = Markdown.deck(from: "## Promises\n:: Keyless | nothing to sign up for\n:: Local | nothing leaves")
        guard case let .cards(_, panels) = deck.slides[0] else {
            return XCTFail("got \(deck.slides[0].kind)")
        }
        XCTAssertEqual(panels.map(\.title), ["Keyless", "Local"])
        XCTAssertEqual(panels[0].body, "nothing to sign up for")
    }

    func testStatsAndCardsKeepEveryWord() {
        let deck = Markdown.deck(from: "## H\n= 91 | tools\n\n## C\n:: Title | body")
        let written = deck.slides.flatMap(\.texts).joined(separator: " ")
        for word in ["91", "tools", "Title", "body"] {
            XCTAssertTrue(written.contains(word), "\(word) was dropped")
        }
    }
}

final class ModernDesignTests: XCTestCase {

    func testTheModernDesignsCarryTheModernKnobs() throws {
        for name in ["aurora", "daylight"] {
            let design = try Designs.named(name)
            XCTAssertNotNil(design.gradient, "\(name) has no gradient")
            XCTAssertNotNil(design.card, "\(name) has no card")
            XCTAssertLessThan(design.headingTracking, 0, "\(name): display type wants negative tracking")
            XCTAssertLessThan(design.lineSpacing, 1, "\(name): display type wants tightening")
        }
    }

    func testTheRestrainedDesignsStillLoadWithoutThem() throws {
        // They predate the modern keys, and a decoder that required them
        // would have broken all four.
        for name in ["studio", "mono", "warm", "slate"] {
            let design = try Designs.named(name)
            XCTAssertNil(design.gradient, name)
            XCTAssertEqual(design.headingTracking, 0, name)
            XCTAssertEqual(design.lineSpacing, 1, name)
        }
    }

    func testLineHeightAccountsForTightenedSpacing() {
        // A checker that ignored lineSpacing flagged the title slide of every
        // modern design as overflowing when it fitted perfectly well.
        var design = Design.fallback
        design.lineSpacing = 0.9
        XCTAssertLessThan(design.lineHeight(40), Design.fallback.lineHeight(40))
    }

    func testEveryDesignRendersEverySlideShapeWithoutOverflowing() throws {
        let deck = Markdown.deck(from: """
            # A title
            a subtitle

            ## Numbers
            = 91 | tools installed
            = 38 | in the tap

            ## Promises
            :: Keyless | nothing to sign up for
            :: Local | nothing leaves the machine

            ## Points
            - one
            - two
            """)
        for design in Designs.all {
            XCTAssertTrue(Check.problems(in: deck, design: design).isEmpty,
                          "\(design.name) overflows on an ordinary deck")
        }
    }
}

final class ModernOutputTests: XCTestCase {

    func testAGradientDesignWritesAGradientFill() throws {
        let design = try Designs.named("aurora")
        let deck = Deck(slides: [.title("T", subtitle: nil)])
        let text = String(decoding: try PPTX.data(deck: deck, design: design), as: UTF8.self)
        XCTAssertTrue(text.contains("<a:gradFill"))
        XCTAssertTrue(text.contains("<a:gs pos="))
    }

    func testACardIsRoundedTranslucentAndShadowed() throws {
        let design = try Designs.named("aurora")
        let deck = Deck(slides: [.stat("N", figures: [(figure: "91", label: "tools")])])
        let text = String(decoding: try PPTX.data(deck: deck, design: design), as: UTF8.self)
        XCTAssertTrue(text.contains("prst=\"roundRect\""))
        XCTAssertTrue(text.contains("<a:alpha val="))
        XCTAssertTrue(text.contains("<a:outerShdw"))
    }

    func testNegativeTrackingIsWritten() throws {
        let design = try Designs.named("aurora")
        let deck = Deck(slides: [.title("T", subtitle: nil)])
        let text = String(decoding: try PPTX.data(deck: deck, design: design), as: UTF8.self)
        XCTAssertTrue(text.contains("spc=\"-"), "no negative letter-spacing reached the file")
    }

    func testLineSpacingComesBeforeSpaceBefore() throws {
        // The schema requires that order. Written the other way round it
        // renders in Quick Look and `xmllint --schema pml.xsd` rejects it —
        // a lenient previewer hides it, PowerPoint might not.
        let design = try Designs.named("aurora")
        let deck = Deck(slides: [.title("T", subtitle: "s")])
        let text = String(decoding: try PPTX.data(deck: deck, design: design), as: UTF8.self)
        guard let paragraph = text.range(of: "<a:lnSpc"), let before = text.range(of: "<a:spcBef") else {
            return XCTFail("expected both elements")
        }
        XCTAssertLessThan(paragraph.lowerBound, before.lowerBound)
    }

    func testAFlatDesignWritesNoGradient() throws {
        let text = String(decoding: try PPTX.data(deck: Deck(slides: [.title("T", subtitle: nil)]),
                                                  design: try Designs.named("mono")), as: UTF8.self)
        XCTAssertFalse(text.contains("<a:gradFill"))
    }
}
