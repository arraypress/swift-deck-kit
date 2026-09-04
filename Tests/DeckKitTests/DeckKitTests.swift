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
            .title("T", subtitle: "s"), .section("S", subtitle: nil, note: nil),
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
            Bullet("Point \($0), written at enough length that it wraps onto a second line by itself")
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
        guard case let .stat(heading, figures, _) = deck.slides[0] else {
            return XCTFail("got \(deck.slides[0].kind)")
        }
        XCTAssertEqual(heading, "Numbers")
        XCTAssertEqual(figures.map(\.figure), ["91", "0"])
        XCTAssertEqual(figures.map(\.label), ["tools installed", "keys required"])
    }

    func testAStatWithNoLabelIsStillAStat() {
        let deck = Markdown.deck(from: "= 91")
        guard case let .stat(_, figures, _) = deck.slides[0] else { return XCTFail() }
        XCTAssertEqual(figures[0].figure, "91")
        XCTAssertEqual(figures[0].label, "")
    }

    func testADoubleColonMakesACard() {
        let deck = Markdown.deck(from: "## Promises\n:: Keyless | nothing to sign up for\n:: Local | nothing leaves")
        guard case let .cards(_, panels, _) = deck.slides[0] else {
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
        let deck = Deck(slides: [.stat("N", figures: [(figure: "91", label: "tools")], note: nil)])
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
        let deck = Deck(slides: [.cards("T", panels: [(title: "a", body: "b")], note: nil)])
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

// MARK: - Inline marks, lists and notes

final class InlineTests: XCTestCase {

    func testTheFourMarks() {
        XCTAssertEqual(Inline.spans("a **b** c").map(\.bold), [false, true, false])
        XCTAssertEqual(Inline.spans("a *b* c").map(\.italic), [false, true, false])
        XCTAssertEqual(Inline.spans("a `b` c").map(\.code), [false, true, false])
        XCTAssertEqual(Inline.spans("[label](url)").first?.link, "url")
    }

    func testAnUnclosedMarkerStaysLiteral() {
        // It used to fall through to the italic branch, which matched the
        // SECOND asterisk of the pair — producing an empty italic span and
        // silently eating the marks the author typed.
        XCTAssertEqual(Inline.plain("**unclosed bold"), "**unclosed bold")
        XCTAssertEqual(Inline.spans("**unclosed bold").count, 1)
        XCTAssertEqual(Inline.plain("an * unpaired asterisk"), "an * unpaired asterisk")
        XCTAssertEqual(Inline.plain("**"), "**")
    }

    func testAnEmptyPairMakesNoEmptySpan() {
        XCTAssertFalse(Inline.spans("a ** b").contains { $0.text.isEmpty })
    }

    func testPlainStripsTheMarks() {
        XCTAssertEqual(Inline.plain("a **b** and `c` and [d](e)"), "a b and c and d")
    }
}

final class ListTests: XCTestCase {

    func testIndentationBecomesALevel() {
        let deck = Markdown.deck(from: "## H\n- top\n  - under\n    - deeper")
        guard case let .points(_, items, _) = deck.slides[0] else { return XCTFail() }
        XCTAssertEqual(items.map(\.level), [0, 1, 2])
    }

    func testNumbersAreThrownAwayAndCountedByPowerPoint() {
        // An author who renumbers by hand always ends up with two sevens.
        let deck = Markdown.deck(from: "## H\n1. first\n2. second\n3) third")
        guard case let .points(_, items, _) = deck.slides[0] else { return XCTFail() }
        XCTAssertEqual(items.map(\.text), ["first", "second", "third"])
        XCTAssertTrue(items.allSatisfy(\.numbered))
    }

    func testAYearIsNotAList() {
        // "2026. A good year" would otherwise become item one.
        XCTAssertNil(Markdown.bullet("2026 was a good year"))
        XCTAssertNotNil(Markdown.bullet("1. a real item"))
    }

    func testABulletCarriesItsMarksThroughToTheFile() throws {
        let deck = Markdown.deck(from: "## H\n- a **bold** point")
        let text = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertTrue(text.contains("<a:t>bold</a:t>"))
        XCTAssertFalse(text.contains("**bold**"), "the marks reached the slide")
    }

    func testALevelBecomesAHangingIndent() throws {
        // marL and indent only — `lvl` selects a list style from the master,
        // and with none defined it overrode these and left every sub-bullet's
        // marker at the same x while only its text moved.
        let deck = Markdown.deck(from: "## H\n- top\n  - under")
        let text = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        /// One step in, then two — the exact figures follow the step size,
        /// so this asserts the shape rather than the numbers: a level-1 item
        /// is indented twice as far as a level-0 one and both hang by one.
        let level0 = try XCTUnwrap(text.range(of: "marL=\"")).upperBound
        let first = Int(text[level0...].prefix(while: \.isNumber)) ?? 0
        XCTAssertGreaterThan(first, 0)
        XCTAssertTrue(text.contains("marL=\"\(first * 2)\" indent=\"-\(first)\""),
                      "a level-1 item should sit twice as far in")
        XCTAssertFalse(text.contains("lvl=\""))
    }
}

final class NotesOutputTests: XCTestCase {

    private let deck = Markdown.deck(from: "## A slide\n- one\n??? say this out loud")

    func testANoteReachesTheFile() throws {
        // The bug: `???` reached the model, `Slide.note` was populated, a test
        // asserted it — and no notesSlide part was ever written, so every
        // note the author typed was parsed and then dropped.
        let text = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertTrue(text.contains("ppt/notesSlides/notesSlide1.xml"))
        XCTAssertTrue(text.contains("ppt/notesMasters/notesMaster1.xml"))
        XCTAssertTrue(text.contains("say this out loud"))
    }

    func testTheSlidePointsAtItsNotes() throws {
        // Without the rel from the slide, a reader finds no notes at all —
        // which is how `has_notes_slide` stayed false while the part existed.
        let text = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertTrue(text.contains("relationships/notesSlide"))
    }

    func testADeckWithNoNotesCarriesNoNotesParts() throws {
        let plain = Markdown.deck(from: "## A slide\n- one")
        let text = String(decoding: try PPTX.data(deck: plain, design: .fallback), as: UTF8.self)
        XCTAssertFalse(text.contains("notesSlide"))
        XCTAssertFalse(text.contains("notesMaster"))
    }

    func testALinkBecomesAnExternalRelationship() throws {
        let linked = Markdown.deck(from: "## H\n- see [the docs](https://example.com)")
        let text = String(decoding: try PPTX.data(deck: linked, design: .fallback), as: UTF8.self)
        XCTAssertTrue(text.contains("relationships/hyperlink"))
        XCTAssertTrue(text.contains("TargetMode=\"External\""))
        XCTAssertTrue(text.contains("hlinkClick"))
    }
}

// MARK: - Tables, numbers, layouts and embedding

final class TableTests: XCTestCase {

    func testAPipeTableBecomesATable() {
        let deck = Markdown.deck(from: """
            ## Results
            | Tool | Result |
            |---|---|
            | one | passes |
            | two | passes |
            """)
        guard case let .table(heading, rows, header) = deck.slides[0] else {
            return XCTFail("got \(deck.slides[0].kind)")
        }
        XCTAssertEqual(heading, "Results")
        XCTAssertTrue(header)
        XCTAssertEqual(rows.count, 3, "the rule row carries no data")
        XCTAssertEqual(rows[0], ["Tool", "Result"])
        XCTAssertEqual(rows[2], ["two", "passes"])
    }

    func testALonePipeIsStillTwoColumnsNotATable() {
        // Both use the pipe, and confusing them would silently turn every
        // comparison into a one-column table.
        let deck = Markdown.deck(from: "## C\n- a\n|\n- b")
        XCTAssertEqual(deck.slides[0].kind, "columns")
    }

    func testATableWithNoRuleHasNoHeader() {
        let deck = Markdown.deck(from: "| a | b |\n| c | d |")
        guard case let .table(_, rows, header) = deck.slides[0] else { return XCTFail() }
        XCTAssertFalse(header)
        XCTAssertEqual(rows.count, 2)
    }

    func testARaggedRowIsPaddedNotDropped() throws {
        let deck = Markdown.deck(from: "| a | b | c |\n|---|---|---|\n| only one |")
        let text = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertTrue(text.contains("<a:tbl>"))
        XCTAssertTrue(text.contains("only one"))
    }

    func testItIsARealTableNotAPicture() throws {
        // The entire reason this writes PowerPoint instead of a PDF is that
        // somebody can edit a cell.
        let deck = Markdown.deck(from: "| a | b |\n|---|---|\n| 1 | 2 |")
        let text = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertTrue(text.contains("graphicFrame"))
        XCTAssertTrue(text.contains("<a:gridCol"))
        XCTAssertFalse(text.contains("<p:pic>"))
    }
}

final class SlideNumberTests: XCTestCase {

    private func design(numbers: Bool) -> Design {
        var design = Design.fallback
        design.slideNumbers = numbers
        return design
    }

    func testNumbersAreOffUnlessTheDesignAsks() {
        let layout = Layout(design: design(numbers: false))
        XCTAssertNil(layout.slideNumber(for: .points("H", items: ["a"], note: nil), number: 3))
    }

    func testAFeatureSlideCarriesNoNumber() {
        // A number on a section divider looks like a mistake.
        let layout = Layout(design: design(numbers: true))
        XCTAssertNil(layout.slideNumber(for: .title("T", subtitle: nil), number: 3))
        XCTAssertNil(layout.slideNumber(for: .section("S", subtitle: nil, note: nil), number: 3))
        XCTAssertNotNil(layout.slideNumber(for: .points("H", items: ["a"], note: nil), number: 3))
    }

    func testItIsAFieldNotATypedDigit() throws {
        // So moving a slide renumbers it.
        let deck = Deck(slides: [.points("H", items: ["a"], note: nil)])
        let text = String(decoding: try PPTX.data(deck: deck, design: design(numbers: true)), as: UTF8.self)
        XCTAssertTrue(text.contains("type=\"slidenum\""))
    }
}

final class LayoutPartTests: XCTestCase {

    func testEverySlideShapeMapsToALayoutThatExists() {
        let shapes: [Slide] = [
            .title("T", subtitle: nil), .section("S", subtitle: nil, note: nil),
            .points("P", items: ["a"], note: nil), .prose("R", body: "b", note: nil),
            .statement("S", attribution: nil), .quote("Q", attribution: nil),
            .stat(nil, figures: [(figure: "1", label: "x")], note: nil),
            .cards(nil, panels: [(title: "T", body: "b")], note: nil),
            .table(nil, rows: [["a"]], header: false),
            .columns("C", left: ["a"], right: ["b"], note: nil),
        ]
        for shape in shapes {
            let number = Layouts.number(for: shape)
            XCTAssertTrue((1...Layouts.all.count).contains(number), shape.kind)
        }
    }

    func testAHeadingSitsInATitlePlaceholder() throws {
        // Without it the outline pane shows nothing: the text is there, but
        // PowerPoint has no idea which box is the heading.
        let deck = Deck(slides: [.points("A heading", items: ["a"], note: nil)])
        let text = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertTrue(text.contains("<p:ph type=\"title\"/>"))
    }

    func testAllFourLayoutsAreWritten() throws {
        let deck = Deck(slides: [.title("T", subtitle: nil)])
        let text = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        for number in 1...4 {
            XCTAssertTrue(text.contains("ppt/slideLayouts/slideLayout\(number).xml"), "layout \(number)")
        }
    }
}

final class EmbeddingTests: XCTestCase {

    func testTheBundledFacesAreThere() {
        let faces = Embedding.bundled()
        XCTAssertEqual(faces.count, 4)
        XCTAssertEqual(Set(faces.map(\.face)), Set(Embedding.Face.allCases))
        for face in faces {
            XCTAssertTrue(Embedding.isFont(face.data), "\(face.face) is not a font")
            XCTAssertGreaterThan(face.data.count, 100_000)
        }
    }

    func testSomethingThatIsNotAFontIsRefused() {
        // A .pptx carrying a text file named .ttf opens and then renders
        // nothing, with no error anywhere.
        XCTAssertFalse(Embedding.isFont(Data("this is not a font".utf8)))
        XCTAssertFalse(Embedding.isFont(Data()))
    }

    func testEmbeddingIsOptional() throws {
        let deck = Deck(slides: [.title("T", subtitle: nil)])
        let plain = try PPTX.data(deck: deck, design: .fallback)
        let carried = try PPTX.data(deck: deck, design: .fallback, embed: Embedding.bundled())
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("fntdata"))
        XCTAssertTrue(String(decoding: carried, as: UTF8.self).contains("fntdata"))
        XCTAssertGreaterThan(carried.count, plain.count + 1_000_000)
    }

    func testTheFontElementIsInThePresentationNamespace() {
        // `a:font` renders everywhere and fails the schema: the element is
        // declared in presentationml and only borrows its TYPE from
        // DrawingML.
        let list = PPTX.embeddedFontList([(face: .regular, data: Data())],
                                         typeface: "Inter", firstRelation: 6)
        XCTAssertTrue(list.contains("<p:font typeface=\"Inter\"/>"))
        XCTAssertFalse(list.contains("<a:font"))
    }

    func testNoFontMeansNoList() {
        XCTAssertTrue(PPTX.embeddedFontList([], typeface: "Inter", firstRelation: 6).isEmpty)
    }
}

final class NoteOwnershipTests: XCTestCase {

    func testASectionsSubtitleIsNotAlsoItsNote() {
        // They were one field, so the line under a section heading was shown
        // on the slide AND written into the presenter view — and a real
        // `???` note on a section was impossible to write.
        let deck = Markdown.deck(from: """
            # First

            # How a tool gets built
            Probe first, measure second
            ??? the actual note
            """)
        guard case let .section(_, subtitle, note) = deck.slides[1] else {
            return XCTFail("got \(deck.slides[1].kind)")
        }
        XCTAssertEqual(subtitle, "Probe first, measure second")
        XCTAssertEqual(note, "the actual note")
    }

    func testAStatSlideKeepsItsNote() {
        // Parsed and then dropped: `Slide.note` had no case for stat or
        // cards, so a `???` under either vanished without a word.
        let deck = Markdown.deck(from: "## Numbers\n= 91 | tools\n??? say it runs offline")
        XCTAssertEqual(deck.slides[0].note, "say it runs offline")
    }

    func testACardSlideKeepsItsNote() {
        let deck = Markdown.deck(from: "## Promises\n:: Keyless | none needed\n??? mention the tap")
        XCTAssertEqual(deck.slides[0].note, "mention the tap")
    }

    func testEveryShapeThatCanCarryANoteWritesOne() throws {
        let shapes: [Slide] = [
            .section("S", subtitle: nil, note: "n"),
            .points("P", items: ["a"], note: "n"),
            .prose("R", body: "b", note: "n"),
            .columns("C", left: ["a"], right: ["b"], note: "n"),
            .stat("N", figures: [(figure: "1", label: "x")], note: "n"),
            .cards("C", panels: [(title: "t", body: "b")], note: "n"),
        ]
        for shape in shapes {
            let text = String(decoding: try PPTX.data(deck: Deck(slides: [shape]), design: .fallback),
                              as: UTF8.self)
            XCTAssertTrue(text.contains("notesSlide1.xml"), "\(shape.kind) lost its note")
        }
    }
}

final class BulletAppearanceTests: XCTestCase {

    func testABulletCarriesItsOwnColour() throws {
        // A buChar inherits nothing from the run beside it and falls back to
        // BLACK — a row of black dashes down the left of a navy deck.
        let deck = Markdown.deck(from: "## H\n- one\n- two")
        let design = try Designs.named("aurora")
        let text = String(decoding: try PPTX.data(deck: deck, design: design), as: UTF8.self)
        XCTAssertTrue(text.contains("<a:buClr><a:srgbClr val=\"\(design.body)\"/></a:buClr>"))
    }

    func testANumberedListIsColouredToo() throws {
        let deck = Markdown.deck(from: "## H\n1. one")
        let design = try Designs.named("aurora")
        let text = String(decoding: try PPTX.data(deck: deck, design: design), as: UTF8.self)
        XCTAssertTrue(text.contains("<a:buClr>"))
        XCTAssertTrue(text.contains("buAutoNum"))
    }

    func testColumnsStartOnTheSameLine() {
        // Centred, a three-item column floats halfway down beside a
        // five-item one and the two lists read as unrelated.
        let layout = Layout(design: .fallback)
        let boxes = layout.boxes(for: .columns("C", left: ["a", "b", "c"], right: ["d"], note: nil))
        let texts = boxes.filter { if case .text = $0.content { return true }; return false }
        XCTAssertEqual(texts.count, 3, "a heading and two columns")
        XCTAssertEqual(texts[1].y, texts[2].y)
        if case let .text(_, _, anchor) = texts[1].content {
            XCTAssertEqual(anchor, .top)
        }
    }
}

final class ContinuationTests: XCTestCase {

    func testAWrappedListItemIsNotDropped() {
        // Markdown's lazy continuation. Without it the remainder was neither
        // a bullet nor usable prose — a block with points ignores prose — so
        // half the sentence simply vanished from the slide.
        let deck = Markdown.deck(from: """
            ## H
            - Verify a framework headless against the real
              `.swiftinterface`, never against search results
            - another point
            """)
        guard case let .points(_, items, _) = deck.slides[0] else { return XCTFail() }
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].text.contains("swiftinterface"), items[0].text)
        XCTAssertTrue(items[0].text.contains("search results"))
    }

    func testProseBeforeAnyBulletIsStillProse() {
        let deck = Markdown.deck(from: "## H\na paragraph\n- and then a point")
        guard case let .points(_, items, _) = deck.slides[0] else { return XCTFail() }
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items[0].text.contains("paragraph"))
    }
}

