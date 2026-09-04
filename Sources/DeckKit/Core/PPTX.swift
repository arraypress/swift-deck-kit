//
//  PPTX.swift
//  DeckKit
//
//  The writer. A .pptx is a zip of XML parts that reference each other by
//  relationship id, and every part has to agree with the others or the file
//  does not open at all.
//

import Foundation

/// Writes a deck as a PowerPoint file.
public enum PPTX {

    /// Builds the archive.
    ///
    /// - Parameter images: pictures already read off disk, keyed by the path
    ///   the slide referred to. Passed in rather than read here so a caller
    ///   can report a missing picture before anything is written.
    public static func data(
        deck: Deck,
        design: Design,
        canvas: Canvas = .sixteenByNine,
        images: [String: Data] = [:]
    ) throws -> Data {

        guard !deck.slides.isEmpty else { throw DeckError.empty }
        let layout = Layout(design: design, canvas: canvas)

        var entries: [Zip.Entry] = []
        var media: [String: String] = [:]           // path → media file name
        var mediaEntries: [Zip.Entry] = []
        var index = 0
        for (path, data) in images.sorted(by: { $0.key < $1.key }) {
            index += 1
            let name = "image\(index).\(((path as NSString).pathExtension).lowercased())"
            media[path] = name
            mediaEntries.append(Zip.Entry(name: "ppt/media/\(name)", data: data))
        }

        var slideParts: [(xml: String, rels: String)] = []
        for slide in deck.slides {
            let boxes = layout.boxes(for: slide)
            var pictures: [(rel: String, name: String)] = []
            for box in boxes {
                if case let .picture(path) = box.content, let name = media[path] {
                    pictures.append((rel: "rId\(pictures.count + 2)", name: name))
                }
            }
            slideParts.append((xml: slideXML(boxes, media: media, canvas: canvas),
                               rels: slideRels(pictures)))
        }

        // MARK: Parts

        let count = deck.slides.count
        let overrides = (1...count).map {
            "<Override PartName=\"/ppt/slides/slide\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
        }.joined()
        var defaults = """
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
            <Default Extension="xml" ContentType="application/xml"/>
            """
        for suffix in Set(media.values.map { ($0 as NSString).pathExtension }) {
            let type = suffix == "png" ? "image/png" : (suffix == "gif" ? "image/gif" : "image/jpeg")
            defaults += "<Default Extension=\"\(suffix)\" ContentType=\"\(type)\"/>"
        }

        entries.append(.init(name: "[Content_Types].xml", data: Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
            \(defaults)\
            <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>\
            <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>\
            <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>\
            <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>\
            <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
            \(overrides)</Types>
            """.utf8)))

        entries.append(.init(name: "_rels/.rels", data: Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>\
            <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>\
            </Relationships>
            """.utf8)))

