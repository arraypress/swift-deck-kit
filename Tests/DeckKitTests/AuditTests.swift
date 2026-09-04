//
//  AuditTests.swift
//  DeckKit
//
//  What a second renderer found that the first one hid. Quick Look is
//  lenient; LibreOffice and a probe deck set in Impact were not.
//

import CoreGraphics
import ImageIO
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

final class ShapeIdentityTests: XCTestCase {

    func testShapeIdsAreUniqueAcrossTheWholeDeck() throws {
        // Quick Look places effect shapes by id at document scope: with ids
        // restarting on every slide, a card from slide 3 was drawn on every
        // later slide that had a shape numbered the same.
        let design = try Designs.named("aurora")
        let deck = Markdown.deck(from: """
            # T
            ## Cards
            :: A | a
            :: B | b
            ^ K
            ## Points
            - one
            | x | y |
            |---|---|
            | 1 | 2 |
            """)
        let layout = Layout(design: design)
        var seen: Set<Int> = []
        for (index, slide) in deck.slides.enumerated() {
            let xml = PPTX.slideXML(layout.boxes(for: slide, kicker: deck.kickers[index]),
                                    media: [:], canvas: .sixteenByNine, design: design, slide: index + 1)
            for match in xml.components(separatedBy: "<p:cNvPr id=\"").dropFirst() {
                let id = Int(match.prefix { $0.isNumber })!
                guard id != 1 else { continue }   // the group shape every slide has
                XCTAssertTrue(seen.insert(id).inserted, "shape id \(id) is reused on slide \(index + 1)")
            }
        }
        XCTAssertGreaterThan(seen.count, 10)
    }
}

final class CompositingTests: XCTestCase {

    func testATranslucentFillCompositesOverTheGround() {
        XCTAssertEqual(Colour.blend("FFFFFF", alpha: 0.07, over: "0E1527"), "1F2536")
        XCTAssertEqual(Colour.blend("FFFFFF", alpha: 1, over: "000000"), "FFFFFF", "opaque is untouched")
        XCTAssertEqual(Colour.blend("FFFFFF", alpha: 0, over: "0E1527"), "0E1527")
        XCTAssertEqual(Colour.blend("nope", alpha: 0.5, over: "000000"), "nope", "unparseable stays as written")
    }

    func testAGradientGroundBlendsAgainstItsMiddle() throws {
        XCTAssertEqual(Colour.average(["0B1120", "121A2E"]), "0E1527")
        let design = try Designs.named("aurora")
        let boxes = Layout(design: design).boxes(for: .points("H", items: ["a"], note: nil))
        XCTAssertEqual(PPTX.groundColour(of: boxes, canvas: .sixteenByNine, design: design), "0E1527")
        let rule = Design.fallback
        let plain = Layout(design: rule).boxes(for: .points("H", items: ["a"], note: nil))
        XCTAssertEqual(PPTX.groundColour(of: plain, canvas: .sixteenByNine, design: rule), rule.background,
                       "the accent rule is a fill, but not the ground")
    }
}

final class QuickLookTests: XCTestCase {

    /// Runs the real generator. Every earlier probe used two slides, and a
    /// two-slide deck never leaks — this one is ten.
    func testQuickLookPlacesNoAttachmentsForTheBundledDesigns() throws {
        let ql = URL(fileURLWithPath: "/usr/bin/qlmanage")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: ql.path), "no Quick Look on this machine")
        let deck = Markdown.deck(from: """
            # T
            sub
            ^ K
            ## S
            = 1 | a
            = 2 | b
            = 3 | c
            ## C
            :: A | a
            :: B | b
            :: C | c
            # D
            sub
            ^ K2
            ## P
            - one
            - two
            ## T
            | a | b |
            |---|---|
            | 1 | 2 |
            ! Statement
            ## Q
            - x
            |
            - y
            ^ K3
            # E
            sub
            ## L
            1. one
            """)
        XCTAssertGreaterThanOrEqual(deck.slides.count, 10)
        for name in ["aurora", "daylight"] {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deck-ql-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("\(name).pptx")
            try PPTX.data(deck: deck, design: try Designs.named(name)).write(to: file)
            let process = Process()
            process.executableURL = ql
            process.arguments = ["-p", "-o", dir.path, file.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            let html = dir.appendingPathComponent("\(name).pptx.qlpreview/Preview.html")
            guard let preview = try? String(contentsOf: html, encoding: .utf8) else {
                throw XCTSkip("Quick Look wrote no preview for \(name)")
            }
            let placed = preview.components(separatedBy: "src=\"Attachment").count - 1
            XCTAssertEqual(placed, 0, "\(name): Quick Look rendered \(placed) attachments, which leak onto other slides")
        }
    }
}

