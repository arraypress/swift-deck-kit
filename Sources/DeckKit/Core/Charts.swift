//
//  Charts.swift
//  DeckKit
//
//  A native chart: the part PowerPoint edits, with the workbook behind it.
//

import Foundation

/// Writes `ppt/charts/chartN.xml` and the workbook it references.
///
/// Written the way PowerPoint writes one — cached references into an
/// embedded sheet — because that is the form every reader draws: Quick Look
/// left a literal-data chart blank, and the schema agrees a series name is
/// a reference or nothing. The sheet is what makes "Edit Data" work.
enum Charts {

    /// A table read as chart data.
    struct Data {
        let categoryTitle: String
        let categories: [String]
        let series: [(name: String, values: [Double])]

        /// The first column is the categories; every other column is a
        /// series. The header row names them when there was one.
        init(rows: [[String]], header: Bool) {
            let width = rows.map(\.count).max() ?? 0
            let head = header ? rows.first ?? [] : []
            let body = header ? Array(rows.dropFirst()) : rows
            func cell(_ row: [String], _ column: Int) -> String { column < row.count ? row[column] : "" }
            categoryTitle = head.first ?? ""
            categories = body.map { cell($0, 0) }
            series = (1..<max(1, width)).map { column in
                let name = header ? cell(head, column) : "Series \(column)"
                return (name: name.isEmpty ? "Series \(column)" : name,
                        values: body.map { Charts.number(cell($0, column)) })
            }
        }
    }

    /// A cell's number: `1,234`, `42%`, `$9.5`, `-3` all read; anything
    /// without digits is zero.
    static func number(_ cell: String) -> Double {
        let kept = cell.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(kept) ?? 0
    }

    /// The column letter for a 0-based index — A for the categories.
    static func column(_ index: Int) -> String {
        var n = index, name = ""
        repeat {
            name = String(UnicodeScalar(65 + n % 26)!) + name
            n = n / 26 - 1
        } while n >= 0
        return name
    }

    // MARK: - The chart part

