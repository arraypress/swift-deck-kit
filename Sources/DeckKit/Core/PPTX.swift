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
        embedTypeface: String = Embedding.bundledTypeface,
        firstSlideNumber: Int = 1,
        contexts: [Layout.Context]? = nil
    ) throws -> Data {

        guard !deck.slides.isEmpty else { throw DeckError.empty }
        let layout = Layout(design: design, canvas: canvas)
        var sizes = images.compactMapValues(ImageSize.of)
        /// Supplied by a caller rendering one slide of a larger deck, so
        /// the copy still knows the deck's sections and furniture.
        let contexts = contexts ?? deck.slides.indices.map { deck.context(for: $0, imageSizes: sizes) }
        var allBoxes = deck.slides.enumerated().map { offset, slide in
            layout.boxes(for: slide, context: contexts[offset])
                + [layout.slideNumber(for: slide, number: firstSlideNumber + offset)].compactMap { $0 }
        }
        /// Pies and doughnuts are drawn and placed as pictures unless the
        /// author asked for `native`: Quick Look draws a native pie as one
        /// circle in one colour. The drawing happens here, once, and the box
        /// becomes a picture box like any other.
        var drawn: [(key: String, data: Data)] = []
        for (slideIndex, boxes) in allBoxes.enumerated() {
            for (boxIndex, box) in boxes.enumerated() {
                guard case let .chart(kind, rows, header, native) = box.content, !native,
                      kind == .pie || kind == .doughnut else { continue }
                let key = "chart#\(slideIndex)#\(boxIndex)"
                let width = Int(Double(box.width) / Canvas.perInch * 96)
                let height = Int(Double(box.height) / Canvas.perInch * 96)
                guard let png = ChartImage.pie(Charts.Data(rows: rows, header: header), doughnut: kind == .doughnut,
                                               design: design, width: width, height: height) else { continue }
                drawn.append((key: key, data: png))
                sizes[key] = ImageSize.of(png)
                allBoxes[slideIndex][boxIndex] = Box(x: box.x, y: box.y, width: box.width, height: box.height,
                                                     content: .picture(key, fit: .contain))
            }
        }

        /// Which slides carry a note, 1-based. Only those get a notes part;
        /// a deck with none stays as small as it was.
        let noted = deck.slides.enumerated().compactMap { index, slide -> (Int, String)? in
            guard let note = slide.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !note.isEmpty else { return nil }
            return (index + 1, note)
        }


        var entries: [Zip.Entry] = []
        var media: [String: String] = [:]           // media key → media file name
        var mediaEntries: [Zip.Entry] = []
        var index = 0
        for (path, data) in images.sorted(by: { $0.key < $1.key }) {
            index += 1
            let name = "image\(index).\(((path as NSString).pathExtension).lowercased())"
            media[path] = name
            mediaEntries.append(Zip.Entry(name: "ppt/media/\(name)", data: data))
        }
        for picture in drawn {
            index += 1
            let name = "image\(index).png"
            media[picture.key] = name
            mediaEntries.append(Zip.Entry(name: "ppt/media/\(name)", data: picture.data))
        }
        /// A cover's photograph is carried a second time, darkened in its
        /// pixels — a translucent shape over it would leak in Quick Look.
        for box in allBoxes.joined() {
            guard case let .picture(path, fit) = box.content, case let .cover(dim) = fit,
                  let data = images[path], media[mediaKey(box)] == nil,
                  let dimmed = Darken.apply(data, amount: dim) else { continue }
            index += 1
            let name = "image\(index)-dim.jpg"
            media[mediaKey(box)] = name
            mediaEntries.append(Zip.Entry(name: "ppt/media/\(name)", data: dimmed))
        }

        var slideParts: [(xml: String, rels: String)] = []
        var chartParts: [Zip.Entry] = []
        var chartCount = 0
        let notedSlides = Set(noted.map(\.0))
        for (offset, slide) in deck.slides.enumerated() {
            let boxes = allBoxes[offset]
            var pictures: [(rel: String, name: String)] = []
            for box in boxes {
                if case .picture = box.content, let name = media[mediaKey(box)] {
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
            /// Charts after the links: each is a part of its own, with a
            /// workbook of its own, numbered across the deck.
            var chartRels: [(rel: String, number: Int)] = []
            let ground = groundColour(of: boxes, canvas: canvas, design: design)
            for box in boxes {
                guard case let .chart(kind, rows, header, _) = box.content else { continue }
                chartCount += 1
                let rel = "rId\(pictures.count + linkRels.count + 2 + chartRels.count)"
                chartRels.append((rel: rel, number: chartCount))
                let data = Charts.Data(rows: rows, header: header)
                chartParts.append(.init(name: "ppt/charts/chart\(chartCount).xml",
                                        data: Data(Charts.part(kind: kind, data: data, design: design, ground: ground).utf8)))
                chartParts.append(.init(name: "ppt/charts/_rels/chart\(chartCount).xml.rels",
                                        data: Data(Charts.rels.replacingOccurrences(of: "%N", with: String(chartCount)).utf8)))
                chartParts.append(.init(name: "ppt/embeddings/Microsoft_Excel_Sheet\(chartCount).xlsx",
                                        data: Charts.workbook(data)))
            }
            let number = offset + 1
            slideParts.append((xml: slideXML(boxes, media: media, sizes: sizes, canvas: canvas,
                                             design: design, links: linkIDs, slide: number,
                                             transition: deck.transition, builds: deck.builds,
                                             charts: chartRels.map(\.rel)),
                               rels: slideRels(pictures, links: linkRels, charts: chartRels,
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
        if chartCount > 0 {
            defaults += "<Default Extension=\"xlsx\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\"/>"
        }
        for suffix in Set(media.values.map { ($0 as NSString).pathExtension }) where !suffix.isEmpty {
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
            \((0..<chartCount).map { "<Override PartName=\"/ppt/charts/chart\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>" }.joined())\
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
        entries += chartParts

        return Zip.archive(entries)
    }

    // MARK: - Slides

    /// Which media file a picture box draws: the picture itself, or its
    /// darkened copy for a cover.
    static func mediaKey(_ box: Box) -> String {
        guard case let .picture(path, fit) = box.content else { return "" }
        if case let .cover(dim) = fit { return "\(path)#dim\(dim)" }
        return path
    }

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

    /// Shape ids are unique across the WHOLE deck, not just the slide.
    ///
    /// The specification only asks for uniqueness within a slide, and ids
    /// restarted at 2 on every one. Quick Look's generator renders each
    /// effect shape — a translucent card, a pill — to an attachment and
    /// then places attachments by shape id at document scope, so every
    /// slide whose shapes merely shared an id with a card elsewhere got that
    /// card drawn on it: a 10-slide deck placed its 9 attachments 17 times.
    /// The ghost boxes a real viewer showed were never placeholders.
    static func slideXML(_ boxes: [Box], media: [String: String],
                         sizes: [String: (width: Int, height: Int)] = [:], canvas: Canvas,
                         design: Design, links: [String: String] = [:],
                         slide: Int = 1, transition: Transition = .none,
                         builds: Bool = false, charts: [String] = []) -> String {
        var shapes = ""
        var id = slide * 100 + 1
        var pictureRel = 1
        var chartIndex = 0
        /// The lists on the slide, for a build: a text box whose every
        /// paragraph carries a marker.
        var lists: [(spid: Int, paragraphs: Int)] = []
        let ground = groundColour(of: boxes, canvas: canvas, design: design)
        for box in boxes {
            id += 1
            switch box.content {
            case let .fill(colour):
                shapes += shape(id: id, box: box, panel: .flat(colour), ground: ground)
            case let .panel(panel):
                shapes += shape(id: id, box: box, panel: panel, ground: ground)
            case let .gradient(stops, angle):
                shapes += gradient(id: id, box: box, stops: stops, angle: angle)
            case let .text(runs, align, anchor):
                if builds, !runs.isEmpty, runs.allSatisfy({ $0.marker != .none }) {
                    lists.append((spid: id, paragraphs: runs.count))
                }
                shapes += textBox(id: id, box: box, runs: runs, align: align,
                                  anchor: anchor, design: design, links: links)
            case let .slideNumber(number, size, colour):
                shapes += slideNumberField(id: id, box: box, number: number,
                                           size: size, colour: colour, face: design.bodyFont)
            case let .table(rows, header):
                shapes += table(id: id, box: box, rows: rows, header: header, design: design)
            case .chart:
                guard chartIndex < charts.count else { continue }
                shapes += chartFrame(id: id, box: box, relationship: charts[chartIndex])
                chartIndex += 1
            case let .picture(path, fit):
                guard media[mediaKey(box)] != nil else { continue }
                pictureRel += 1
                shapes += picture(id: id, box: box, relationship: "rId\(pictureRel)",
                                  size: sizes[path], fit: fit)
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
            <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>\
            \(Timing.transition(transition))\(builds ? Timing.builds(lists) : "")</p:sld>
            """
    }

    static func slideRels(_ pictures: [(rel: String, name: String)],
                          links: [(rel: String, target: String)] = [],
                          charts: [(rel: String, number: Int)] = [],
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
        for chart in charts {
            rels.append("<Relationship Id=\"\(chart.rel)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"../charts/chart\(chart.number).xml\"/>")
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

    /// The colour the slide's ground composites to: a gradient's middle, a
    /// full-bleed fill's colour, or the design's background.
    static func groundColour(of boxes: [Box], canvas: Canvas, design: Design) -> String {
        for box in boxes {
            switch box.content {
            case let .gradient(stops, _):
                if let middle = Colour.average(stops.map(\.colour)) { return middle }
            case let .fill(colour) where box.width >= canvas.width && box.height >= canvas.height:
                return colour
            default:
                continue
            }
        }
        return design.background
    }

    /// A filled shape, with or without a soft shadow.
    ///
    /// **Written opaque.** A translucent fill is composited over the ground
    /// here — see `Colour` — because Quick Look renders any shape with alpha,
    /// or with rounded corners, to an attachment and places attachments on
    /// the wrong slides of a longer deck. Square and opaque it is a `div`.
    /// The radius is still honoured when a design insists, and measured to
    /// leak the same way.
    ///
    /// `roundRect`'s adjust is a percentage of **half the shorter side**, so
    /// a radius given as a fraction of the shorter side doubles on the way in.
    private static func shape(id: Int, box: Box, panel: Panel, ground: String) -> String {
        let rounded = panel.radius > 0
        let adjust = min(50_000, Int(panel.radius * 2 * 100_000))
        let geometry = rounded
            ? "<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val \(adjust)\"/></a:avLst></a:prstGeom>"
            : "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>"
        let face = Colour.blend(panel.fill, alpha: panel.fillAlpha, over: ground)
        let fill = "<a:solidFill><a:srgbClr val=\"\(face)\"/></a:solidFill>"
        /// The border straddles the card's edge, so it composites over the
        /// card rather than the ground.
        let line = panel.border.map {
            "<a:ln w=\(Canvas.points(panel.borderWidth).quoted)><a:solidFill><a:srgbClr val=\"\(Colour.blend($0, alpha: panel.borderAlpha, over: face))\"/></a:solidFill></a:ln>"
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

    private static func textBox(id: Int, box: Box, runs: [Run],
                                align: Box.Align, anchor: Box.Anchor,
                                design: Design, links: [String: String] = [:]) -> String {
        /// A placeholder shape is not a text box, and saying it is stops
        /// PowerPoint treating it as the slide's title.
        ///
        /// A subtitle or body placeholder carries `idx="1"` to match the
        /// one on its layout; the title kinds are matched by type alone.
        let placeholder = box.placeholder.map { type in
            let index = type == "subTitle" || type == "body" ? " idx=\"1\"" : ""
            return "<p:nvPr><p:ph type=\"\(type)\"\(index)/></p:nvPr>"
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
                bullet = colour + "<a:buFont typeface=\"\(bulletFace)\"/><a:buChar char=\"\(escape(mark))\"/>"
            case .number:
                /// Counted by PowerPoint, so inserting a line renumbers the
                /// rest instead of leaving the author to fix it by hand.
                bullet = colour + "<a:buFont typeface=\"\(bulletFace)\"/><a:buAutoNum type=\"arabicPeriod\"/>"
            }
            /// A hanging indent, so a wrapped line lines up with the text
            /// above it rather than with the bullet.
            ///
            /// `marL` and `indent` only, **no `lvl`**: `lvl` selects a list
            /// style from the master, and with none defined it overrode these
            /// and left every sub-bullet's marker at the same x while only
            /// its text moved.
            /// Measured from the bullet itself, so the text clears the dash
            /// in every reader rather than in the one it was tuned on.
            let step = TextMetrics.indent(for: run.marker, design: design)
            let indent = run.marker == .none && run.level == 0
                ? ""
                : " marL=\"\(Canvas.points(step + Double(run.level) * step))\" indent=\"-\(Canvas.points(step))\""

            paragraphs += "<a:p><a:pPr algn=\"\(alignment)\"\(indent)>"
                + spacing + before + bullet + "</a:pPr>"
            for span in run.spans where !span.text.isEmpty {
                paragraphs += self.span(span, run: run, design: design, links: links)
            }
            paragraphs += "</a:p>"
        }
        return """
        <p:sp><p:nvSpPr><p:cNvPr id="\(id)" name="text\(id)"/>\(shapeProperties)\(placeholder)</p:nvSpPr>\
        <p:spPr><a:xfrm><a:off x="\(box.x)" y="\(box.y)"/><a:ext cx="\(box.width)" cy="\(box.height)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>\
        <p:txBody><a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="\(anchoring)">\
        <a:noAutofit/></a:bodyPr><a:lstStyle/>\(paragraphs)</p:txBody></p:sp>
        """
    }

    /// The monospaced face for `code`.
    static let codeFace = "Menlo"
    /// The face bullets and numbers are set in — one every reader has.
    static let bulletFace = "Arial"

    /// The face a run is set in, by name.
    static func face(for span: Span, run: Run, design: Design) -> String {
        /// A monospaced face for `code`, because a file name set in the body
        /// face is indistinguishable from prose — which is the whole reason
        /// somebody wrote backticks round it.
        if span.code { return codeFace }
        return run.face == .heading ? design.headingFont : design.bodyFont
    }

    /// One run of text, with whatever marks it carries.
    ///
    /// **Every run names its face.** The theme carries the design's fonts,
    /// but a text box that is not a placeholder inherits nothing from it in
    /// Quick Look, and every deck rendered in the viewer's fallback sans
    /// while the design said Avenir Next — measured with Impact, which is
    /// impossible to mistake, and it came out as Helvetica. LibreOffice
    /// went further: after one run named Menlo, every run without a face
    /// for the rest of the slide came out in a serif.
    private static func span(_ span: Span, run: Run, design: Design,
                             links: [String: String]) -> String {
        let tracking = run.tracking != 0 ? " spc=\"\(Int(run.tracking * 100))\"" : ""
        let bold = (run.bold || span.bold) ? 1 : 0
        let italic = span.italic ? " i=\"1\"" : ""
        let face = "<a:latin typeface=\"\(escape(self.face(for: span, run: run, design: design)))\"/>"
        let link = span.link.flatMap { links[$0] }.map {
            "<a:hlinkClick xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:id=\"\($0)\"/>"
        } ?? ""
        /// `kern="1200"`: pair kerning on from 12pt, which is PowerPoint's
        /// own default for new text and what display type needs — without
        /// it "AV" and "To" sit a hair apart in every heading.
        return "<a:r><a:rPr lang=\"en-GB\" sz=\"\(Int(run.size * 100))\" b=\"\(bold)\"\(italic) kern=\"1200\"\(tracking) dirty=\"0\">"
            + "<a:solidFill><a:srgbClr val=\"\(run.colour)\"/></a:solidFill>"
            + face + link + "</a:rPr><a:t>\(escape(span.text))</a:t></a:r>"
    }

    /// A slide-number field.
    ///
    /// `<a:fld type="slidenum">` rather than a typed digit, so moving a slide
    /// renumbers it. The literal inside is only what a reader that cannot
    /// evaluate the field falls back to.
    private static func slideNumberField(id: Int, box: Box, number: Int,
                                         size: Double, colour: String, face: String) -> String {
        """
        <p:sp><p:nvSpPr><p:cNvPr id="\(id)" name="number\(id)"/><p:cNvSpPr txBox="1"/>\
        <p:nvPr/></p:nvSpPr>\
        <p:spPr><a:xfrm><a:off x="\(box.x)" y="\(box.y)"/><a:ext cx="\(box.width)" cy="\(box.height)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>\
        <p:txBody><a:bodyPr wrap="none" lIns="0" tIns="0" rIns="0" bIns="0" anchor="ctr"/><a:lstStyle/>\
        <a:p><a:pPr algn="r"><a:buNone/></a:pPr>\
        <a:fld id="{B4B7A2E9-0F1C-4A64-9E19-\(String(format: "%012X", id))}" type="slidenum">\
        <a:rPr lang="en-GB" sz="\(Int(size * 100))" dirty="0">\
        <a:solidFill><a:srgbClr val="\(colour)"/></a:solidFill>\
        <a:latin typeface="\(escape(face))"/></a:rPr>\
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
                        + "<a:latin typeface=\"\(escape(span.code ? codeFace : design.bodyFont))\"/>"
                        + "</a:rPr><a:t>\(escape(span.text))</a:t></a:r>"
                }
                if spans.allSatisfy({ $0.text.isEmpty }) { paragraph += "" }
                paragraph += "</a:p>"
                /// No fill and a single hairline under each row: a table with
                /// banded colour fights every design in here, and a rule is
                /// what a designed table actually uses.
                ///
                /// The other three edges are switched OFF by name. Left
                /// unsaid, a reader fills them in from its own default —
                /// LibreOffice drew a black grid round every cell.
                let off = "<a:noFill/>"
                cells += "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/>\(paragraph)</a:txBody>"
                    + "<a:tcPr marL=\"91440\" marR=\"91440\" marT=\"45720\" marB=\"45720\" anchor=\"ctr\">"
                    + "<a:lnL>\(off)</a:lnL><a:lnR>\(off)</a:lnR><a:lnT>\(off)</a:lnT>"
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

    /// The frame a chart part is drawn in.
    private static func chartFrame(id: Int, box: Box, relationship: String) -> String {
        """
        <p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="\(id)" name="chart\(id)"/>\
        <p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>\
        <p:xfrm><a:off x="\(box.x)" y="\(box.y)"/><a:ext cx="\(box.width)" cy="\(box.height)"/></p:xfrm>\
        <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">\
        <c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" r:id="\(relationship)"/>\
        </a:graphicData></a:graphic></p:graphicFrame>
        """
    }

    /// A picture, at its own proportions.
    ///
    /// `stretch` fills the frame it is given, so the frame is cut down to
    /// the picture's shape first and centred in the box the layout offered.
    /// Given the box itself, a 1:3 portrait arrived as a 3:1 landscape —
    /// every diagram squashed, every photograph made fat, silently.
    private static func picture(id: Int, box: Box, relationship: String,
                                size: (width: Int, height: Int)?, fit: Box.Fit = .contain) -> String {
        var frame = (x: box.x, y: box.y, width: box.width, height: box.height)
        var crop = ""
        if let size {
            switch fit {
            case .contain, .leading, .top:
                let fitted = ImageSize.fit(width: size.width, height: size.height, in: box)
                frame = fitted
                /// Against an edge rather than centred: a logo hugs the
                /// margin, a picture beside text starts on the text's line.
                if fit == .leading { frame.x = box.x }
                if fit == .top { frame.y = box.y }
            case .cover:
                /// The picture fills the box and the excess is cropped away
                /// with `srcRect`, in thousandths of a percent per edge.
                let scale = max(Double(box.width) / Double(size.width), Double(box.height) / Double(size.height))
                let visibleWidth = Double(box.width) / scale / Double(size.width)
                let visibleHeight = Double(box.height) / scale / Double(size.height)
                let left = Int((1 - visibleWidth) / 2 * 100_000)
                let top = Int((1 - visibleHeight) / 2 * 100_000)
                crop = "<a:srcRect l=\"\(left)\" t=\"\(top)\" r=\"\(left)\" b=\"\(top)\"/>"
            }
        }
        return """
        <p:pic><p:nvPicPr><p:cNvPr id="\(id)" name="picture\(id)"/>\
        <p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>\
        <p:blipFill><a:blip r:embed="\(relationship)"/>\(crop)\
        <a:stretch><a:fillRect/></a:stretch></p:blipFill>\
        <p:spPr><a:xfrm><a:off x="\(frame.x)" y="\(frame.y)"/><a:ext cx="\(frame.width)" cy="\(frame.height)"/></a:xfrm>\
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
        \((1...6).map { "<a:accent\($0)><a:srgbClr val=\"\(design.chartPalette[($0 - 1) % design.chartPalette.count])\"/></a:accent\($0)>" }.joined())\
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