final class FurnitureTests: XCTestCase {

    func testDirectivesAreReadAndRemovedFromTheText() {
        let deck = Markdown.deck(from: """
            logo: mark.png
            footer: Acme · 2026
            transition: fade
            build: yes

            # T
            ## P
            - one
            """)
        XCTAssertEqual(deck.logo, "mark.png")
        XCTAssertEqual(deck.footer, "Acme · 2026")
        XCTAssertEqual(deck.transition, .fade)
        XCTAssertTrue(deck.builds)
        XCTAssertEqual(deck.slides.map(\.kind), ["title", "points"], "a directive is not a slide")
        XCTAssertEqual(deck.imagePaths, ["mark.png"])
    }

    func testTheLogoSitsOnEverySlideAndTheFooterOnContentSlides() {
        let layout = Layout(design: .fallback)
        let context = Layout.Context(logo: "m.png", footer: "Acme", imageSizes: ["m.png": (300, 100)])
        func pictures(_ slide: Slide) -> Int {
            layout.boxes(for: slide, context: context).filter { if case .picture = $0.content { return true }; return false }.count
        }
        func hasFooter(_ slide: Slide) -> Bool {
            layout.boxes(for: slide, context: context).contains {
                if case let .text(runs, _, _) = $0.content { return runs.first?.text == "Acme" }
                return false
            }
        }
        XCTAssertEqual(pictures(.title("T", subtitle: nil)), 1)
        XCTAssertEqual(pictures(.points("P", items: ["a"], note: nil)), 1)
        XCTAssertTrue(hasFooter(.points("P", items: ["a"], note: nil)))
        XCTAssertFalse(hasFooter(.title("T", subtitle: nil)), "a title slide carries the mark, not the footer")
        let logo = layout.boxes(for: .points("P", items: ["a"], note: nil), context: context)
            .first { if case .picture = $0.content { return true }; return false }!
        XCTAssertEqual(logo.width, logo.height * 3, accuracy: 2, "the mark keeps its proportions")
    }
}

final class CompositionTests: XCTestCase {

    func testAPictureAmongPointsIsASplitOnTheSideItWasWritten() {
        let left = Markdown.deck(from: "## H\n![c](p.png)\n- a\n- b\n").slides[0]
        let right = Markdown.deck(from: "## H\n- a\n- b\n![](p.png)\n").slides[0]
        guard case let .split(_, items, image, caption, imageLeft, _) = left else { return XCTFail("\(left.kind)") }
        XCTAssertEqual(items.map(\.text), ["a", "b"])
        XCTAssertEqual(image, "p.png")
        XCTAssertEqual(caption, "c")
        XCTAssertTrue(imageLeft)
        guard case let .split(_, _, _, _, rightSide, _) = right else { return XCTFail("\(right.kind)") }
        XCTAssertFalse(rightSide)
    }

    func testAPictureUnderATitleIsTheCover() {
        let deck = Markdown.deck(from: "# T\nsub\n![](photo.jpg)\n\n## P\n- a\n\n# S\n![](photo.jpg)\n")
        XCTAssertEqual(deck.slides.map(\.kind), ["cover", "points", "cover"])
        guard case let .cover(text, subtitle, image, first) = deck.slides[0] else { return XCTFail() }
        XCTAssertEqual([text, subtitle ?? "", image], ["T", "sub", "photo.jpg"])
        XCTAssertTrue(first)
        XCTAssertEqual(deck.title, "T")
        XCTAssertEqual(deck.sections, ["S"], "a later cover is a section")
        XCTAssertTrue(deck.slides[2].isSection)
    }

