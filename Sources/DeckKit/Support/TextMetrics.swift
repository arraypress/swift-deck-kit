//
//  TextMetrics.swift
//  DeckKit
//
//  How much room text needs — measured in the face it will be set in.
//

import CoreText
import Foundation

/// Measuring runs with CoreText.
///
/// **An estimate, and says so.** PowerPoint does its own line breaking, so
/// a generator cannot know exactly where a line will end. What it can do is
/// set the string in the same face at the same size, count the lines that
/// takes at the box's width, and add them up. Used by the layout to size a
/// card to what is on it and to place a short list, and by `Check` to catch
/// text that will not fit.
enum TextMetrics {

    /// The height a set of runs needs, in EMU.
    static func height(of runs: [Run], inWidth width: Int, design: Design) -> Double {
        var total = 0.0
        for run in runs {
            let lines = lineCount(run, inWidth: width, design: design)
            total += Double(lines) * Double(Canvas.points(design.lineHeight(run.size)))
            total += Double(Canvas.points(run.spaceBefore))
        }
        return total
    }

    /// How many lines a run wraps to at a width.
    static func lineCount(_ run: Run, inWidth width: Int, design: Design) -> Int {
        let available = Double(width) / Canvas.perInch * 72
        guard available > 0 else { return 1 }
        /// A hanging indent narrows every line of a list item.
        let indented = available - (run.marker == .none && run.level == 0
                                    ? 0 : indent(for: run.marker, design: design) * Double(run.level + 1))
        return max(1, Int((self.width(of: run, design: design) / max(1, indented)).rounded(.up)))
    }

    /// The hanging indent for a list marker, in points: the marker's own
    /// width plus a gap of half the body size, and never less than the
    /// floor.
    ///
    /// Measured, because it was guessed twice. At 26pt the dash "sat a
    /// thumb's width from its sentence" — in Quick Look, which pads a
    /// bullet by itself. Cut to 17pt, it fitted Quick Look and touched the
    /// text in LibreOffice and PowerPoint, where the text starts exactly
    /// at the indent and an em dash at 85% of 18pt is 15pt wide.
    static func indent(for marker: Run.Marker, design: Design) -> Double {
        let mark: String
        switch marker {
        case .none: return Layout.minimumIndent
        case let .character(character): mark = character
        case .number: mark = "9."
        }
        let font = CTFontCreateWithName(PPTX.bulletFace as CFString, design.bodySize * 0.85, nil)
        let line = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, mark as CFString, [kCTFontAttributeName: font] as CFDictionary)!)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        return max(Layout.minimumIndent, (width + design.bodySize * 0.5).rounded())
    }

    /// The run set on one line, in points.
    static func width(of run: Run, design: Design) -> Double {
        CTLineGetTypographicBounds(line(for: run, design: design), nil, nil, nil)
    }

    /// Measured in the run's own face — a heading in Avenir Next Bold is a
    /// fifth wider than the same words in Helvetica Neue, and a measurement
    /// in the wrong face is a guess with a decimal point.
    private static func line(for run: Run, design: Design) -> CTLine {
        let name = run.face == .heading ? design.headingFont : design.bodyFont
        let base = CTFontCreateWithName(name as CFString, run.size, nil)
        let font = run.bold
            ? (CTFontCreateCopyWithSymbolicTraits(base, run.size, nil, .boldTrait, .boldTrait) ?? base)
            : base
        var attributes: [CFString: Any] = [kCTFontAttributeName: font]
        if run.tracking != 0 { attributes[kCTKernAttributeName] = run.tracking }
        return CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, run.text as CFString, attributes as CFDictionary)!)
    }
}
