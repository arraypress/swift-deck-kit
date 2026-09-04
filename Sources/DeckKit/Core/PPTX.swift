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
        images: [String: Data] = [:],
        embed: [(face: Embedding.Face, data: Data)] = [],
        embedTypeface: String = Embedding.bundledTypeface
    ) throws -> Data {

        guard !deck.slides.isEmpty else { throw DeckError.empty }
        let layout = Layout(design: design, canvas: canvas)

        /// Which slides carry a note, 1-based. Only those get a notes part;
        /// a deck with none stays as small as it was.
        let noted = deck.slides.enumerated().compactMap { index, slide -> (Int, String)? in
            guard let note = slide.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !note.isEmpty else { return nil }
            return (index + 1, note)
        }


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
        let notedSlides = Set(noted.map(\.0))
        for (offset, slide) in deck.slides.enumerated() {
            let boxes = layout.boxes(for: slide)
                + [layout.slideNumber(for: slide, number: offset + 1)].compactMap { $0 }
            var pictures: [(rel: String, name: String)] = []
            for box in boxes {
                if case let .picture(path) = box.content, let name = media[path] {
                    pictures.append((rel: "rId\(pictures.count + 2)", name: name))
                }
            }
            /// Links number on after the pictures, since both live in the
            /// same relationship file.
            var linkRels: [(rel: String, target: String)] = []
            var linkIDs: [String: String] = [:]
            for (offset, target) in linkTargets(boxes).enumerated() {
                let rel = "rId\(pictures.count + 2 + offset)"
                linkRels.append((rel: rel, target: target))
                linkIDs[target] = rel
            }
            let number = offset + 1
            slideParts.append((xml: slideXML(boxes, media: media, canvas: canvas,
                                             design: design, links: linkIDs),
                               rels: slideRels(pictures, links: linkRels,
                                               notesSlide: notedSlides.contains(number) ? number : nil,
                                               layout: Layouts.number(for: slide))))
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
        if !embed.isEmpty {
            defaults += "<Default Extension=\"fntdata\" ContentType=\"application/x-fontdata\"/>"
        }
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
            \((1...Layouts.all.count).map { "<Override PartName=\"/ppt/slideLayouts/slideLayout\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml\"/>" }.joined())\
            <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>\
            <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
            \(noted.isEmpty ? "" : "<Override PartName=\"/ppt/notesMasters/notesMaster1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml\"/>")\
            \(noted.map { "<Override PartName=\"/ppt/notesSlides/notesSlide\($0.0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml\"/>" }.joined())\
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
        /// Fonts number after the slides, the theme and the notes master, so
        /// their ids stay stable whether or not there are notes.
        let fontRelationBase = count + (noted.isEmpty ? 3 : 4)
        entries.append(.init(name: "ppt/presentation.xml", data: Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
            xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">\
            <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>\
            \(noted.isEmpty ? "" : "<p:notesMasterIdLst><p:notesMasterId r:id=\"rId\(count + 3)\"/></p:notesMasterIdLst>")\
            <p:sldIdLst>\(slideIDs)</p:sldIdLst>\
            <p:sldSz cx="\(canvas.width)" cy="\(canvas.height)"/>\
            <p:notesSz cx="\(canvas.height)" cy="\(canvas.width)"/>\
            \(embeddedFontList(embed, typeface: embedTypeface, firstRelation: fontRelationBase))\
            </p:presentation>
            """.utf8)))

        var presentationRels = ["<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"]
        for slide in 0..<count {
            presentationRels.append("<Relationship Id=\"rId\(slide + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(slide + 1).xml\"/>")
        }
        presentationRels.append("<Relationship Id=\"rId\(count + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"theme/theme1.xml\"/>")
        if !noted.isEmpty {
            presentationRels.append("<Relationship Id=\"rId\(count + 3)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster\" Target=\"notesMasters/notesMaster1.xml\"/>")
        }

        entries.append(.init(name: "ppt/slideMasters/slideMaster1.xml", data: Data(master(design).utf8)))
        entries.append(.init(name: "ppt/slideMasters/_rels/slideMaster1.xml.rels", data: Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            \((1...Layouts.all.count).map { "<Relationship Id=\"rId\($0)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout\($0).xml\"/>" }.joined())\
            <Relationship Id="rId\(Layouts.all.count + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>\
            </Relationships>
            """.utf8)))
        for (offset, layout) in Layouts.all.enumerated() {
            entries.append(.init(name: "ppt/slideLayouts/slideLayout\(offset + 1).xml",
                                 data: Data(Layouts.xml(layout).utf8)))
            entries.append(.init(name: "ppt/slideLayouts/_rels/slideLayout\(offset + 1).xml.rels", data: Data("""
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
                <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>\
                </Relationships>
                """.utf8)))
        }
        entries.append(.init(name: "ppt/theme/theme1.xml", data: Data(theme(design).utf8)))

        for (offset, font) in embed.enumerated() {
            let name = "font\(offset + 1).fntdata"
            entries.append(.init(name: "ppt/fonts/\(name)", data: font.data))
            presentationRels.append("<Relationship Id=\"rId\(fontRelationBase + offset)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/font\" Target=\"fonts/\(name)\"/>")
        }

        /// Written last, because the font relationships are appended to it
        /// after the theme — a rels file emitted early would name every part
        /// except the fonts, and PowerPoint would drop them silently.
        entries.append(.init(name: "ppt/_rels/presentation.xml.rels", data: Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            \(presentationRels.joined())</Relationships>
            """.utf8)))

        for (offset, part) in slideParts.enumerated() {
            entries.append(.init(name: "ppt/slides/slide\(offset + 1).xml", data: Data(part.xml.utf8)))
            entries.append(.init(name: "ppt/slides/_rels/slide\(offset + 1).xml.rels", data: Data(part.rels.utf8)))
        }
        if !noted.isEmpty {
            entries.append(.init(name: "ppt/notesMasters/notesMaster1.xml", data: Data(Notes.master.utf8)))
            entries.append(.init(name: "ppt/notesMasters/_rels/notesMaster1.xml.rels", data: Data("""
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
                <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>\
                </Relationships>
                """.utf8)))
            for (index, note) in noted {
                entries.append(.init(name: "ppt/notesSlides/notesSlide\(index).xml",
                                     data: Data(Notes.slide(note).utf8)))
                entries.append(.init(name: "ppt/notesSlides/_rels/notesSlide\(index).xml.rels",
                                     data: Data(Notes.rels(slide: index).utf8)))
            }
        }

        entries += mediaEntries

        return Zip.archive(entries)
    }

    // MARK: - Slides

    /// Every distinct link target on a slide, in the order it appears.
    static func linkTargets(_ boxes: [Box]) -> [String] {
        var seen: [String] = []
        for box in boxes {
            guard case let .text(runs, _, _) = box.content else { continue }
            for run in runs {
                for span in run.spans {
                    guard let link = span.link, !seen.contains(link) else { continue }
                    seen.append(link)
                }
            }
        }
        return seen
    }

    static func slideXML(_ boxes: [Box], media: [String: String], canvas: Canvas,
                         design: Design, links: [String: String] = [:]) -> String {
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
                shapes += textBox(id: id, box: box, runs: runs, align: align,
                                  anchor: anchor, links: links)
            case let .slideNumber(number, size, colour):
                shapes += slideNumberField(id: id, box: box, number: number,
                                           size: size, colour: colour)
            case let .table(rows, header):
                shapes += table(id: id, box: box, rows: rows, header: header, design: design)
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

    static func slideRels(_ pictures: [(rel: String, name: String)],
                          links: [(rel: String, target: String)] = [],
                          notesSlide: Int? = nil,
                          layout: Int = 4) -> String {
        var rels = ["<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout\(layout).xml\"/>"]
        for picture in pictures {
            rels.append("<Relationship Id=\"\(picture.rel)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/\(picture.name)\"/>")
        }
        for link in links {
            /// External, so PowerPoint opens it rather than looking for a
            /// part inside the file.
            rels.append("<Relationship Id=\"\(link.rel)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(escape(link.target))\" TargetMode=\"External\"/>")
        }
        if let notesSlide {
            /// The slide points at its notes as well as the other way round.
            /// Without this rel a reader finds no notes at all — which is how
            /// `has_notes_slide` stayed false while the part existed.
            rels.append("<Relationship Id=\"rId\(rels.count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide\" Target=\"../notesSlides/notesSlide\(notesSlide).xml\"/>")
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

    private static func textBox(id: Int, box: Box, runs: [Run],
                                align: Box.Align, anchor: Box.Anchor,
                                links: [String: String] = [:]) -> String {
        /// A placeholder shape is not a text box, and saying it is stops
        /// PowerPoint treating it as the slide's title.
        let placeholder = box.placeholder.map {
            "<p:nvPr><p:ph type=\"\($0)\"/></p:nvPr>"
        } ?? "<p:nvPr/>"
        let shapeProperties = box.placeholder == nil
            ? "<p:cNvSpPr txBox=\"1\"/>"
            : "<p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr>"
        let alignment = ["left": "l", "centre": "ctr", "right": "r"][align.rawValue] ?? "l"
        let anchoring = ["top": "t", "middle": "ctr", "bottom": "b"][anchor.rawValue] ?? "t"
        var paragraphs = ""
        for run in runs {
            /// **Order matters**: the schema requires lnSpc, then spcBef,
            /// then the bullet elements. Written any other way it renders in
            /// Quick Look and `xmllint --schema pml.xsd` rejects it — a
            /// lenient previewer hides what PowerPoint might not forgive.
            let spacing = run.lineSpacing.map {
                "<a:lnSpc><a:spcPct val=\"\(Int($0 * 100_000))\"/></a:lnSpc>"
            } ?? ""
            let before = run.spaceBefore > 0
                ? "<a:spcBef><a:spcPts val=\"\(Int(run.spaceBefore * 100))\"/></a:spcBef>"
                : ""
            /// **The bullet needs its own colour.** A `buChar` inherits
            /// nothing from the run beside it and falls back to BLACK, so
            /// every dash on a dark slide was invisible-but-there — a row of
            /// black marks down the left of a navy deck.
            ///
            /// And its own size: at full body size a dash is heavier than
            /// the sentence it introduces.
            let colour = "<a:buClr><a:srgbClr val=\"\(run.colour)\"/></a:buClr>"
                + "<a:buSzPct val=\"85000\"/>"
            let bullet: String
            switch run.marker {
            case .none:
                bullet = "<a:buNone/>"
            case let .character(mark):
                bullet = colour + "<a:buFont typeface=\"Arial\"/><a:buChar char=\"\(escape(mark))\"/>"
            case .number:
                /// Counted by PowerPoint, so inserting a line renumbers the
                /// rest instead of leaving the author to fix it by hand.
                bullet = colour + "<a:buFont typeface=\"Arial\"/><a:buAutoNum type=\"arabicPeriod\"/>"
            }
            /// A hanging indent, so a wrapped line lines up with the text
            /// above it rather than with the bullet.
            ///
            /// `marL` and `indent` only, **no `lvl`**: `lvl` selects a list
            /// style from the master, and with none defined it overrode these
            /// and left every sub-bullet's marker at the same x while only
            /// its text moved.
            /// Closer than it was. At 26pt the dash sat a thumb's width from
            /// its sentence and read as a separate column of marks.
            let step = 17.0
            let indent = run.marker == .none && run.level == 0
                ? ""
                : " marL=\"\(Canvas.points(step + Double(run.level) * step))\" indent=\"-\(Canvas.points(step))\""

            paragraphs += "<a:p><a:pPr algn=\"\(alignment)\"\(indent)>"
                + spacing + before + bullet + "</a:pPr>"
            for span in run.spans where !span.text.isEmpty {
                paragraphs += self.span(span, run: run, links: links)
            }
            paragraphs += "</a:p>"
        }
        return """
        <p:sp><p:nvSpPr><p:cNvPr id="\(id)" name="text\(id)"/>\(shapeProperties)\(placeholder)</p:nvSpPr>\
        <p:spPr><a:xfrm><a:off x="\(box.x)" y="\(box.y)"/><a:ext cx="\(box.width)" cy="\(box.height)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>\
        <p:txBody><a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="\(anchoring)">\
        <a:normAutofit/></a:bodyPr><a:lstStyle/>\(paragraphs)</p:txBody></p:sp>
        """
    }

    /// One run of text, with whatever marks it carries.
    private static func span(_ span: Span, run: Run, links: [String: String]) -> String {
        let tracking = run.tracking != 0 ? " spc=\"\(Int(run.tracking * 100))\"" : ""
        let bold = (run.bold || span.bold) ? 1 : 0
        let italic = span.italic ? " i=\"1\"" : ""
        /// A monospaced face for `code`, because a file name set in the body
        /// face is indistinguishable from prose — which is the whole reason
        /// somebody wrote backticks round it.
        let face = span.code ? "<a:latin typeface=\"Menlo\"/>" : ""
        let link = span.link.flatMap { links[$0] }.map {
            "<a:hlinkClick xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:id=\"\($0)\"/>"
        } ?? ""
        return "<a:r><a:rPr lang=\"en-GB\" sz=\"\(Int(run.size * 100))\" b=\"\(bold)\"\(italic)\(tracking) dirty=\"0\">"
            + "<a:solidFill><a:srgbClr val=\"\(run.colour)\"/></a:solidFill>"
            + face + link + "</a:rPr><a:t>\(escape(span.text))</a:t></a:r>"
    }

    /// A slide-number field.
    ///
    /// `<a:fld type="slidenum">` rather than a typed digit, so moving a slide
    /// renumbers it. The literal inside is only what a reader that cannot
    /// evaluate the field falls back to.
    private static func slideNumberField(id: Int, box: Box, number: Int,
                                         size: Double, colour: String) -> String {
        """
        <p:sp><p:nvSpPr><p:cNvPr id="\(id)" name="number\(id)"/><p:cNvSpPr txBox="1"/>\
        <p:nvPr/></p:nvSpPr>\
        <p:spPr><a:xfrm><a:off x="\(box.x)" y="\(box.y)"/><a:ext cx="\(box.width)" cy="\(box.height)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>\
        <p:txBody><a:bodyPr wrap="none" lIns="0" tIns="0" rIns="0" bIns="0" anchor="ctr"/><a:lstStyle/>\
        <a:p><a:pPr algn="r"><a:buNone/></a:pPr>\
        <a:fld id="{B4B7A2E9-0F1C-4A64-9E19-1F1E8E1C4E01}" type="slidenum">\
        <a:rPr lang="en-GB" sz="\(Int(size * 100))" dirty="0">\
        <a:solidFill><a:srgbClr val="\(colour)"/></a:solidFill></a:rPr>\
        <a:t>\(number)</a:t></a:fld></a:p></p:txBody></p:sp>
        """
    }

    /// A table, as a graphic frame.
    ///
    /// A real `<a:tbl>` rather than a picture of one, so the person you hand
    /// the deck to can edit a cell — which is the entire reason this writes
    /// PowerPoint instead of a PDF.
    private static func table(id: Int, box: Box, rows: [[String]],
                              header: Bool, design: Design) -> String {
        let columns = rows.map(\.count).max() ?? 1
        let width = box.width / max(1, columns)
        let height = box.height / max(1, rows.count)
        let grid = (0..<columns).map { _ in "<a:gridCol w=\"\(width)\"/>" }.joined()

        var body = ""
        for (index, row) in rows.enumerated() {
            let isHeader = header && index == 0
            var cells = ""
            for column in 0..<columns {
                let text = column < row.count ? row[column] : ""
                let spans = Inline.spans(text)
                var paragraph = "<a:p><a:pPr algn=\"l\"/>"
                for span in spans where !span.text.isEmpty {
                    paragraph += "<a:r><a:rPr lang=\"en-GB\" sz=\"\(Int(design.captionSize * 100))\" "
                        + "b=\"\(isHeader || span.bold ? 1 : 0)\"\(span.italic ? " i=\"1\"" : "") dirty=\"0\">"
                        + "<a:solidFill><a:srgbClr val=\"\(isHeader ? design.heading : design.body)\"/></a:solidFill>"
                        + (span.code ? "<a:latin typeface=\"Menlo\"/>" : "")
                        + "</a:rPr><a:t>\(escape(span.text))</a:t></a:r>"
                }
                if spans.allSatisfy({ $0.text.isEmpty }) { paragraph += "" }
                paragraph += "</a:p>"
                /// No fill and a single hairline under each row: a table with
                /// banded colour fights every design in here, and a rule is
                /// what a designed table actually uses.
                cells += "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/>\(paragraph)</a:txBody>"
                    + "<a:tcPr marL=\"91440\" marR=\"91440\" marT=\"45720\" marB=\"45720\" anchor=\"ctr\">"
                    + "<a:lnB w=\"12700\" cap=\"flat\"><a:solidFill><a:srgbClr val=\"\(design.body)\">"
                    + "<a:alpha val=\"\(isHeader ? 45000 : 18000)\"/></a:srgbClr></a:solidFill></a:lnB>"
                    + "<a:noFill/></a:tcPr></a:tc>"
            }
            body += "<a:tr h=\"\(height)\">\(cells)</a:tr>"
        }

        return """
        <p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="\(id)" name="table\(id)"/>\
        <p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>\
        <p:xfrm><a:off x="\(box.x)" y="\(box.y)"/><a:ext cx="\(box.width)" cy="\(box.height)"/></p:xfrm>\
        <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">\
        <a:tbl><a:tblPr firstRow="\(header ? 1 : 0)" bandRow="0"/>\
        <a:tblGrid>\(grid)</a:tblGrid>\(body)</a:tbl>\
        </a:graphicData></a:graphic></p:graphicFrame>
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

    /// `p:embeddedFontLst`, or nothing when no font was asked for.
    static func embeddedFontList(_ embed: [(face: Embedding.Face, data: Data)],
                                 typeface: String, firstRelation: Int) -> String {
        guard !embed.isEmpty else { return "" }
        var faces = ""
        for (offset, font) in embed.enumerated() {
            faces += "<p:\(font.face.element) r:id=\"rId\(firstRelation + offset)\"/>"
        }
        /// `p:font`, not `a:font`. The schema declares the element inside
        /// CT_EmbeddedFontListEntry and only borrows its TYPE from
        /// DrawingML — presentationml is elementFormDefault="qualified", so
        /// the element lives in the p: namespace. Written as a:font it
        /// renders everywhere and fails xmllint, which is how it was caught.
        return "<p:embeddedFontLst><p:embeddedFont><p:font typeface=\"\(escape(typeface))\"/>"
            + faces + "</p:embeddedFont></p:embeddedFontLst>"
    }

    // MARK: - The fixed parts

    /// Every layout, listed on the master so the New Slide menu shows them.
    private static var layoutIDs: String {
        let ids = (1...Layouts.all.count)
            .map { "<p:sldLayoutId id=\"\(2_147_483_648 + $0)\" r:id=\"rId\($0)\"/>" }
            .joined()
        return "<p:sldLayoutIdLst>\(ids)</p:sldLayoutIdLst>"
    }

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
        \(layoutIDs)</p:sldMaster>
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