    func testACoverIsCroppedAndDarkenedNotOverlaid() throws {
        let deck = Deck(slides: [.cover("T", subtitle: nil, image: "p.png", first: true)])
        let context = CGContext(data: nil, width: 40, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 40, height: 10))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil); CGImageDestinationFinalize(destination)
        let xml = String(decoding: try PPTX.data(deck: deck, design: .fallback, images: ["p.png": data as Data]), as: UTF8.self)
        XCTAssertTrue(xml.contains("<a:srcRect l=\""), "a 4:1 picture on a 16:9 slide is cropped at the sides")
        XCTAssertTrue(xml.contains("-dim.jpg"), "the darkened copy is what the slide shows")
        XCTAssertFalse(xml.contains("<a:alpha val="))
        let dimmed = Darken.apply(data as Data, amount: 0.5)!
        let pixel = ImageSize.of(dimmed)
        XCTAssertEqual(pixel?.width, 40)
    }

    func testTheAgendaListsTheSectionsAndEveryDividerMarksItsOwn() {
        let deck = Markdown.deck(from: "# T\n## Agenda\n[agenda]\n# One\n## P\n- a\n# Two\n")
        XCTAssertEqual(deck.slides.map(\.kind), ["title", "agenda", "section", "points", "section"])
        XCTAssertEqual(deck.sections, ["One", "Two"])
        XCTAssertTrue(deck.hasAgenda)
        let layout = Layout(design: .fallback)
        let agenda = layout.boxes(for: deck.slides[1], context: deck.context(for: 1))
        let list = agenda.compactMap { box -> [Run]? in if case let .text(runs, _, _) = box.content, runs.count == 2 { return runs }; return nil }.first
        XCTAssertEqual(list?.map(\.text), ["One", "Two"])
        XCTAssertEqual(list?.first?.marker, .number)
        let divider = layout.boxes(for: deck.slides[4], context: deck.context(for: 4))
        let marks = divider.compactMap { box -> [Run]? in if case let .text(runs, _, _) = box.content, runs.count == 2 { return runs }; return nil }.first
        XCTAssertEqual(marks?.map(\.bold), [false, true], "the second divider marks the second section")
    }
}

final class ChartTests: XCTestCase {

    let rows = [["Quarter", "2025", "2026"], ["Q1", "10", "14"], ["Q2", "1,400", "18%"]]

    func testATableUnderAChartMarkerIsAChart() {
        let deck = Markdown.deck(from: "## Sales\n[chart pie]\n| A | B |\n|---|---|\n| x | 1 |\n\n## Plain\n| A | B |\n|---|---|\n| x | 1 |\n")
        XCTAssertEqual(deck.slides.map(\.kind), ["chart", "table"])
        guard case let .chart(_, kind, _, header, native, _) = deck.slides[0] else { return XCTFail() }
        XCTAssertFalse(native)
        XCTAssertEqual(kind, .pie)
        XCTAssertTrue(header)
        XCTAssertEqual(ChartKind(word: "donut"), .doughnut)
        XCTAssertEqual(ChartKind(word: "bars"), .bar)
        XCTAssertNil(ChartKind(word: "scatter"))
    }

    func testTheTableIsReadAsCategoriesAndSeries() {
        let data = Charts.Data(rows: rows, header: true)
        XCTAssertEqual(data.categoryTitle, "Quarter")
        XCTAssertEqual(data.categories, ["Q1", "Q2"])
        XCTAssertEqual(data.series.map(\.name), ["2025", "2026"])
        XCTAssertEqual(data.series[0].values, [10, 1400], "a thousands separator is not a decimal")
        XCTAssertEqual(data.series[1].values, [14, 18])
        XCTAssertEqual(Charts.column(0), "A"); XCTAssertEqual(Charts.column(25), "Z"); XCTAssertEqual(Charts.column(26), "AA")
    }