    static func part(kind: ChartKind, data: Data, design: Design, ground: String) -> String {
        let palette = design.chartPalette
        let text = textProperties(size: design.captionSize, colour: design.body, font: design.bodyFont)
        let gridline = Colour.blend(design.body, alpha: 0.22, over: ground)
        let lastRow = data.categories.count + 1
        let categories = "<c:cat><c:strRef><c:f>Sheet1!$A$2:$A$\(lastRow)</c:f><c:strCache><c:ptCount val=\"\(data.categories.count)\"/>"
            + data.categories.enumerated().map { "<c:pt idx=\"\($0)\"><c:v>\(PPTX.escape($1))</c:v></c:pt>" }.joined()
            + "</c:strCache></c:strRef></c:cat>"

        func series(_ index: Int, _ entry: (name: String, values: [Double]), extra: String = "",
                    fill: String) -> String {
            let letter = column(index + 1)
            let values = "<c:val><c:numRef><c:f>Sheet1!$\(letter)$2:$\(letter)$\(lastRow)</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val=\"\(entry.values.count)\"/>"
                + entry.values.enumerated().map { "<c:pt idx=\"\($0)\"><c:v>\(format($1))</c:v></c:pt>" }.joined()
                + "</c:numCache></c:numRef></c:val>"
            return "<c:ser><c:idx val=\"\(index)\"/><c:order val=\"\(index)\"/>"
                + "<c:tx><c:strRef><c:f>Sheet1!$\(letter)$1</c:f><c:strCache><c:ptCount val=\"1\"/><c:pt idx=\"0\"><c:v>\(PPTX.escape(entry.name))</c:v></c:pt></c:strCache></c:strRef></c:tx>"
                + fill + extra + categories + values + (kind == .line ? "<c:smooth val=\"0\"/>" : "") + "</c:ser>"
        }

        let axes = "<c:axId val=\"500000001\"/><c:axId val=\"500000002\"/>"
        var plot = ""
        var legend = data.series.count > 1
        switch kind {
        case .column, .bar:
            let bars = data.series.enumerated().map { index, entry in
                series(index, entry, extra: "<c:invertIfNegative val=\"0\"/>",
                       fill: solid(palette[index % palette.count]))
            }.joined()
            plot = "<c:barChart><c:barDir val=\"\(kind == .bar ? "bar" : "col")\"/><c:grouping val=\"clustered\"/><c:varyColors val=\"0\"/>"
                + bars + "<c:gapWidth val=\"70\"/><c:overlap val=\"-8\"/>" + axes + "</c:barChart>"
                + categoryAxis(position: kind == .bar ? "l" : "b", text: text, line: gridline)
                + valueAxis(position: kind == .bar ? "b" : "l", text: text, gridline: gridline)
        case .line:
            let lines = data.series.enumerated().map { index, entry in
                let colour = palette[index % palette.count]
                let marker = "<c:marker><c:symbol val=\"circle\"/><c:size val=\"6\"/><c:spPr>\(solidFill(colour))<a:ln><a:noFill/></a:ln></c:spPr></c:marker>"
                return series(index, entry, extra: marker,
                              fill: "<c:spPr><a:ln w=\"28575\" cap=\"rnd\">\(solidFill(colour))<a:round/></a:ln></c:spPr>")
            }.joined()
            plot = "<c:lineChart><c:grouping val=\"standard\"/><c:varyColors val=\"0\"/>" + lines
                + "<c:marker val=\"1\"/>" + axes + "</c:lineChart>"
                + categoryAxis(position: "b", text: text, line: gridline)
                + valueAxis(position: "l", text: text, gridline: gridline)
        case .area:
            let areas = data.series.enumerated().map { index, entry in
                series(index, entry, fill: solid(palette[index % palette.count]))
            }.joined()
            plot = "<c:areaChart><c:grouping val=\"standard\"/><c:varyColors val=\"0\"/>" + areas + axes + "</c:areaChart>"
                + categoryAxis(position: "b", text: text, line: gridline)
                + valueAxis(position: "l", text: text, gridline: gridline)
        case .pie, .doughnut:
            /// One series, one colour per slice, and the share on each.
            legend = true
            let first = data.series.first ?? (name: "Series 1", values: [])
            let slices = data.categories.indices.map { index in
                "<c:dPt><c:idx val=\"\(index)\"/><c:bubble3D val=\"0\"/>\(solid(palette[index % palette.count]))</c:dPt>"
            }.joined()
            let labels = "<c:dLbls><c:numFmt formatCode=\"0%\" sourceLinked=\"0\"/><c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>\(text)"
                + "<c:dLblPos val=\"outEnd\"/><c:showLegendKey val=\"0\"/><c:showVal val=\"0\"/><c:showCatName val=\"0\"/>"
                + "<c:showSerName val=\"0\"/><c:showPercent val=\"1\"/><c:showBubbleSize val=\"0\"/><c:showLeaderLines val=\"1\"/></c:dLbls>"
            let element = kind == .pie ? "pieChart" : "doughnutChart"
            plot = "<c:\(element)><c:varyColors val=\"1\"/>"
                + series(0, first, extra: slices + labels, fill: "")
                + "<c:firstSliceAng val=\"0\"/>" + (kind == .doughnut ? "<c:holeSize val=\"58\"/>" : "")
                + "</c:\(element)>"
        }

        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" \
            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
            <c:date1904 val="0"/><c:roundedCorners val="0"/>\
            <c:chart><c:autoTitleDeleted val="1"/><c:plotArea><c:layout/>\(plot)\
            <c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr></c:plotArea>\
            \(legend ? "<c:legend><c:legendPos val=\"b\"/><c:overlay val=\"0\"/>\(text)</c:legend>" : "")\
            <c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart>\
            <c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>\
            \(text)\
            <c:externalData r:id="rId1"><c:autoUpdate val="0"/></c:externalData>\
            </c:chartSpace>
            """
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    private static func solidFill(_ hex: String) -> String {
        "<a:solidFill><a:srgbClr val=\"\(hex)\"/></a:solidFill>"
    }

    /// A shape's fill and no outline.
    private static func solid(_ hex: String) -> String {
        "<c:spPr>\(solidFill(hex))<a:ln><a:noFill/></a:ln></c:spPr>"
    }

    /// Default text for the whole chart: the body face, the caption size,
    /// the body colour. Named on the chart because, like a text box, it
    /// inherits nothing a reader can be relied on to look up.
    private static func textProperties(size: Double, colour: String, font: String) -> String {
        "<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz=\"\(Int(size * 100))\" b=\"0\">"
            + "<a:solidFill><a:srgbClr val=\"\(colour)\"/></a:solidFill><a:latin typeface=\"\(PPTX.escape(font))\"/>"
            + "</a:defRPr></a:pPr><a:endParaRPr lang=\"en-GB\"/></a:p></c:txPr>"
    }

    private static func categoryAxis(position: String, text: String, line: String) -> String {
        "<c:catAx><c:axId val=\"500000001\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/>"
            + "<c:axPos val=\"\(position)\"/><c:numFmt formatCode=\"General\" sourceLinked=\"1\"/>"
            + "<c:majorTickMark val=\"none\"/><c:minorTickMark val=\"none\"/><c:tickLblPos val=\"nextTo\"/>"
            + "<c:spPr><a:ln w=\"9525\">\(solidFill(line))</a:ln></c:spPr>\(text)"
            + "<c:crossAx val=\"500000002\"/><c:crosses val=\"autoZero\"/><c:auto val=\"1\"/><c:lblAlgn val=\"ctr\"/>"
            + "<c:lblOffset val=\"100\"/><c:noMultiLvlLbl val=\"0\"/></c:catAx>"
    }

    private static func valueAxis(position: String, text: String, gridline: String) -> String {
        "<c:valAx><c:axId val=\"500000002\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/>"
            + "<c:axPos val=\"\(position)\"/><c:majorGridlines><c:spPr><a:ln w=\"6350\">\(solidFill(gridline))</a:ln></c:spPr></c:majorGridlines>"
            + "<c:numFmt formatCode=\"General\" sourceLinked=\"1\"/><c:majorTickMark val=\"none\"/><c:minorTickMark val=\"none\"/>"
            + "<c:tickLblPos val=\"nextTo\"/><c:spPr><a:ln><a:noFill/></a:ln></c:spPr>\(text)"
            + "<c:crossAx val=\"500000001\"/><c:crosses val=\"autoZero\"/><c:crossBetween val=\"between\"/></c:valAx>"
    }

    // MARK: - The workbook

    /// The chart part's relationships: the sheet behind it.
    static let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/package" Target="../embeddings/Microsoft_Excel_Sheet%N.xlsx"/>\
        </Relationships>
        """

    /// A one-sheet `.xlsx` holding the table, so PowerPoint's Edit Data
    /// opens something. Inline strings, no shared-string table, one style.
    static func workbook(_ data: Data) -> Foundation.Data {
        func cell(_ reference: String, text: String) -> String {
            "<c r=\"\(reference)\" t=\"inlineStr\"><is><t>\(PPTX.escape(text))</t></is></c>"
        }
        func cell(_ reference: String, number: Double) -> String {
            "<c r=\"\(reference)\"><v>\(format(number))</v></c>"
        }
        var rows = "<row r=\"1\">" + cell("A1", text: data.categoryTitle)
            + data.series.enumerated().map { cell("\(column($0 + 1))1", text: $1.name) }.joined() + "</row>"
        for (index, category) in data.categories.enumerated() {
            let row = index + 2
            rows += "<row r=\"\(row)\">" + cell("A\(row)", text: category)
                + data.series.enumerated().map { cell("\(column($0 + 1))\(row)", number: index < $1.values.count ? $1.values[index] : 0) }.joined()
                + "</row>"
        }
        let entries: [Zip.Entry] = [
            .init(name: "[Content_Types].xml", data: Foundation.Data("""
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
                <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
                <Default Extension="xml" ContentType="application/xml"/>\
                <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
                <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
                <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
                </Types>
                """.utf8)),
            .init(name: "_rels/.rels", data: Foundation.Data("""
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
                <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
                </Relationships>
                """.utf8)),
            .init(name: "xl/workbook.xml", data: Foundation.Data("""
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
                <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
                xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
                <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>
                """.utf8)),
            .init(name: "xl/_rels/workbook.xml.rels", data: Foundation.Data("""
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
                <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
                <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
                </Relationships>
                """.utf8)),
            .init(name: "xl/styles.xml", data: Foundation.Data("""
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
                <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
                <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>\
                <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
                <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
                <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
                <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>\
                </styleSheet>
                """.utf8)),
            .init(name: "xl/worksheets/sheet1.xml", data: Foundation.Data("""
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
                <sheetData>\(rows)</sheetData></worksheet>
                """.utf8)),
        ]
        return Zip.archive(entries)
    }
}
