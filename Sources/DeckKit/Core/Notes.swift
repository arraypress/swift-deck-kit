//
//  Notes.swift
//  DeckKit
//
//  The half of a deck the audience never sees.
//

import Foundation

/// The parts a `.pptx` needs before a speaker note exists.
///
/// This was the gap worth finding: `???` reached the model, `Slide.note`
/// was populated, a test asserted it — and no `notesSlide` part was ever
/// written, so every note the author typed was parsed and then dropped. The
/// grammar promised something the writer never delivered.
enum Notes {

    /// A notes master, which every notes slide must point at.
    static let master = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <p:notesMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld>\
        <p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>\
        <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>\
        <a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>\
        <p:sp><p:nvSpPr><p:cNvPr id="2" name="Notes Placeholder"/>\
        <p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>\
        <p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>\
        <p:spPr><a:xfrm><a:off x="685800" y="4343400"/><a:ext cx="5486400" cy="4114800"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>\
        <p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody></p:sp>\
        </p:spTree></p:cSld>\
        <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" \
        accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" \
        hlink="hlink" folHlink="folHlink"/></p:notesMaster>
        """

    /// One notes slide, carrying the text and nothing else.
    ///
    /// The `<p:ph type="body" idx="1"/>` is what makes PowerPoint and Keynote
    /// show it in the presenter view rather than treating it as a stray
    /// text box on a printed page.
    static func slide(_ text: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld>\
        <p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>\
        <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>\
        <a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>\
        <p:sp><p:nvSpPr><p:cNvPr id="2" name="Notes Placeholder"/>\
        <p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>\
        <p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>\
        <p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>\
        <a:p><a:r><a:rPr lang="en-GB" dirty="0"/><a:t>\(PPTX.escape(text))</a:t></a:r></a:p>\
        </p:txBody></p:sp></p:spTree></p:cSld>\
        <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>
        """
    }

    /// A notes slide points at the slide it belongs to and at the master.
    static func rels(slide index: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster" Target="../notesMasters/notesMaster1.xml"/>\
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="../slides/slide\(index).xml"/>\
        </Relationships>
        """
    }
}
