//
//  Layout.swift
//  DeckKit
//
//  Where everything goes — one rhythm, applied to every slide shape.
//

import Foundation

/// A positioned box of text or colour.
public struct Box: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case text([Run], align: Align, anchor: Anchor)
        case fill(String)
        /// A rounded, possibly translucent and shadowed card.
        case panel(Panel)
        /// A gradient ground, which is what a flat colour used to be.
        case gradient([Stop], angle: Double)
        case picture(String)
        /// A real table, editable in PowerPoint rather than a picture of one.
        case table(rows: [[String]], header: Bool)
        /// The slide's own number, as a field rather than a typed digit.
        case slideNumber(Int, size: Double, colour: String)
    }
    public enum Align: String, Sendable { case left, centre, right }
    public enum Anchor: String, Sendable { case top, middle, bottom }

    public let x: Int, y: Int, width: Int, height: Int
    public let content: Content
    /// The placeholder this box fills, if any.
    ///
    /// A slide's title has to sit in a `title` placeholder or the outline
    /// pane shows nothing — the text is there, but PowerPoint has no idea
    /// which of the boxes is the heading.
    public var placeholder: String?

    public init(x: Int, y: Int, width: Int, height: Int,
                content: Content, placeholder: String? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.content = content
        self.placeholder = placeholder
    }
}

/// One styled paragraph.
public struct Run: Sendable, Equatable {

    /// The pieces of the line, each with its own marks.
    ///
    /// A paragraph used to be one string, so `**bold**` inside a bullet
    /// reached the slide with its asterisks intact. OOXML models it the same
    /// way — one `<a:p>` holding several `<a:r>`.
    public let spans: [Span]

    /// The whole line, unmarked. For measuring and for a manifest.
    public var text: String { spans.map(\.text).joined() }
    public let size: Double
    public let bold: Bool
    public let colour: String
    /// Space before this line, in points.
    public let spaceBefore: Double
    /// Letter-spacing in points. Negative tightens large type, which is the
    /// single change that most separates a modern heading from a dated one.
    public let tracking: Double
    /// Line spacing as a multiple, or nil for the font's own.
    public let lineSpacing: Double?

    /// The bullet or number this paragraph carries, and how deep it sits.
    public let marker: Marker
    public let level: Int

    /// Which of the design's two faces sets this run.
    ///
    /// Named on the run because the writer names it on every `<a:r>`: a
    /// face that lives only in the theme never reached a text box in Quick
    /// Look, and every deck rendered in the viewer's fallback sans while the
    /// design said Avenir Next.
    public let face: Face

    /// What sits in front of a paragraph.
    public enum Marker: Sendable, Equatable {
        case none
        /// A literal character — a dash, a dot, whatever the design says.
        case character(String)
        /// 1. 2. 3., counted by PowerPoint so an inserted line renumbers.
        case number
    }

    /// The design's heading face or its body face.
    public enum Face: Sendable, Equatable { case body, heading }

    public init(_ text: String, size: Double, bold: Bool = false,
                colour: String, spaceBefore: Double = 0,
                tracking: Double = 0, lineSpacing: Double? = nil,
                marker: Marker = .none, level: Int = 0, face: Face = .body) {
        self.init(Inline.spans(text), size: size, bold: bold, colour: colour,
                  spaceBefore: spaceBefore, tracking: tracking,
                  lineSpacing: lineSpacing, marker: marker, level: level, face: face)
    }

    public init(_ spans: [Span], size: Double, bold: Bool = false,
                colour: String, spaceBefore: Double = 0,
                tracking: Double = 0, lineSpacing: Double? = nil,
                marker: Marker = .none, level: Int = 0, face: Face = .body) {
        self.spans = spans
        self.size = size
        self.bold = bold
        self.colour = colour
        self.spaceBefore = spaceBefore
        self.tracking = tracking
        self.lineSpacing = lineSpacing
        self.marker = marker
        self.level = level
        self.face = face
    }
}

/// Turns a slide into boxes.
///
/// Every vertical position comes from the same three numbers — the margin,
/// the heading band, and the gap — so a heading sits in the same place on
/// every slide of a deck. That is the whole difference between a deck that
/// looks designed and one that looks assembled.
public struct Layout: Sendable {

    public let design: Design
    public let canvas: Canvas

    /// The least a hanging indent can be, in points. The real one is
    /// measured from the bullet — see `TextMetrics.indent(for:design:)`.
    public static let minimumIndent = 17.0