    func testTheChartPartIsWrittenTheWayPowerPointWritesOne() throws {
        // Cached references into a sheet, not literals: Quick Look left a
        // literal-data chart blank, and a series name cannot be a strLit.
        let deck = Deck(slides: [.chart("S", kind: .column, rows: rows, header: true, native: false, note: nil)])
        let bytes = try PPTX.data(deck: deck, design: try Designs.named("aurora"))
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(text.contains("ppt/charts/chart1.xml"))
        XCTAssertTrue(text.contains("ppt/embeddings/Microsoft_Excel_Sheet1.xlsx"))
        XCTAssertTrue(text.contains("<c:f>Sheet1!$B$2:$B$3</c:f>"))
        XCTAssertTrue(text.contains("<c:strRef><c:f>Sheet1!$C$1</c:f>"))
        XCTAssertFalse(text.contains("strLit"))
        XCTAssertTrue(text.contains("<c:axId val=\"500000001\"/>"), "axis ids are unsigned, as the schema says")
        XCTAssertTrue(text.contains("relationships/chart\" Target=\"../charts/chart1.xml\""))
        XCTAssertTrue(text.contains("<c:chart xmlns:c="))
        XCTAssertTrue(text.contains("<a:latin typeface=\"Avenir Next\"/></a:defRPr>"), "the chart's text names its face")
    }

    func testEveryKindWritesItsOwnPlot() throws {
        for kind in ChartKind.allCases {
            let deck = Deck(slides: [.chart(nil, kind: kind, rows: rows, header: true, native: true, note: nil)])
            let text = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
            let element = ["bar": "barChart", "column": "barChart", "line": "lineChart",
                           "pie": "pieChart", "doughnut": "doughnutChart", "area": "areaChart"][kind.rawValue]!
            XCTAssertTrue(text.contains("<c:\(element)>"), kind.rawValue)
        }
        let pie = String(decoding: try PPTX.data(deck: Deck(slides: [.chart(nil, kind: .pie, rows: rows, header: true, native: true, note: nil)]), design: .fallback), as: UTF8.self)
        XCTAssertEqual(pie.components(separatedBy: "<c:dPt>").count - 1, 2, "one colour per slice")
        XCTAssertTrue(pie.contains("<c:showPercent val=\"1\"/>"))
    }

    func testAPieIsDrawnUnlessAskedForNative() throws {
        // Quick Look draws a native pie as one circle in one colour.
        let drawn = String(decoding: try PPTX.data(deck: Deck(slides: [.chart("P", kind: .pie, rows: rows, header: true, native: false, note: nil)]), design: try Designs.named("aurora")), as: UTF8.self)
        XCTAssertFalse(drawn.contains("<c:pieChart>"))
        XCTAssertFalse(drawn.contains("ppt/charts/"))
        XCTAssertTrue(drawn.contains("<p:pic>"), "placed as a picture")
        XCTAssertTrue(drawn.contains("ppt/media/image1.png"))
        let native = Markdown.deck(from: "## P\n[chart pie native]\n| a | b |\n|---|---|\n| x | 1 |\n").slides[0]
        guard case let .chart(_, _, _, _, isNative, _) = native else { return XCTFail() }
        XCTAssertTrue(isNative)
        let image = ChartImage.pie(Charts.Data(rows: rows, header: true), doughnut: true, design: .fallback, width: 800, height: 400)
        XCTAssertNotNil(image)
        XCTAssertEqual(ImageSize.of(image!)?.width, 1600, "drawn at two pixels per point")
    }

    func testAChartSitsOnACardWhenTheDesignHasOne() throws {
        let boxes = Layout(design: try Designs.named("aurora")).boxes(for: .chart("C", kind: .column, rows: rows, header: true, native: false, note: nil))
        let card = boxes.first { if case .panel = $0.content { return true }; return false }
        let chart = boxes.first { if case .chart = $0.content { return true }; return false }
        XCTAssertNotNil(card); XCTAssertNotNil(chart)
        XCTAssertEqual(card?.x, chart?.x); XCTAssertEqual(card?.width, chart?.width)
        XCTAssertEqual(card?.height, chart?.height, "the frame is the card, so Quick Look's frame is the card's edge")
    }

