//
//  Colour.swift
//  DeckKit
//
//  Compositing done here, so the file carries opaque colour.
//

import Foundation

/// Hex colour arithmetic.
///
/// A translucent fill reaches the file as the OPAQUE colour it would have
/// composited to. Quick Look renders any shape with an alpha channel — or
/// rounded corners — to a separate attachment, and on a deck longer than a
/// few slides places those attachments on the wrong slides: a ten-slide
/// deck's 9 cards were drawn 17 times. Square and opaque, the same card is
/// a plain `div` and stays where it was put. On a flat or gently graded
/// ground the composited colour is what the translucent one looked like.
enum Colour {

    /// `fill` at `alpha`, composited over `ground`. Opaque input comes back
    /// unchanged; an unparseable colour comes back as it was.
    static func blend(_ fill: String, alpha: Double, over ground: String) -> String {
        guard alpha < 1, let top = rgb(fill), let under = rgb(ground) else { return fill }
        let a = max(0, alpha)
        func mix(_ x: Int, _ y: Int) -> Int { Int((Double(x) * a + Double(y) * (1 - a)).rounded()) }
        return hex(mix(top.r, under.r), mix(top.g, under.g), mix(top.b, under.b))
    }

    /// The mean of several colours — a gradient's middle, to blend against.
    static func average(_ colours: [String]) -> String? {
        let parsed = colours.compactMap(rgb)
        guard !parsed.isEmpty else { return nil }
        let n = parsed.count
        return hex(parsed.map(\.r).reduce(0, +) / n,
                   parsed.map(\.g).reduce(0, +) / n,
                   parsed.map(\.b).reduce(0, +) / n)
    }

    static func rgb(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        return (value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
    }

    static func hex(_ r: Int, _ g: Int, _ b: Int) -> String {
        String(format: "%02X%02X%02X", min(255, max(0, r)), min(255, max(0, g)), min(255, max(0, b)))
    }
}