    /// Where a block with room to spare sits in that room.
    ///
    /// A little above the geometric centre, because that is where the eye
    /// reads "centred". Dead-centred, a three-line list floated in the
    /// middle of the slide with its heading stranded above it; pinned to
    /// the top, every content slide was top-heavy. This is the number
    /// between those two complaints.
    static let optical = 0.36

    public init(design: Design, canvas: Canvas = .sixteenByNine) {
        self.design = design
        self.canvas = canvas
    }

    private var margin: Int { canvas.across(design.margin) }
    private var contentWidth: Int { canvas.width - margin * 2 }
    /// The heading's box begins here on every slide that has one.
    private var gap: Int { Canvas.points(design.bodySize * design.gap) }

    /// The slide number, bottom right, when the design asks for one.
    ///
    /// Left off title and section slides, which is the convention every deck
    /// follows — a number on a section divider looks like a mistake.
    public func slideNumber(for slide: Slide, number: Int) -> Box? {
        guard design.slideNumbers else { return nil }
        switch slide {
        case .title, .section: return nil
        default: break
        }
        return Box(x: canvas.width - margin - canvas.across(0.08),
                   y: canvas.height - canvas.down(0.075),
                   width: canvas.across(0.08), height: canvas.down(0.045),
                   content: .slideNumber(number, size: design.captionSize * 0.85, colour: design.body))
    }

