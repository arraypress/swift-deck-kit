//
//  AuditTests.swift
//  DeckKit
//
//  What a second renderer found that the first one hid. Quick Look is
//  lenient; LibreOffice and a probe deck set in Impact were not.
//

import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import DeckKit

final class FaceTests: XCTestCase {

    /// Every `<a:r>` on a slide, as the inside of its `<a:rPr>`.
    private func runProperties(_ xml: String) -> [String] {
        xml.components(separatedBy: "<a:r><a:rPr").dropFirst().map { piece in
            piece.range(of: "</a:rPr>").map { String(piece[..<$0.lowerBound]) } ?? piece
        }
    }

    func testEveryRunNamesItsFace() throws {
        // The theme carries the fonts, but a text box inherits nothing from
        // it in Quick Look: set in Impact, the deck rendered in Helvetica.
        let deck = Markdown.deck(from: """
            # Title
            a subtitle
            ## Points
            - one with **bold** and `code`
            ## Cards
            :: A | b
            = 9 | nine
            | a | b |
            |---|---|
            | c | d |
            """)
        let xml = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        let runs = runProperties(xml)
        XCTAssertGreaterThan(runs.count, 10)
        for run in runs {
            XCTAssertTrue(run.contains("<a:latin typeface=\""), "a run without a face: \(run.prefix(80))")
        }
    }

    func testHeadingsAndBodyUseTheDesignsOwnFaces() throws {
        var design = Design.fallback
        design.headingFont = "Futura"
        design.bodyFont = "Georgia"
        let deck = Deck(slides: [.points("A heading", items: ["a point"], note: nil)])
        let xml = String(decoding: try PPTX.data(deck: deck, design: design), as: UTF8.self)
        XCTAssertTrue(xml.contains("<a:latin typeface=\"Futura\"/></a:rPr><a:t>A heading"))
        XCTAssertTrue(xml.contains("<a:latin typeface=\"Georgia\"/></a:rPr><a:t>a point"))
    }

    func testCodeKeepsItsOwnFace() throws {
        let deck = Deck(slides: [.points("H", items: ["see `main.swift` here"], note: nil)])
        let xml = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertTrue(xml.contains("<a:latin typeface=\"\(PPTX.codeFace)\"/></a:rPr><a:t>main.swift"))
    }

    func testTextBoxesDoNotAutofit() throws {
        // `normAutofit` invites every reader to shrink text by its own
        // rule; the layout is measured, and the check catches overflow.
        let deck = Deck(slides: [.points("H", items: ["a"], note: nil)])
        let xml = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertTrue(xml.contains("<a:noAutofit/>"))
        XCTAssertFalse(xml.contains("<a:normAutofit"))
    }

    func testRunsAreKerned() throws {
        let deck = Deck(slides: [.title("AV To", subtitle: nil)])
        let xml = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertTrue(xml.contains("kern=\"1200\""))
    }
}

final class PlaceholderTests: XCTestCase {

    func testTheSubtitleHasAPlaceholderOfItsOwn() throws {
        // Both lines sat in the title placeholder, so python-pptx read the
        // title as "Ninety-one tools, one Mac\nBuilt for agents…".
        /// The slide part alone: the layout carries the same placeholders,
        /// empty, and so does the content-types list by name.
        let boxes = Layout(design: .fallback).boxes(for: .title("The title", subtitle: "the subtitle"))
        let xml = PPTX.slideXML(boxes, media: [:], canvas: .sixteenByNine, design: .fallback)
        XCTAssertTrue(xml.contains("<p:ph type=\"ctrTitle\"/>"))
        XCTAssertTrue(xml.contains("<p:ph type=\"subTitle\" idx=\"1\"/>"))
        let title = xml.range(of: "<p:ph type=\"ctrTitle\"/>")!.upperBound
        let subtitle = xml.range(of: "<p:ph type=\"subTitle\" idx=\"1\"/>")!.upperBound
        let titleShape = xml[title..<subtitle]
        XCTAssertTrue(titleShape.contains("The title"))
        XCTAssertFalse(titleShape.contains("the subtitle"))
    }

    func testASectionsSubtitleIsItsBody() throws {
        let deck = Deck(slides: [.title("T", subtitle: nil), .section("S", subtitle: "under", note: nil)])
        let xml = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertTrue(xml.contains("<p:ph type=\"body\" idx=\"1\"/>"))
    }

