//
//  Check.swift
//  DeckKit
//
//  Will it fit? — asked before someone opens the deck in front of a room.
//

import Foundation

/// Finding text that will not fit its box.
///
/// **This is an estimate, and says so.** PowerPoint does its own line
/// breaking, so a generator cannot know exactly where a line will end. What
/// it can do is measure the string in the same font at the same size with
/// CoreText, work out how many lines that needs at the box's width, and
/// compare the block against the box's height. That catches the case that
/// actually happens — a heading or a list far too long for the slide — well
/// before it becomes a broken slide in front of an audience.
public enum Check {

    /// One piece of text that is too long.
    public struct Problem: Sendable, Equatable {
        /// 1-based, as a person counts slides.
        public let slide: Int
        public let kind: String
        /// What is wrong, in a sentence.
        public let message: String
        /// The text at fault, shortened.
        public let text: String
        /// How much over: 1.2 means a fifth taller than its box.
        public let overflow: Double

        /// Public so a caller can build one for a test of its own rendering,
        /// without generating a deck that overflows to get hold of it.
        public init(slide: Int, kind: String, message: String, text: String, overflow: Double) {
            self.slide = slide
            self.kind = kind
            self.message = message
            self.text = text
            self.overflow = overflow
        }
    }

    /// Every problem in a deck.
    ///
    /// - Parameter tolerance: how much overflow to allow before reporting.
    ///   A little slack on purpose — the measurement is an estimate, and a
    ///   checker that cries wolf at 2% gets turned off.
    public static func problems(
        in deck: Deck,
        design: Design,
        canvas: Canvas = .sixteenByNine,
        tolerance: Double = 1.08
    ) -> [Problem] {

        let layout = Layout(design: design, canvas: canvas)
        var found: [Problem] = []

        for (index, slide) in deck.slides.enumerated() {
            for box in layout.boxes(for: slide, kicker: deck.kickers[index]) {
                guard case let .text(runs, _, _) = box.content, !runs.isEmpty else { continue }
                let needed = height(of: runs, inWidth: box.width, design: design)
                let available = Double(box.height)
                guard available > 0 else { continue }
                let ratio = needed / available
                guard ratio > tolerance else { continue }

                let longest = runs.max(by: { $0.text.count < $1.text.count })?.text ?? ""
                found.append(Problem(
                    slide: index + 1,
                    kind: slide.kind,
                    message: "the text needs about \(Int((ratio - 1) * 100))% more room than the slide gives it",
                    text: longest.count > 60 ? String(longest.prefix(57)) + "…" : longest,
                    overflow: (ratio * 100).rounded() / 100))
            }
        }
        return found
    }

    /// The height a set of runs needs, in EMU.
    static func height(of runs: [Run], inWidth width: Int, design: Design) -> Double {
        TextMetrics.height(of: runs, inWidth: width, design: design)
    }

    static func lineCount(_ run: Run, inWidth width: Int, design: Design) -> Int {
        TextMetrics.lineCount(run, inWidth: width, design: design)
    }
}
