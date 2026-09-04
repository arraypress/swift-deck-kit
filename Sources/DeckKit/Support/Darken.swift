//
//  Darken.swift
//  DeckKit
//
//  A photograph made quiet enough to read over.
//

import CoreGraphics
import Foundation
import ImageIO

/// Dims a picture by compositing black over it, and returns it as JPEG.
///
/// Done to the pixels rather than with a translucent shape on top, because
/// Quick Look renders a translucent shape to an attachment and places
/// attachments on the wrong slides of a longer deck. A darkened picture is
/// just a picture.
enum Darken {

    /// `data` with black at `amount` (0–1) over it. Orientation is applied
    /// and the longer side capped at `maximum` pixels, which is more than a
    /// slide can show.
    static func apply(_ data: Data, amount: Double, maximum: Int = 2400) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximum,
              ] as CFDictionary) else { return nil }
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: frame)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: min(1, max(0, amount))))
        context.fill(frame)
        guard let dimmed = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, dimmed, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