    /// The boxes for one slide.
    ///
    /// - Parameter kicker: the small label above the heading, if the author
    ///   wrote one.
    public func boxes(for slide: Slide, kicker: String? = nil) -> [Box] {
        /// A gradient ground on ordinary slides as well, when the design asks
        /// for one — a modern deck is rarely flat white.
        let ordinary = ground(feature: false).map { [$0] } ?? []
        switch slide {
        case let .title(text, subtitle):
            return feature(text, size: design.titleSize, secondary: subtitle,
                           kicker: kicker, isTitleSlide: true)

        case let .section(text, subtitle, _):
            return feature(text, size: design.sectionSize, secondary: subtitle, kicker: kicker)

        case let .points(heading, items, _):
            return ordinary + self.heading(heading, kicker: kicker) + [body(list(items))]

        case let .prose(heading, text, _):
            /// A shorter measure than a list. Prose set across the full slide
            /// is 120 characters a line, which nobody reads from the back of
            /// a room; 60 to 75 is the range that does.
            return ordinary + self.heading(heading, kicker: kicker) + [
                body([Run(text, size: design.bodySize, colour: design.body)],
                     width: Int(Double(contentWidth) * 0.72)),
            ]

        case let .statement(text, attribution):
            /// Optically centred and set large: the slide people remember has
            /// nothing else on it.
            var runs = [Run(text, size: design.statementSize, bold: design.headingBold,
                            colour: design.heading, tracking: design.headingTracking,
                            lineSpacing: design.lineSpacing, face: .heading)]
            if let attribution {
                /// One step down, not two. At caption size it read as a
                /// footnote beside a line four times its height.
                runs.append(Run(attribution, size: design.size(1), colour: design.body,
                                spaceBefore: design.bodySize * 1.3))
            }
            return ordinary + [Box(x: margin, y: canvas.down(0.2), width: contentWidth,
                                   height: canvas.down(0.6),
                                   content: .text(runs, align: .left, anchor: .middle))]

        case let .quote(text, attribution):
            var runs = [Run("\u{201C}\(text)\u{201D}", size: design.size(2),
                            colour: design.featureHeading, face: .heading)]
            if let attribution {
                runs.append(Run("\u{2014} \(attribution)", size: design.size(1),
                                colour: design.featureBody,
                                spaceBefore: design.bodySize * 1.3))
            }
            return [ground(feature: true)].compactMap { $0 } + [
                    Box(x: margin, y: canvas.down(0.2), width: contentWidth,
                        height: canvas.down(0.6),
                        content: .text(runs, align: .left, anchor: .middle))]

        case let .image(path, caption, heading):
            var boxes = ordinary + self.heading(heading, kicker: kicker)
            let top = heading == nil ? canvas.down(0.08) : bodyTop
            let bottom = caption == nil ? canvas.down(0.92) : canvas.down(0.84)
            /// The box the picture is fitted INTO: the writer shrinks it to
            /// the picture's own proportions and centres it here.
            boxes.append(Box(x: margin, y: top, width: contentWidth, height: bottom - top,
                             content: .picture(path)))
            if let caption {
                boxes.append(Box(x: margin, y: canvas.down(0.86), width: contentWidth,
                                 height: canvas.down(0.1),
                                 content: .text([Run(caption, size: design.captionSize,
                                                     colour: design.body)],
                                                align: .left, anchor: .top)))
            }
            return boxes

        case let .stat(heading, figures, _):
            /// Figures on cards when the design has one, bare when it does
            /// not — a stat slide is the one place a deck can be loud, and a
            /// number set small is a number nobody remembers.
            let contents = figures.map { figure in [
                Run(figure.figure, size: design.size(4), bold: design.headingBold,
                    colour: design.heading, tracking: design.headingTracking,
                    lineSpacing: design.lineSpacing, face: .heading),
                Run(figure.label, size: design.size(-1) * 1.15, colour: design.body,
                    spaceBefore: design.bodySize * 0.55,
                    tracking: design.kickerTracking * 0.5),
            ] }
            return ordinary + self.heading(heading, kicker: kicker)
                + panels(contents, anchor: .middle, underHeading: heading != nil)

        case let .cards(heading, panels, _):
            let contents = panels.map { panel in [
                Run(panel.title, size: design.size(1), bold: design.headingBold,
                    colour: design.heading, tracking: design.headingTracking * 0.5,
                    face: .heading),
                /// Body size, not caption. A card is not a footnote, and at
                /// one step down the text was smaller than the bullets
                /// beside it.
                Run(panel.body, size: design.bodySize, colour: design.body,
                    spaceBefore: design.bodySize * 0.7, lineSpacing: 1.05),
            ] }
            return ordinary + self.heading(heading, kicker: kicker)
                + self.panels(contents, anchor: .top, underHeading: heading != nil)

        case let .table(heading, rows, header):
            let head = ordinary + self.heading(heading, kicker: kicker)
            let top = heading == nil ? canvas.down(0.2) : bodyTop
            /// The frame's height is a starting point: PowerPoint grows a
            /// table to fit its rows and will not shrink below what the text
            /// needs, so asking for less than the rows require just moves the
            /// overflow rather than preventing it.
            let depth = min(canvas.height - top - canvas.down(0.12),
                            Canvas.points(design.lineHeight(design.bodySize) * 2.1 * Double(max(1, rows.count))))
            return head + [Box(x: margin, y: top, width: contentWidth, height: depth,
                               content: .table(rows: rows, header: header))]

        case let .columns(heading, left, right, _):
            let head = ordinary + self.heading(heading, kicker: kicker)
            let gutter = canvas.across(0.04)
            let column = (contentWidth - gutter) / 2
            /// Both columns start on the same line — the taller one decides
            /// where — and both are anchored to the TOP. Centred each on its
            /// own, a three-item column floated halfway down beside a
            /// five-item one and the two lists read as unrelated.
            let available = canvas.height - bodyTop - canvas.down(0.12)
            let tallest = [list(left), list(right)]
                .map { TextMetrics.height(of: $0, inWidth: column, design: design) }
                .max() ?? 0
            let top = bodyTop + Int(Double(max(0, available - Int(tallest))) * Self.optical)
            let depth = available - (top - bodyTop)
            return head + [
                Box(x: margin, y: top, width: column, height: depth,
                    content: .text(list(left), align: .left, anchor: .top)),
                Box(x: margin + column + gutter, y: top, width: column, height: depth,
                    content: .text(list(right), align: .left, anchor: .top)),
            ]
        }
    }

    // MARK: - The bands

    /// Points as paragraphs with real bullets.
    ///
    /// Not a character glued to the front of the string: PowerPoint then
    /// indents the wrap, renumbers a list when a line is inserted, and a
    /// reader editing the deck gets a list rather than a paragraph that
    /// looks like one.
    private func list(_ items: [Bullet]) -> [Run] {
        let leading = design.bodySize * design.leading
        return items.enumerated().map { index, item in
            Run(Inline.spans(item.text), size: design.bodySize, colour: design.body,
                spaceBefore: index == 0 ? 0 : leading,
                marker: item.numbered ? .number
                    : (design.bullet.isEmpty ? .none : .character(design.bullet)),
                level: item.level)
        }
    }

