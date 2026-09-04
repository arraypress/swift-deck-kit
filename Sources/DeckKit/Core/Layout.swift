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
        case picture(String)
    }
    public enum Align: String, Sendable { case left, centre, right }
    public enum Anchor: String, Sendable { case top, middle, bottom }

    public let x: Int, y: Int, width: Int, height: Int
    public let content: Content
}

/// One styled line.
public struct Run: Sendable, Equatable {
    public let text: String
    public let size: Double
    public let bold: Bool
    public let colour: String
    /// Space before this line, in points.
    public let spaceBefore: Double

    public init(_ text: String, size: Double, bold: Bool = false,
                colour: String, spaceBefore: Double = 0) {
        self.text = text
        self.size = size
        self.bold = bold
        self.colour = colour
        self.spaceBefore = spaceBefore
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
    private var headingY: Int { canvas.down(design.headingTop) }
    private var gap: Int { Canvas.points(design.bodySize * design.gap) }

    public func boxes(for slide: Slide) -> [Box] {
        switch slide {
        case let .title(text, subtitle):
            return feature(text, size: design.titleSize, secondary: subtitle)

        case let .section(text, note):
            return feature(text, size: design.sectionSize, secondary: note)

        case let .points(heading, items, _):
            let head = self.heading(heading)
            let leading = design.bodySize * design.leading
            let runs = items.enumerated().map { index, item in
                Run(design.bullet.isEmpty ? item : "\(design.bullet)  \(item)",
                    size: design.bodySize, colour: design.body,
                    spaceBefore: index == 0 ? 0 : leading)
            }
            return head + [body(runs)]

        case let .prose(heading, text, _):
            /// A shorter measure than a list. Prose set across the full slide
            /// is 120 characters a line, which nobody reads from the back of
            /// a room; 60 to 75 is the range that does.
            let top = bodyTop
            return self.heading(heading) + [
                Box(x: margin, y: top, width: Int(Double(contentWidth) * 0.72),
                    height: canvas.height - top - canvas.down(0.12),
                    content: .text([Run(text, size: design.bodySize, colour: design.body)],
                                   align: .left, anchor: .top)),
            ]

        case let .statement(text, attribution):
            /// Optically centred and set large: the slide people remember has
            /// nothing else on it.
            var runs = [Run(text, size: design.statementSize, bold: design.headingBold,
                            colour: design.heading)]
            if let attribution {
                runs.append(Run(attribution, size: design.captionSize, colour: design.body,
                                spaceBefore: design.bodySize * 1.6))
            }
            return [Box(x: margin, y: canvas.down(0.2), width: contentWidth,
                        height: canvas.down(0.6),
                        content: .text(runs, align: .left, anchor: .middle))]

        case let .quote(text, attribution):
            var runs = [Run("\u{201C}\(text)\u{201D}", size: design.size(2),
                            colour: design.featureHeading)]
            if let attribution {
                runs.append(Run("\u{2014} \(attribution)", size: design.captionSize,
                                colour: design.featureBody,
                                spaceBefore: design.bodySize * 1.4))
            }
            return [Box(x: 0, y: 0, width: canvas.width, height: canvas.height,
                        content: .fill(design.featureBackground)),
                    Box(x: margin, y: canvas.down(0.2), width: contentWidth,
                        height: canvas.down(0.6),
                        content: .text(runs, align: .left, anchor: .middle))]

        case let .image(path, caption, heading):
            var boxes = heading.map(self.heading) ?? []
            let top = heading == nil ? canvas.down(0.08) : headingY + gap + Canvas.points(design.headingSize)
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

        case let .columns(heading, left, right, _):
            let head = self.heading(heading)
            let leading = design.bodySize * design.leading
            let gutter = canvas.across(0.04)
            let column = (contentWidth - gutter) / 2
            let top = bodyTop
            func runs(_ items: [String]) -> [Run] {
                items.enumerated().map { index, item in
                    Run(design.bullet.isEmpty ? item : "\(design.bullet)  \(item)",
                        size: design.bodySize, colour: design.body,
                        spaceBefore: index == 0 ? 0 : leading)
                }
            }
            return head + [
                Box(x: margin, y: top, width: column, height: canvas.height - top - canvas.down(0.1),
                    content: .text(runs(left), align: .left, anchor: .top)),
                Box(x: margin + column + gutter, y: top, width: column,
                    height: canvas.height - top - canvas.down(0.1),
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
        let top = canvas.down(0.06)
        var boxes = [Box(x: margin, y: top, width: contentWidth,
                         height: ruleY - top - Canvas.points(design.headingSize * 0.35),
                         content: .text([Run(text, size: design.headingSize,
                                             bold: design.headingBold, colour: design.heading)],
                                        align: .left, anchor: .bottom))]
        if design.rule {
            /// Under the heading's band rather than under the text itself:
            /// the rule marks the grid, and a rule that moves with a one-line
            /// or two-line heading reads as a mistake.
            boxes.append(Box(x: margin, y: ruleY, width: canvas.across(0.05),
                             height: Canvas.points(3), content: .fill(design.accent)))
        }
        return boxes
    }

    private var ruleY: Int { headingY + Canvas.points(design.headingSize * 1.75) }
    private var bodyTop: Int { ruleY + gap }

    private func body(_ runs: [Run]) -> Box {
        Box(x: margin, y: bodyTop, width: contentWidth,
            height: canvas.height - bodyTop - canvas.down(0.12),
            content: .text(runs, align: .left, anchor: .top))
    }

    /// Title and section slides: full-bleed colour, text on the lower third.
    private func feature(_ text: String, size: Double, secondary: String?) -> [Box] {
        var boxes = [Box(x: 0, y: 0, width: canvas.width, height: canvas.height,
                         content: .fill(design.featureBackground))]
        var runs = [Run(text, size: size, bold: design.headingBold, colour: design.featureHeading)]
        if let secondary {
            runs.append(Run(secondary, size: design.bodySize, colour: design.featureBody,
                            spaceBefore: design.bodySize * 1.5))
        }
        boxes.append(Box(x: margin, y: canvas.down(0.24), width: contentWidth,
                         height: canvas.down(0.52),
                         content: .text(runs, align: .left, anchor: .middle)))
        if design.rule {
            boxes.append(Box(x: margin, y: canvas.down(0.79), width: canvas.across(0.05),
                             height: Canvas.points(3), content: .fill(design.accent)))
        }
        return boxes
    }
}