    func testATitleWithoutASubtitleSitsOnTheSameLine() {
        // The title's box ends on the same baseline either way; only the
        // subtitle box comes and goes.
        let layout = Layout(design: .fallback)
        func titleBottom(_ subtitle: String?) -> Int? {
            layout.boxes(for: .title("T", subtitle: subtitle))
                .first { $0.placeholder == "ctrTitle" }.map { $0.y + $0.height }
        }
        XCTAssertNotNil(titleBottom(nil))
        XCTAssertNotNil(titleBottom("s"))
        XCTAssertGreaterThanOrEqual(titleBottom(nil)!, titleBottom("s")!)
    }
}

final class PictureTests: XCTestCase {

    private func png(width: Int, height: Int) throws -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testAPicturesSizeIsReadWithoutDecodingIt() throws {
        let size = ImageSize.of(try png(width: 20, height: 60))
        XCTAssertEqual(size?.width, 20)
        XCTAssertEqual(size?.height, 60)
        XCTAssertNil(ImageSize.of(Data("not a picture".utf8)))
    }

    func testATallPictureStaysTall() {
        // A 1:3 portrait arrived on the slide as a 3:1 landscape.
        let box = Box(x: 100, y: 200, width: 3000, height: 1000, content: .picture("p"))
        let fitted = ImageSize.fit(width: 400, height: 1200, in: box)
        XCTAssertEqual(fitted.height, 1000)
        XCTAssertEqual(fitted.width, 333)
        XCTAssertEqual(fitted.y, 200)
        XCTAssertEqual(fitted.x, 100 + (3000 - 333) / 2, "centred in the box it was offered")
    }

    func testAWidePictureIsNotEnlarged() {
        let box = Box(x: 0, y: 0, width: 3000, height: 1000, content: .picture("p"))
        let fitted = ImageSize.fit(width: 3000, height: 1000, in: box)
        XCTAssertEqual(fitted.width, 3000)
        XCTAssertEqual(fitted.height, 1000)
    }

    func testTheWrittenFrameHasThePicturesProportions() throws {
        let deck = Deck(slides: [.image("tall.png", caption: nil, heading: "H")])
        let images = ["tall.png": try png(width: 10, height: 30)]
        let xml = String(decoding: try PPTX.data(deck: deck, design: .fallback, images: images), as: UTF8.self)
        let pic = xml.range(of: "<p:pic>")!.upperBound
        let ext = xml[pic...].range(of: "<a:ext cx=\"")!.upperBound
        let numbers = xml[ext...].prefix(40).split(whereSeparator: { !$0.isNumber })
        let cx = Int(numbers[0])!, cy = Int(numbers[1])!
        XCTAssertEqual(Double(cy) / Double(cx), 3, accuracy: 0.01)
    }
}

final class TableBorderTests: XCTestCase {

    func testOnlyTheBottomEdgeIsDrawn() throws {
        // Left unsaid, LibreOffice filled the other three in from its own
        // default and drew a black grid round every cell.
        let deck = Deck(slides: [.table("T", rows: [["a", "b"], ["c", "d"]], header: true)])
        let xml = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertTrue(xml.contains("<a:lnL><a:noFill/></a:lnL><a:lnR><a:noFill/></a:lnR><a:lnT><a:noFill/></a:lnT><a:lnB w="))
    }
}

final class KickerTests: XCTestCase {

    func testAKickerIsReadFromAboveItsHeading() {
        let deck = Markdown.deck(from: """
            # T
            ^ Results
            ## The numbers
            - a
            ^ Also
            = 9 | nine
            """)
        XCTAssertEqual(deck.slides.map(\.kind), ["title", "points", "stat"])
        XCTAssertEqual(deck.kickers, [1: "Results", 2: "Also"])
        XCTAssertEqual(deck.slides[1].texts, ["The numbers", "a"], "the kicker line is not prose")
    }

    func testAKickerIsSetAboveTheHeadingInCapitals() throws {
        let design = try Designs.named("aurora")
        let layout = Layout(design: design)
        let boxes = layout.boxes(for: .points("The numbers", items: ["a"], note: nil), kicker: "Results")
        let heading = boxes.first { $0.placeholder == "title" }!
        let kicker = boxes.first {
            if case let .text(runs, _, _) = $0.content { return runs.first?.text == "RESULTS" }
            return false
        }
        XCTAssertNotNil(kicker)
        XCTAssertLessThan(kicker!.y + kicker!.height, heading.y + heading.height)
        XCTAssertTrue(boxes.contains { if case .panel = $0.content { return true }; return false },
                      "aurora sets its kicker on a pill")
    }

    func testAKickerReachesTheFileAndThePreviewCopy() throws {
        let deck = Deck(slides: [.points("H", items: ["a"], note: nil)], kickers: [0: "Part one"])
        let xml = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertTrue(xml.contains("<a:t>PART ONE</a:t>"))
    }