    /// Heading, the short rule under it, and the kicker above it.
    ///
    /// The heading box runs from the top margin down to the rule and is
    /// anchored to its BOTTOM, so it grows upward into empty space. Anchored
    /// to the top with a fixed rule below, a heading that wraps to two lines
    /// runs straight through the rule — and headings wrap on the slide, not
    /// in this code, because PowerPoint does its own line breaking.
    private func heading(_ text: String?, kicker: String?) -> [Box] {
        guard let text else {
            /// A kicker with no heading under it still labels the slide,
            /// on the heading's own line.
            return kicker.map {
                self.kicker($0, bottom: headingBandTop + Canvas.points(design.lineHeight(design.captionSize)))
            } ?? []
        }
        let top = headingBandTop
        let bottom = ruleY - Canvas.points(design.headingSize * 0.3)
        let run = Run(text, size: design.headingSize, bold: design.headingBold,
                      colour: design.heading, tracking: design.headingTracking,
                      lineSpacing: design.lineSpacing, face: .heading)
        var boxes = [Box(x: margin, y: top, width: contentWidth, height: bottom - top,
                         content: .text([run], align: .left, anchor: .bottom),
                         placeholder: "title")]
        if let kicker {
            /// Above the heading's TEXT, not its box. The box is two lines
            /// deep and bottom-anchored, so a one-line heading leaves the top
            /// of it empty, and a kicker pinned to the box would float a
            /// whole line above the words it labels.
            let textTop = bottom - Int(TextMetrics.height(of: [run], inWidth: contentWidth, design: design))
            boxes += self.kicker(kicker, bottom: textTop - Canvas.points(design.headingSize * 0.35))
        }
        if design.rule {
            /// Under the heading's band rather than under the text itself:
            /// the rule marks the grid, and a rule that moves with a one-line
            /// or two-line heading reads as a mistake.
            boxes.append(Box(x: margin, y: ruleY, width: canvas.across(0.05),
                             height: Canvas.points(3), content: .fill(design.accent)))
        }
        return boxes
    }

    /// The small label above a heading — the most recognisable single mark
    /// of a modern deck, and the cheapest. Uppercase, tracked, in the
    /// design's kicker colour, on a pill when the design has one.
    ///
    /// - Parameter bottom: where the label's box ends.
    private func kicker(_ text: String, bottom: Int) -> [Box] {
        let size = (design.captionSize * 0.8).rounded()
        let run = Run(text.uppercased(), size: size, bold: true, colour: design.kickerColour,
                      tracking: design.kickerTracking, face: .heading)
        let line = Canvas.points(design.lineHeight(size))
        guard let pill = design.kickerPill else {
            return [Box(x: margin, y: bottom - line, width: contentWidth, height: line,
                        content: .text([run], align: .left, anchor: .bottom))]
        }
        let padX = Canvas.points(size * 1.1)
        let padY = Canvas.points(size * 0.4)
        /// The tracking trails the last letter too, and a box a hair too
        /// narrow wraps the label onto a second line inside its pill.
        let width = Canvas.points(TextMetrics.width(of: run, design: design) + design.kickerTracking * 2)
            + padX * 2
        let height = line + padY * 2
        return [
            Box(x: margin, y: bottom - height, width: width, height: height, content: .panel(pill)),
            Box(x: margin + padX, y: bottom - height + padY, width: width - padX * 2, height: line,
                content: .text([run], align: .left, anchor: .middle)),
        ]
    }

    private var headingBandTop: Int { canvas.down(design.headingTop) }

    /// The rule sits **two heading lines** below the top of the band.
    ///
    /// Derived rather than chosen, so the band is deep enough for a heading
    /// that wraps — which is most of them, on a real deck. A fixed offset
    /// left the box a line short: the render looked fine, because the box is
    /// bottom-anchored and overflowed upward into empty space, but the
    /// overflow check was right to complain and the two would have kept
    /// disagreeing.
    private var ruleY: Int {
        headingBandTop + Canvas.points(design.lineHeight(design.headingSize) * 2 + design.headingSize * 0.3)
    }
    private var bodyTop: Int { ruleY + gap }

    /// The body, placed by how much of the room under the rule it needs.
    ///
    /// Measured, then set from the top at the optical point of the space it
    /// leaves. Anchoring the box to its middle did the same job without a
    /// measurement, but "middle" is not where a block looks centred — and
    /// a top-anchored box at a known y is a box the overflow check and the
    /// slide agree about.
    private func body(_ runs: [Run], width: Int? = nil) -> Box {
        let top = bodyTop
        let width = width ?? contentWidth
        let available = canvas.height - top - canvas.down(0.12)
        let needed = Int(TextMetrics.height(of: runs, inWidth: width, design: design))
        let y = top + Int(Double(max(0, available - needed)) * Self.optical)
        return Box(x: margin, y: y, width: width, height: available - (y - top),
                   content: .text(runs, align: .left, anchor: .top))
    }

