//
//  ChartImage.swift
//  DeckKit
//
//  The charts Quick Look cannot draw, drawn here.
//

import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// A pie or a doughnut as a transparent PNG.
///
/// Quick Look renders a native pie as one undivided circle in one colour,
/// whatever the file says about its slices — measured with per-point
/// colours, theme accents and data labels, none of which it honoured. A
/// picture is the same in every viewer; `[chart pie drawn]` asks for one.
/// The default stays native, because editable is the point of a `.pptx`.
enum ChartImage {

    /// Slices from the first series, at `scale` pixels per point of the
    /// box's size, in the design's palette and faces.
    static func pie(_ data: Charts.Data, doughnut: Bool, design: Design,
                    width: Int, height: Int, scale: CGFloat = 2) -> Data? {
        let w = CGFloat(width) * scale, h = CGFloat(height) * scale
        guard let context = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: w, height: h))
        let values = data.series.first?.values ?? []
        let total = values.reduce(0, +)
        guard total > 0 else { return nil }
        let palette = design.chartPalette

        /// The pie on the left, a legend on the right; percent labels just
        /// outside each slice.
        let radius = min(h * 0.36, w * 0.22)
        let centre = CGPoint(x: w * 0.34, y: h * 0.5)
        var start = CGFloat.pi / 2
        let labelFont = CTFontCreateWithName(design.bodyFont as CFString, h / 16, nil)
        let text = colour(design.body)
        for (index, value) in values.enumerated() {
            let sweep = CGFloat(value / total) * 2 * .pi
            let end = start - sweep
            context.setFillColor(colour(palette[index % palette.count]))
            context.move(to: centre)
            context.addArc(center: centre, radius: radius, startAngle: start, endAngle: end, clockwise: true)
            context.closePath()
            context.fillPath()
            /// A hairline of the ground between slices, so they separate.
            context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
            context.setLineWidth(1.5 * scale)
            context.move(to: centre)
            context.addLine(to: CGPoint(x: centre.x + radius * cos(end), y: centre.y + radius * sin(end)))
            context.strokePath()
            let middle = start - sweep / 2
            let share = Int((value / total * 100).rounded())
            let label = CGPoint(x: centre.x + radius * 1.18 * cos(middle), y: centre.y + radius * 1.18 * sin(middle))
            draw("\(share)%", at: label, font: labelFont, colour: text, in: context,
                 align: cos(middle) < -0.2 ? .right : (cos(middle) > 0.2 ? .left : .centre))
            start = end
        }
        if doughnut {
            context.setBlendMode(.clear)
            context.fillEllipse(in: CGRect(x: centre.x - radius * 0.58, y: centre.y - radius * 0.58,
                                           width: radius * 1.16, height: radius * 1.16))
            context.setBlendMode(.normal)
        }
        /// The legend: a swatch and the category, one row each.
        let legendFont = CTFontCreateWithName(design.bodyFont as CFString, h / 15, nil)
        let row = h / 15 * 1.9
        let x = w * 0.62
        var y = centre.y + row * CGFloat(data.categories.count - 1) / 2
        for (index, category) in data.categories.enumerated() {
            context.setFillColor(colour(palette[index % palette.count]))
            context.fill(CGRect(x: x, y: y - row * 0.22, width: row * 0.44, height: row * 0.44))
            draw(category, at: CGPoint(x: x + row * 0.7, y: y), font: legendFont, colour: text, in: context, align: .left)
            y -= row
        }
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private enum Align { case left, centre, right }

    /// Text vertically centred on `point`.
    private static func draw(_ string: String, at point: CGPoint, font: CTFont, colour: CGColor,
                             in context: CGContext, align: Align) {
        let attributed = CFAttributedStringCreate(nil, string as CFString, [
            kCTFontAttributeName: font, kCTForegroundColorAttributeName: colour,
        ] as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let x: CGFloat
        switch align {
        case .left: x = point.x
        case .centre: x = point.x - width / 2
        case .right: x = point.x - width
        }
        context.textPosition = CGPoint(x: x, y: point.y - (ascent - descent) / 2)
        CTLineDraw(line, context)
    }

    private static func colour(_ hex: String) -> CGColor {
        let c = Colour.rgb(hex) ?? (r: 0, g: 0, b: 0)
        return CGColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }
}
