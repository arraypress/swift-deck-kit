//
//  Layouts.swift
//  DeckKit
//
//  The layouts a reader sees in "New Slide", and the placeholders that make
//  the outline pane work.
//

import Foundation

/// The slide layouts a deck ships with.
///
/// Without these a deck has one blank layout: the recipient's **New Slide**
/// menu is empty, the **outline pane shows nothing** because no text sits in
/// a title placeholder, and PowerPoint's own "Reset" does nothing. The file
/// opened and looked right, and behaved like a folder of pictures.
enum Layouts {

    /// Which layout a slide shape belongs to, 1-based to match the parts.
    static func number(for slide: Slide) -> Int {
        switch slide {
        case .title: return 1
        case .section: return 2
        case .points, .prose, .columns: return 3
        default: return 4
        }
    }

    static let all: [(name: String, type: String, placeholders: [Placeholder])] = [
        ("Title Slide", "title", [.init(type: "ctrTitle", index: nil), .init(type: "subTitle", index: 1)]),
        ("Section Header", "secHead", [.init(type: "title", index: nil), .init(type: "body", index: 1)]),
        ("Title and Content", "obj", [.init(type: "title", index: nil), .init(type: "body", index: 1)]),
        ("Blank", "blank", []),
    ]

    struct Placeholder {
        let type: String
        let index: Int?

        var attributes: String {
            "type=\"\(type)\"" + (index.map { " idx=\"\($0)\"" } ?? "")
        }
    }

    /// One layout part.
    ///
    /// The placeholders are given real geometry rather than left to the
    /// master: a reader who picks "Title and Content" from the menu should
    /// get boxes where this design puts them, not where PowerPoint's default
    /// master does.
    static func xml(_ layout: (name: String, type: String, placeholders: [Placeholder]),
                    design: Design, canvas: Canvas) -> String {
        let margin = canvas.across(design.margin)
        let width = canvas.width - margin * 2
        var shapes = ""
        for (offset, placeholder) in layout.placeholders.enumerated() {
            let isTitle = placeholder.type.hasSuffix("itle")
            let y = isTitle ? canvas.down(design.headingTop) : canvas.down(0.42)
            let height = isTitle ? canvas.down(0.2) : canvas.down(0.42)
            shapes += """
                <p:sp><p:nvSpPr><p:cNvPr id="\(offset + 2)" name="\(placeholder.type)"/>\
                <p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>\
                <p:nvPr><p:ph \(placeholder.attributes)/></p:nvPr></p:nvSpPr>\
                <p:spPr><a:xfrm><a:off x="\(margin)" y="\(y)"/><a:ext cx="\(width)" cy="\(height)"/></a:xfrm>\
                <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>\
                <p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody></p:sp>
                """
        }
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
            xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" \
            type="\(layout.type)" preserve="1">\
            <p:cSld name="\(PPTX.escape(layout.name))"><p:spTree>\
            <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>\
            <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>\
            <a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>\
            \(shapes)</p:spTree></p:cSld>\
            <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>
            """
    }
}