final class LayoutGeometryTests: XCTestCase {

    func testLayoutPlaceholdersCarryNoGeometry() {
        // Given an explicit a:xfrm they are real shapes at real coordinates,
        // and a viewer that paints empty placeholders — several do — draws a
        // ghost box on every slide that uses the layout.
        for layout in Layouts.all {
            let xml = Layouts.xml(layout)
            /// One transform only: the shape tree's own, which is required.
            /// Any more means a placeholder was given coordinates.
            XCTAssertEqual(xml.components(separatedBy: "<a:xfrm").count - 1, 1,
                           "\(layout.name) positions a placeholder")
        }
    }

    func testASlideNumbersLiteralMatchesItsSlide() throws {
        let deck = Deck(slides: (1...3).map { .points("H\($0)", items: ["a"], note: nil) })
        var design = Design.fallback
        design.slideNumbers = true
        let text = String(decoding: try PPTX.data(deck: deck, design: design), as: UTF8.self)
        // The literal is only a fallback, but a deck where every slide says
        // "2" is what a reader sees in anything that does not evaluate fields.
        XCTAssertTrue(text.contains("<a:t>1</a:t>"))
        XCTAssertTrue(text.contains("<a:t>3</a:t>"))
    }
}

final class PreviewNumberingTests: XCTestCase {

    func testAOneSlideCopyKeepsTheRealNumber() throws {
        // Each preview is a one-slide copy, so without this every rendered
        // page showed "1" while the deck itself was numbered correctly — a
        // preview that disagrees with the file is worse than none.
        var design = Design.fallback
        design.slideNumbers = true
        let single = Deck(slides: [.points("H", items: ["a"], note: nil)])
        let text = String(decoding: try PPTX.data(deck: single, design: design,
                                                  firstSlideNumber: 7), as: UTF8.self)
        XCTAssertTrue(text.contains("<a:t>7</a:t>"))
    }
}