    func testThePaletteTurnsTheAccentIntoDistinctHues() {
        let palette = Design.fallback.chartPalette
        XCTAssertEqual(palette.count, 8)
        XCTAssertEqual(palette[0], Design.fallback.accent)
        XCTAssertEqual(Set(palette).count, 8)
        XCTAssertEqual(try Designs.named("aurora").chartPalette.count, 6, "the modern designs name their own")
        XCTAssertEqual(Colour.rotate("FF0000", by: 120), "00FF00")
        XCTAssertEqual(Colour.rotate("FF0000", by: 240), "0000FF")
        var own = Design.fallback; own.chartColours = ["112233"]
        XCTAssertEqual(own.chartPalette, ["112233"])
    }
}

final class TimingTests: XCTestCase {

    func testATransitionAndABuildReachTheSlide() throws {
        let deck = Deck(slides: [.points("H", items: ["a", "b", "c"], note: nil)], transition: .fade, builds: true)
        let text = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertTrue(text.contains("</p:clrMapOvr><p:transition spd=\"med\"><p:fade/></p:transition><p:timing>"))
        XCTAssertEqual(text.components(separatedBy: "nodeType=\"clickEffect\"").count - 1, 3, "one click per point")
        XCTAssertTrue(text.contains("<p:pRg st=\"2\" end=\"2\"/>"))
        let spid = text.components(separatedBy: "<p:bldP spid=\"")[1].prefix { $0.isNumber }
        XCTAssertTrue(text.contains("<p:cNvPr id=\"\(spid)\" name=\"text\(spid)\"/>"), "the build targets a text box on the slide")
        XCTAssertTrue(text.contains("<p:spTgt spid=\"\(spid)\"><p:txEl><p:pRg st=\"0\" end=\"0\"/>"))
    }

    func testNothingIsWrittenWhenNothingWasAsked() throws {
        let deck = Deck(slides: [.points("H", items: ["a"], note: nil)])
        let text = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertFalse(text.contains("<p:transition"))
        XCTAssertFalse(text.contains("<p:timing>"))
        XCTAssertEqual(Timing.builds([]), "")
    }

    func testAHeadingIsNotABuildTarget() throws {
        let deck = Deck(slides: [.prose("H", body: "b", note: nil)], builds: true)
        let text = String(decoding: try PPTX.data(deck: deck, design: .fallback), as: UTF8.self)
        XCTAssertFalse(text.contains("<p:timing>"), "prose has no list to build")
    }
}

final class PDFTests: XCTestCase {

    func testTheFontConfigurationNamesTheSystemFolders() {
        let conf = PDF.fontConfiguration(cache: "/tmp/x")
        XCTAssertTrue(conf.contains("<dir>/System/Library/Fonts</dir>"))
        XCTAssertTrue(conf.contains("<cachedir>/tmp/x</cachedir>"))
    }

    func testWithoutLibreOfficeTheErrorSaysSo() {
        // Only meaningful where it is not installed; where it is, render.
        guard PDF.libreOffice == nil else { return }
        XCTAssertThrowsError(try PDF.render(URL(fileURLWithPath: "/nowhere.pptx"), to: URL(fileURLWithPath: "/nowhere.pdf"))) {
            guard case DeckError.noLibreOffice = $0 else { return XCTFail("\($0)") }
        }
    }
}

final class ResourceTests: XCTestCase {

    func testTheDesignsAreFoundThroughTheResourceBundle() throws {
        // Six bundled designs and four faces: the bundle resolved.
        XCTAssertGreaterThanOrEqual(Designs.all.count, 6)
        XCTAssertEqual(Embedding.bundled().count, 4)
        XCTAssertTrue(Resources.bundle.bundlePath.hasSuffix("DeckKit_DeckKit.bundle"))
    }
}
