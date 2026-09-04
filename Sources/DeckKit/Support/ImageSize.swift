//
//  ImageSize.swift
//  DeckKit
//
//  How big a picture is, and where it goes inside a box that is not its shape.
//

import Foundation
import ImageIO

/// Pixel dimensions, read without decoding the image.
enum ImageSize {

    /// Width and height in pixels, or nil for something ImageIO cannot read.
    static func of(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        /// EXIF orientation 5–8 are the rotated ones: the pixels are stored
        /// on their side and every viewer turns them upright, so the width
        /// a layout should plan for is the stored height.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, orientation >= 5 {
            return (height, width)
        }
        return (width, height)
    }

    /// The largest rectangle of the picture's proportions that fits the box,
    /// centred in it.
    ///
    /// A picture stretched to the box was the alternative, and a 1:3
    /// portrait arrived on the slide as a 3:1 landscape — every diagram
    /// squashed, every photograph made fat, silently.
    static func fit(width: Int, height: Int, in box: Box) -> (x: Int, y: Int, width: Int, height: Int) {
        guard width > 0, height > 0, box.width > 0, box.height > 0 else {
            return (box.x, box.y, box.width, box.height)
        }
        let scale = min(Double(box.width) / Double(width), Double(box.height) / Double(height))
        let fitted = (width: Int(Double(width) * scale), height: Int(Double(height) * scale))
        return (x: box.x + (box.width - fitted.width) / 2,
                y: box.y + (box.height - fitted.height) / 2,
                width: fitted.width, height: fitted.height)
    }
}
