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

    /// What sits in front of a paragraph.
    public enum Marker: Sendable, Equatable {
        case none
        /// A literal character — a dash, a dot, whatever the design says.
        case character(String)
        /// 1. 2. 3., counted by PowerPoint so an inserted line renumbers.
        case number
    }

    public init(_ text: String, size: Double, bold: Bool = false,
                colour: String, spaceBefore: Double = 0,
                tracking: Double = 0, lineSpacing: Double? = nil,
                marker: Marker = .none, level: Int = 0) {
        self.init(Inline.spans(text), size: size, bold: bold, colour: colour,
                  spaceBefore: spaceBefore, tracking: tracking,
                  lineSpacing: lineSpacing, marker: marker, level: level)
    }

    public init(_ spans: [Span], size: Double, bold: Bool = false,
                colour: String, spaceBefore: Double = 0,
                tracking: Double = 0, lineSpacing: Double? = nil,
                marker: Marker = .none, level: Int = 0) {
        self.spans = spans
        self.size = size
        self.bold = bold
        self.colour = colour
        self.spaceBefore = spaceBefore
        self.tracking = tracking
        self.lineSpacing = lineSpacing
        self.marker = marker
        self.level = level
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

    public func boxes(for slide: Slide) -> [Box] {
        /// A gradient ground on ordinary slides as well, when the design asks
        /// for one — a modern deck is rarely flat white.
        let ordinary = ground(feature: false).map { [$0] } ?? []
        switch slide {
        case let .title(text, subtitle):
            return feature(text, size: design.titleSize, secondary: subtitle, isTitleSlide: true)

        case let .section(text, subtitle, _):
            return feature(text, size: design.sectionSize, secondary: subtitle)

        case let .points(heading, items, _):
            let head = ordinary + self.heading(heading)
            let leading = design.bodySize * design.leading
            /// A real bullet, not a character glued to the front of the
            /// string: PowerPoint then indents the wrap, renumbers a list
            /// when a line is inserted, and a reader editing the deck gets a
            /// list rather than a paragraph that looks like one.
            let runs = items.enumerated().map { index, item in
                Run(Inline.spans(item.text), size: design.bodySize, colour: design.body,
                    spaceBefore: index == 0 ? 0 : leading,
                    marker: item.numbered ? .number
                        : (design.bullet.isEmpty ? .none : .character(design.bullet)),
                    level: item.level)
            }
            return head + [body(runs)]

        case let .prose(heading, text, _):
            /// A shorter measure than a list. Prose set across the full slide
            /// is 120 characters a line, which nobody reads from the back of
            /// a room; 60 to 75 is the range that does.
            let top = bodyTop
            return ordinary + self.heading(heading) + [
                Box(x: margin, y: top, width: Int(Double(contentWidth) * 0.72),
                    height: canvas.height - top - canvas.down(0.12),
                    content: .text([Run(text, size: design.bodySize, colour: design.body)],
                                   align: .left, anchor: .middle)),
            ]

        case let .statement(text, attribution):
            /// Optically centred and set large: the slide people remember has
            /// nothing else on it.
            var runs = [Run(text, size: design.statementSize, bold: design.headingBold,
                            colour: design.heading)]
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
                            colour: design.featureHeading)]
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
            var boxes = ordinary + (heading.map(self.heading) ?? [])
            let top = heading == nil ? canvas.down(0.08) : bodyTop
            let bottom = caption == nil ? canvas.down(0.92) : canvas.down(0.84)
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
            let head = ordinary + (heading.map(self.heading) ?? [])
            /// Deep, and centred in what is left. A stat band pinned to the
            /// top of the body area left the bottom third of every slide
            /// empty and the figures looking stranded.
            let bottom = canvas.down(0.86)
            let available = bottom - (heading == nil ? canvas.down(0.2) : bodyTop)
            let depth = min(available, canvas.down(0.40))
            let top = (heading == nil ? canvas.down(0.2) : bodyTop) + (available - depth) / 2
            let count = max(1, figures.count)
            let gutter = canvas.across(0.025)
            let width = (contentWidth - gutter * (count - 1)) / count
            var boxes = head
            for (index, figure) in figures.enumerated() {
                let x = margin + (width + gutter) * index
                if let card = design.card {
                    boxes.append(Box(x: x, y: top, width: width, height: depth,
                                     content: .panel(card)))
                }
                let inset = design.card == nil ? 0 : canvas.across(0.018)
                boxes.append(Box(x: x + inset, y: top, width: width - inset * 2, height: depth,
                                 content: .text([
                                    Run(figure.figure, size: design.size(4), bold: design.headingBold,
                                        colour: design.heading, tracking: design.headingTracking,
                                        lineSpacing: design.lineSpacing),
                                    Run(figure.label, size: design.size(-1) * 1.15, colour: design.body,
                                        spaceBefore: design.bodySize * 0.55,
                                        tracking: design.kickerTracking * 0.5),
                                 ], align: .left, anchor: .middle)))
            }
            return boxes

        case let .cards(heading, panels, _):
            let head = ordinary + (heading.map(self.heading) ?? [])
            let bottom = canvas.down(0.86)
            let available = bottom - (heading == nil ? canvas.down(0.2) : bodyTop)
            let depth = min(available, canvas.down(0.46))
            let top = (heading == nil ? canvas.down(0.2) : bodyTop) + (available - depth) / 2
            let count = max(1, panels.count)
            let gutter = canvas.across(0.025)
            let width = (contentWidth - gutter * (count - 1)) / count
            var boxes = head
            for (index, panel) in panels.enumerated() {
                let x = margin + (width + gutter) * index
                if let card = design.card {
                    boxes.append(Box(x: x, y: top, width: width, height: depth,
                                     content: .panel(card)))
                }
                let inset = design.card == nil ? 0 : canvas.across(0.018)
                boxes.append(Box(x: x + inset, y: top + canvas.down(0.045),
                                 width: width - inset * 2, height: depth - canvas.down(0.09),
                                 content: .text([
                                    Run(panel.title, size: design.size(1), bold: design.headingBold,
                                        colour: design.heading, tracking: design.headingTracking * 0.5),
                                    /// Body size, not caption. A card is not a
                                    /// footnote, and at one step down the text
                                    /// was smaller than the bullets beside it.
                                    Run(panel.body, size: design.bodySize, colour: design.body,
                                        spaceBefore: design.bodySize * 0.7,
                                        lineSpacing: 1.05),
                                 ], align: .left, anchor: .top)))
            }
            return boxes

        case let .table(heading, rows, header):
            let head = ordinary + (heading.map(self.heading) ?? [])
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
            let head = ordinary + self.heading(heading)
            let leading = design.bodySize * design.leading
            let gutter = canvas.across(0.04)
            let column = (contentWidth - gutter) / 2
            let top = bodyTop
            let depth = canvas.height - top - canvas.down(0.12)
            func runs(_ items: [Bullet]) -> [Run] {
                items.enumerated().map { index, item in
                    Run(Inline.spans(item.text), size: design.bodySize, colour: design.body,
                        spaceBefore: index == 0 ? 0 : leading,
                        marker: item.numbered ? .number
                            : (design.bullet.isEmpty ? .none : .character(design.bullet)),
                        level: item.level)
                }
            }
            /// Anchored to the TOP, not centred. Centred, a three-item
            /// column floats halfway down beside a five-item one and the two
            /// lists read as unrelated.
            return head + [
                Box(x: margin, y: top, width: column, height: depth,
                    content: .text(runs(left), align: .left, anchor: .top)),
                Box(x: margin + column + gutter, y: top, width: column, height: depth,
                    content: .text(runs(right), align: .left, anchor: .top)),
            ]
        }
    }

    // MARK: - The bands

    /// Heading, and the short rule under it.
    ///
    /// The heading box runs from the top margin down to the rule and is
    /// anchored to its BOTTOM, so it grows upward into empty space. Anchored
    /// to the top with a fixed rule below, a heading that wraps to two lines
    /// runs straight through the rule — and headings wrap on the slide, not
    /// in this code, because PowerPoint does its own line breaking.
    private func heading(_ text: String) -> [Box] {
        let top = headingBandTop
        var boxes = [Box(x: margin, y: top, width: contentWidth,
                         height: ruleY - top - Canvas.points(design.headingSize * 0.3),
                         content: .text([Run(text, size: design.headingSize,
                                             bold: design.headingBold, colour: design.heading,
                                             tracking: design.headingTracking,
                                             lineSpacing: design.lineSpacing)],
                                        align: .left, anchor: .bottom),
                         placeholder: "title")]
        if design.rule {
            /// Under the heading's band rather than under the text itself:
            /// the rule marks the grid, and a rule that moves with a one-line
            /// or two-line heading reads as a mistake.
            boxes.append(Box(x: margin, y: ruleY, width: canvas.across(0.05),
                             height: Canvas.points(3), content: .fill(design.accent)))
        }
        return boxes
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

    /// Centred in the space under the rule, not pinned to the top of it.
    ///
    /// Top-anchored, a three-line list left half the slide empty below it and
    /// the deck read as top-heavy on every content slide. Centring balances
    /// a short list and a long one alike, and the heading and rule stay put,
    /// so the deck's fixed furniture is still fixed.
    private func body(_ runs: [Run]) -> Box {
        Box(x: margin, y: bodyTop, width: contentWidth,
            height: canvas.height - bodyTop - canvas.down(0.12),
            content: .text(runs, align: .left, anchor: .middle))
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

    /// Title and section slides: full-bleed ground, text on the lower third.
    private func feature(_ text: String, size: Double, secondary: String?,
                         isTitleSlide: Bool = false) -> [Box] {
        var boxes = [ground(feature: true)].compactMap { $0 }
        var runs = [Run(text, size: size, bold: design.headingBold, colour: design.featureHeading,
                        tracking: design.headingTracking, lineSpacing: design.lineSpacing)]
        if let secondary {
            runs.append(Run(secondary, size: design.bodySize, colour: design.featureBody,
                            spaceBefore: design.bodySize * 1.5))
        }
        boxes.append(Box(x: margin, y: canvas.down(0.24), width: contentWidth,
                         height: canvas.down(0.52),
                         content: .text(runs, align: .left, anchor: .middle),
                         placeholder: isTitleSlide ? "ctrTitle" : "title"))
        if design.rule {
            boxes.append(Box(x: margin, y: canvas.down(0.79), width: canvas.across(0.05),
                             height: Canvas.points(3), content: .fill(design.accent)))
        }
        return boxes
    }
}