        entries.append(.init(name: "docProps/core.xml", data: Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
            xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
            <dc:title>\(escape(deck.title ?? "Deck"))</dc:title></cp:coreProperties>
            """.utf8)))

        let slideIDs = (0..<count).map { "<p:sldId id=\"\(256 + $0)\" r:id=\"rId\($0 + 2)\"/>" }.joined()
        entries.append(.init(name: "ppt/presentation.xml", data: Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
            xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">\
            <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>\
            <p:sldIdLst>\(slideIDs)</p:sldIdLst>\
            <p:sldSz cx="\(canvas.width)" cy="\(canvas.height)"/>\
            <p:notesSz cx="\(canvas.height)" cy="\(canvas.width)"/></p:presentation>
            """.utf8)))

        var presentationRels = ["<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"]
        for slide in 0..<count {
            presentationRels.append("<Relationship Id=\"rId\(slide + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(slide + 1).xml\"/>")
        }
        presentationRels.append("<Relationship Id=\"rId\(count + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"theme/theme1.xml\"/>")
        entries.append(.init(name: "ppt/_rels/presentation.xml.rels", data: Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            \(presentationRels.joined())</Relationships>
            """.utf8)))

        entries.append(.init(name: "ppt/slideMasters/slideMaster1.xml", data: Data(master(design).utf8)))
        entries.append(.init(name: "ppt/slideMasters/_rels/slideMaster1.xml.rels", data: Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>\
            <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>\
            </Relationships>
            """.utf8)))
        entries.append(.init(name: "ppt/slideLayouts/slideLayout1.xml", data: Data(blankLayout.utf8)))
        entries.append(.init(name: "ppt/slideLayouts/_rels/slideLayout1.xml.rels", data: Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>\
            </Relationships>
            """.utf8)))
        entries.append(.init(name: "ppt/theme/theme1.xml", data: Data(theme(design).utf8)))

        for (offset, part) in slideParts.enumerated() {
            entries.append(.init(name: "ppt/slides/slide\(offset + 1).xml", data: Data(part.xml.utf8)))
            entries.append(.init(name: "ppt/slides/_rels/slide\(offset + 1).xml.rels", data: Data(part.rels.utf8)))
        }
        entries += mediaEntries

        return Zip.archive(entries)
    }

    // MARK: - Slides

    static func slideXML(_ boxes: [Box], media: [String: String], canvas: Canvas) -> String {
        var shapes = ""
        var id = 1
        var pictureRel = 1
        for box in boxes {
            id += 1
            switch box.content {
            case let .fill(colour):
                shapes += shape(id: id, box: box, panel: .flat(colour), canvas: canvas)
            case let .panel(panel):
                shapes += shape(id: id, box: box, panel: panel, canvas: canvas)
            case let .gradient(stops, angle):
                shapes += gradient(id: id, box: box, stops: stops, angle: angle)
            case let .text(runs, align, anchor):
                shapes += textBox(id: id, box: box, runs: runs, align: align, anchor: anchor)
            case let .picture(path):
                guard media[path] != nil else { continue }
                pictureRel += 1
                shapes += picture(id: id, box: box, relationship: "rId\(pictureRel)")
            }
        }
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
            xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree>\
            <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>\
            <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>\
            <a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>\
            \(shapes)</p:spTree></p:cSld>\
            <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>
            """
    }

    static func slideRels(_ pictures: [(rel: String, name: String)]) -> String {
        var rels = ["<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/>"]
        for picture in pictures {
            rels.append("<Relationship Id=\"\(picture.rel)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/\(picture.name)\"/>")
        }
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            \(rels.joined())</Relationships>
            """
    }

    /// A filled shape: flat or rounded, opaque or translucent, with or
    /// without a soft shadow.
    ///
    /// `roundRect`'s adjust is a percentage of **half the shorter side**, so
    /// a radius given as a fraction of the shorter side doubles on the way in.
    private static func shape(id: Int, box: Box, panel: Panel, canvas: Canvas) -> String {
        let rounded = panel.radius > 0
        let adjust = min(50_000, Int(panel.radius * 2 * 100_000))
        let geometry = rounded
            ? "<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val \(adjust)\"/></a:avLst></a:prstGeom>"
            : "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>"
        let fill = "<a:solidFill>\(colour(panel.fill, alpha: panel.fillAlpha))</a:solidFill>"
        let line = panel.border.map {
            "<a:ln w=\(Canvas.points(panel.borderWidth).quoted)><a:solidFill>\(colour($0, alpha: panel.borderAlpha))</a:solidFill></a:ln>"
        } ?? "<a:ln><a:noFill/></a:ln>"
        /// Blur and offset in EMU. Generous blur and a short drop is what
        /// reads as a soft modern shadow rather than a 2007 bevel.
        let effect = panel.shadow
            ? "<a:effectLst><a:outerShdw blurRad=\"400000\" dist=\"140000\" dir=\"5400000\" rotWithShape=\"0\">"
              + "<a:srgbClr val=\"000000\"><a:alpha val=\"32000\"/></a:srgbClr></a:outerShdw></a:effectLst>"
            : ""
        return """
        <p:sp><p:nvSpPr><p:cNvPr id="\(id)" name="fill\(id)"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>\
        <p:spPr><a:xfrm><a:off x="\(box.x)" y="\(box.y)"/><a:ext cx="\(box.width)" cy="\(box.height)"/></a:xfrm>\
        \(geometry)\(fill)\(line)\(effect)</p:spPr>\
        <p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody></p:sp>
        """
    }

    /// A gradient ground.
    ///
    /// OOXML's angle is in sixtieths of a degree and runs clockwise from
    /// "left to right", so 135° here is the top-left to bottom-right sweep a
    /// person means when they say diagonal.
    private static func gradient(id: Int, box: Box, stops: [Stop], angle: Double) -> String {
        let list = stops
            .sorted { $0.position < $1.position }
            .map { "<a:gs pos=\"\(Int(min(max($0.position, 0), 1) * 100_000))\"><a:srgbClr val=\"\($0.colour)\"/></a:gs>" }
            .joined()
        return """
        <p:sp><p:nvSpPr><p:cNvPr id="\(id)" name="ground\(id)"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>\
        <p:spPr><a:xfrm><a:off x="\(box.x)" y="\(box.y)"/><a:ext cx="\(box.width)" cy="\(box.height)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>\
        <a:gradFill rotWithShape="1"><a:gsLst>\(list)</a:gsLst>\
        <a:lin ang="\(Int(angle.truncatingRemainder(dividingBy: 360) * 60_000))" scaled="0"/></a:gradFill>\
        <a:ln><a:noFill/></a:ln></p:spPr>\
        <p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody></p:sp>
        """
    }

    /// A colour, with an alpha child only when it is not opaque.
    private static func colour(_ hex: String, alpha: Double) -> String {
        alpha >= 1
            ? "<a:srgbClr val=\"\(hex)\"/>"
            : "<a:srgbClr val=\"\(hex)\"><a:alpha val=\"\(Int(max(0, alpha) * 100_000))\"/></a:srgbClr>"
    }

    private static func textBox(id: Int, box: Box, runs: [Run], align: Box.Align, anchor: Box.Anchor) -> String {
        let alignment = ["left": "l", "centre": "ctr", "right": "r"][align.rawValue] ?? "l"
        let anchoring = ["top": "t", "middle": "ctr", "bottom": "b"][anchor.rawValue] ?? "t"
        var paragraphs = ""
        for run in runs {
            /// **Order matters**: the schema requires lnSpc before spcBef.
            /// Written the other way round it renders in Quick Look and is
            /// rejected by `xmllint --schema pml.xsd`, which is how it was
            /// caught — a lenient previewer hides it, PowerPoint might not.
            let spacing = run.lineSpacing.map {
                "<a:lnSpc><a:spcPct val=\"\(Int($0 * 100_000))\"/></a:lnSpc>"
            } ?? ""
            let before = run.spaceBefore > 0
                ? "<a:spcBef><a:spcPts val=\"\(Int(run.spaceBefore * 100))\"/></a:spcBef>"
                : ""
            /// Letter-spacing is in hundredths of a point and may be negative.
            let tracking = run.tracking != 0 ? " spc=\"\(Int(run.tracking * 100))\"" : ""
            paragraphs += """
                <a:p><a:pPr algn="\(alignment)">\(spacing)\(before)</a:pPr><a:r>\
                <a:rPr lang="en-GB" sz="\(Int(run.size * 100))" b="\(run.bold ? 1 : 0)"\(tracking) dirty="0">\
                <a:solidFill><a:srgbClr val="\(run.colour)"/></a:solidFill>\
                </a:rPr><a:t>\(escape(run.text))</a:t></a:r></a:p>
                """
        }
        return """
        <p:sp><p:nvSpPr><p:cNvPr id="\(id)" name="text\(id)"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>\
        <p:spPr><a:xfrm><a:off x="\(box.x)" y="\(box.y)"/><a:ext cx="\(box.width)" cy="\(box.height)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>\
        <p:txBody><a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="\(anchoring)">\
        <a:normAutofit/></a:bodyPr><a:lstStyle/>\(paragraphs)</p:txBody></p:sp>
        """
    }

    private static func picture(id: Int, box: Box, relationship: String) -> String {
        """
        <p:pic><p:nvPicPr><p:cNvPr id="\(id)" name="picture\(id)"/>\
        <p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>\
        <p:blipFill><a:blip r:embed="\(relationship)"/>\
        <a:stretch><a:fillRect/></a:stretch></p:blipFill>\
        <p:spPr><a:xfrm><a:off x="\(box.x)" y="\(box.y)"/><a:ext cx="\(box.width)" cy="\(box.height)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>
        """
    }

    /// `&`, `<` and `>` only. A quote inside element text is legal XML, and
    /// escaping it makes typographic quotes show up as `&quot;` in the
    /// editor a person opens this in.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - The fixed parts

    private static let blankLayout = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1">\
        <p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>\
        <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>\
        <a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld>\
        <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>
        """

    private static func master(_ design: Design) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld>\
        <p:bg><p:bgPr><a:solidFill><a:srgbClr val="\(design.background)"/></a:solidFill>\
        <a:effectLst/></p:bgPr></p:bg><p:spTree>\
        <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>\
        <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>\
        <a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld>\
        <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" \
        accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>\
        <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>
        """
    }

    private static func theme(_ design: Design) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="\(escape(design.name))">\
        <a:themeElements><a:clrScheme name="\(escape(design.name))">\
        <a:dk1><a:srgbClr val="\(design.heading)"/></a:dk1><a:lt1><a:srgbClr val="\(design.background)"/></a:lt1>\
        <a:dk2><a:srgbClr val="\(design.body)"/></a:dk2><a:lt2><a:srgbClr val="\(design.featureBody)"/></a:lt2>\
        <a:accent1><a:srgbClr val="\(design.accent)"/></a:accent1><a:accent2><a:srgbClr val="\(design.accent)"/></a:accent2>\
        <a:accent3><a:srgbClr val="\(design.accent)"/></a:accent3><a:accent4><a:srgbClr val="\(design.accent)"/></a:accent4>\
        <a:accent5><a:srgbClr val="\(design.accent)"/></a:accent5><a:accent6><a:srgbClr val="\(design.accent)"/></a:accent6>\
        <a:hlink><a:srgbClr val="\(design.accent)"/></a:hlink><a:folHlink><a:srgbClr val="\(design.accent)"/></a:folHlink>\
        </a:clrScheme><a:fontScheme name="\(escape(design.name))">\
        <a:majorFont><a:latin typeface="\(escape(design.headingFont))"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>\
        <a:minorFont><a:latin typeface="\(escape(design.bodyFont))"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>\
        </a:fontScheme><a:fmtScheme name="\(escape(design.name))">\
        <a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>\
        <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>\
        <a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>\
        <a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>\
        <a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>\
        <a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>\
        <a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle>\
        <a:effectStyle><a:effectLst/></a:effectStyle>\
        <a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>\
        <a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>\
        <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>\
        <a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>\
        </a:fmtScheme></a:themeElements></a:theme>
        """
    }
}