    /// Cards across the slide, each as deep as the tallest one's content.
    ///
    /// Sized to what is on them, not to the slide: at a fixed 46% of the
    /// height a card holding two lines was two-thirds empty, and a stat card
    /// was a number floating in a box three times its size.
    private func panels(_ contents: [[Run]], anchor: Box.Anchor, underHeading: Bool) -> [Box] {
        let count = max(1, contents.count)
        let gutter = canvas.across(0.025)
        let width = (contentWidth - gutter * (count - 1)) / count
        let inset = design.card == nil ? 0 : canvas.across(0.018)
        let pad = canvas.down(0.045)
        let tallest = contents
            .map { TextMetrics.height(of: $0, inWidth: width - inset * 2, design: design) }
            .max() ?? 0
        let start = underHeading ? bodyTop : canvas.down(0.2)
        let available = canvas.down(0.86) - start
        let depth = min(available, max(canvas.down(0.2), Int(tallest) + pad * 2))
        let top = start + Int(Double(available - depth) * Self.optical)
        var boxes: [Box] = []
        for (index, runs) in contents.enumerated() {
            let x = margin + (width + gutter) * index
            if let card = design.card {
                boxes.append(Box(x: x, y: top, width: width, height: depth, content: .panel(card)))
            }
            boxes.append(Box(x: x + inset, y: top + pad, width: width - inset * 2, height: depth - pad * 2,
                             content: .text(runs, align: .left, anchor: anchor)))
        }
        return boxes
    }

    /// The whole slide, as a gradient when the design has one.
    private func ground(feature: Bool) -> Box? {
        let stops = feature ? design.gradient : design.bodyGradient
        if let stops, stops.count >= 2 {
            return Box(x: 0, y: 0, width: canvas.width, height: canvas.height,
                       content: .gradient(stops, angle: design.gradientAngle))
        }
        guard feature else { return nil }
        return Box(x: 0, y: 0, width: canvas.width, height: canvas.height,
                   content: .fill(design.featureBackground))
    }

    /// Title and section slides: full-bleed ground, text on the lower half.
    ///
    /// The title's box ends on a fixed line and is anchored to its bottom,
    /// so a two-line title grows upward; the subtitle starts a fixed
    /// distance below that same line, in a placeholder of its own. They
    /// used to share one box anchored to its middle — which put both in the
    /// title placeholder, so the outline pane and every reader saw
    /// "Title\nSubtitle" as the title, and the title moved whenever the
    /// subtitle wrapped.
    private func feature(_ text: String, size: Double, secondary: String?,
                         kicker: String?, isTitleSlide: Bool = false) -> [Box] {
        var boxes = [ground(feature: true)].compactMap { $0 }
        let top = canvas.down(0.12)
        let baseline = canvas.down(secondary == nil ? 0.60 : 0.56)
        let run = Run(text, size: size, bold: design.headingBold, colour: design.featureHeading,
                      tracking: design.headingTracking, lineSpacing: design.lineSpacing,
                      face: .heading)
        if let kicker {
            let textTop = baseline - Int(TextMetrics.height(of: [run], inWidth: contentWidth, design: design))
            boxes += self.kicker(kicker, bottom: textTop - Canvas.points(size * 0.3))
        }
        boxes.append(Box(x: margin, y: top, width: contentWidth, height: baseline - top,
                         content: .text([run], align: .left, anchor: .bottom),
                         placeholder: isTitleSlide ? "ctrTitle" : "title"))
        if let secondary {
            /// One step up from body. At body size the line under a 72pt
            /// title was a quarter of its height and read as a footnote.
            let y = baseline + Canvas.points(design.bodySize)
            boxes.append(Box(x: margin, y: y, width: contentWidth, height: canvas.down(0.78) - y,
                             content: .text([Run(secondary, size: design.size(1),
                                                 colour: design.featureBody)],
                                            align: .left, anchor: .top),
                             placeholder: isTitleSlide ? "subTitle" : "body"))
        }
        if design.rule {
            boxes.append(Box(x: margin, y: canvas.down(0.80), width: canvas.across(0.05),
                             height: Canvas.points(3), content: .fill(design.accent)))
        }
        return boxes
    }
}
