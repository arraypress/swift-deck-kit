//
//  Timing.swift
//  DeckKit
//
//  Transitions and builds — the part of a deck nothing here can watch.
//

import Foundation

/// The `p:transition` and `p:timing` parts of a slide.
///
/// **Validated, not seen.** Quick Look and a PDF both render a still frame,
/// so these are checked against the schema and by a LibreOffice round-trip
/// — it re-exports the timing tree it understood, and every click, target
/// and paragraph range came back. That is the honest limit of what can be
/// said about them from this machine.
enum Timing {

    /// One slide's transition element, or nothing for `.none`.
    static func transition(_ kind: Transition) -> String {
        switch kind {
        case .none: return ""
        case .fade: return "<p:transition spd=\"med\"><p:fade/></p:transition>"
        case .push: return "<p:transition spd=\"med\"><p:push dir=\"l\"/></p:transition>"
        case .wipe: return "<p:transition spd=\"med\"><p:wipe dir=\"l\"/></p:transition>"
        }
    }

    /// "Appear, by paragraph, on click" for each target shape in turn —
    /// the timing tree PowerPoint itself writes for that choice.
    ///
    /// - Parameter targets: the shape ids of the lists, with how many
    ///   paragraphs each has. Empty means no `p:timing` at all.
    static func builds(_ targets: [(spid: Int, paragraphs: Int)]) -> String {
        let clicks = targets.flatMap { target in
            (0..<target.paragraphs).map { (spid: target.spid, paragraph: $0) }
        }
        guard !clicks.isEmpty else { return "" }
        var id = 2
        var body = ""
        for click in clicks {
            body += """
                <p:par><p:cTn id="\(id + 1)" fill="hold"><p:stCondLst><p:cond delay="indefinite"/></p:stCondLst><p:childTnLst>\
                <p:par><p:cTn id="\(id + 2)" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>\
                <p:par><p:cTn id="\(id + 3)" presetID="1" presetClass="entr" presetSubtype="0" fill="hold" nodeType="clickEffect">\
                <p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>\
                <p:set><p:cBhvr><p:cTn id="\(id + 4)" dur="1" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst></p:cTn>\
                <p:tgtEl><p:spTgt spid="\(click.spid)"><p:txEl><p:pRg st="\(click.paragraph)" end="\(click.paragraph)"/></p:txEl></p:spTgt></p:tgtEl>\
                <p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr>\
                <p:to><p:strVal val="visible"/></p:to></p:set>\
                </p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par>
                """
            id += 4
        }
        let builds = targets.map { "<p:bldP spid=\"\($0.spid)\" grpId=\"0\" build=\"p\"/>" }.joined()
        return """
            <p:timing><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"><p:childTnLst>\
            <p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"><p:childTnLst>\
            \(body)</p:childTnLst></p:cTn>\
            <p:prevCondLst><p:cond evt="onPrev" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst>\
            <p:nextCondLst><p:cond evt="onNext" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq>\
            </p:childTnLst></p:cTn></p:par></p:tnLst><p:bldLst>\(builds)</p:bldLst></p:timing>
            """
    }
}