    func testNoKickerNoBoxes() {
        let layout = Layout(design: .fallback)
        let plain = layout.boxes(for: .points("H", items: ["a"], note: nil))
        let kicked = layout.boxes(for: .points("H", items: ["a"], note: nil), kicker: "K")
        XCTAssertEqual(kicked.count, plain.count + 1)
    }
}

final class MeasuredPlacementTests: XCTestCase {

    private func panel(_ slide: Slide, design: Design) -> Box? {
        Layout(design: design).boxes(for: slide).first {
            if case .panel = $0.content { return true }
            return false
        }
    }

    func testACardIsAsDeepAsItsContentNotTheSlide() throws {
        let design = try Designs.named("aurora")
        let short = panel(.cards("H", panels: [(title: "A", body: "one line")], note: nil), design: design)!
        let long = panel(.cards("H", panels: [(title: "A", body: String(repeating: "many words wrap here ", count: 12))], note: nil), design: design)!
        XCTAssertLessThan(short.height, Canvas.sixteenByNine.down(0.30))
        XCTAssertGreaterThan(long.height, short.height)
    }

    func testAStatCardHoldsItsFigureWithRoomAndNoMore() throws {
        let design = try Designs.named("aurora")
        let card = panel(.stat("H", figures: [(figure: "91", label: "tools")], note: nil), design: design)!
        XCTAssertLessThan(card.height, Canvas.sixteenByNine.down(0.34))
        XCTAssertGreaterThan(card.height, Canvas.sixteenByNine.down(0.18))
    }

    func testAShortListSitsAboveCentreNotSunk() {
        let layout = Layout(design: .fallback)
        let boxes = layout.boxes(for: .points("H", items: ["one"], note: nil))
        let body = boxes.last { if case .text = $0.content { return true }; return false }!
        let heading = boxes.first { $0.placeholder == "title" }!
        let region = (top: heading.y + heading.height, bottom: Canvas.sixteenByNine.height)
        let centre = (region.top + region.bottom) / 2
        XCTAssertGreaterThan(body.y, region.top)
        XCTAssertLessThan(body.y, centre)
    }

    func testALongListStartsAtTheTopOfItsRoom() {
        let layout = Layout(design: .fallback)
        let items = (1...14).map { Bullet("point number \($0) which wraps a little", level: 0) }
        let boxes = layout.boxes(for: .points("H", items: items, note: nil))
        let body = boxes.last { if case .text = $0.content { return true }; return false }!
        let one = layout.boxes(for: .points("H", items: ["one"], note: nil))
            .last { if case .text = $0.content { return true }; return false }!
        XCTAssertLessThan(body.y, one.y)
    }

    func testMeasurementUsesTheRunsOwnFace() {
        var design = Design.fallback
        design.headingFont = "Impact"
        design.bodyFont = "Georgia"
        let text = "The quick brown fox jumps over the lazy dog"
        let narrow = TextMetrics.width(of: Run(text, size: 30, colour: "000000", face: .heading), design: design)
        let wide = TextMetrics.width(of: Run(text, size: 30, colour: "000000", face: .body), design: design)
        XCTAssertLessThan(narrow, wide, "Impact is condensed; Georgia is not")
    }
}

final class IndentTests: XCTestCase {

    func testTheHangingIndentClearsTheBullet() {
        // An em dash at 85% of the body size is wider than the 17pt the
        // indent used to be; the text started on top of it.
        let design = Design.fallback
        let dash = TextMetrics.indent(for: .character("\u{2014}"), design: design)
        let dot = TextMetrics.indent(for: .character("\u{2022}"), design: design)
        XCTAssertGreaterThan(dash, design.bodySize * 0.85, "the em dash alone is an em wide")
        XCTAssertGreaterThanOrEqual(dot, Layout.minimumIndent)
        XCTAssertGreaterThan(dash, dot)
    }

    func testTheWrittenIndentIsTheMeasuredOne() throws {
        let design = Design.fallback
        let deck = Deck(slides: [.points("H", items: ["a"], note: nil)])
        let xml = String(decoding: try PPTX.data(deck: deck, design: design), as: UTF8.self)
        let step = Canvas.points(TextMetrics.indent(for: .character(design.bullet), design: design))
        XCTAssertTrue(xml.contains("marL=\"\(step)\" indent=\"-\(step)\""))
    }

    func testColumnsStartOnTheSameLine() {
        let layout = Layout(design: .fallback)
        let boxes = layout.boxes(for: .columns("C", left: ["a"], right: ["d", "e", "f", "g", "h"], note: nil))
        let columns = boxes.filter { $0.placeholder == nil }.compactMap { box -> Box? in
            if case .text = box.content { return box }
            return nil
        }
        XCTAssertEqual(columns.count, 2)
        XCTAssertEqual(columns[0].y, columns[1].y)
    }
}
