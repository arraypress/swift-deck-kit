# Swift DeckKit

Markdown in, editable PowerPoint out.

```swift
import DeckKit

let deck = Markdown.deck(from: markdown)
let design = try Designs.named("studio")

try DeckWriter.write(deck, design: design, to: url)          // .pptx
let slides = try Preview.render(deck: deck, design: design,  // one PNG per slide
                                into: folder)
Check.problems(in: deck, design: design)                     // what will not fit
```

Six designs. Two modern — `aurora` (dark) and `daylight` (light), with
gradient grounds, translucent rounded cards and tight display type — and four
restrained: `studio`, `mono`, `warm`, `slate`. Or your own JSON.

## Why a .pptx and not a PDF

`press` in this fleet already sets Markdown as a designed PDF. Nobody can edit
a PDF in a meeting, and the person you hand a deck to wants to change slide
four.

## The grammar

```
# Title, then a section divider     ## A slide heading
- a point                          | splits the points into two columns
> a quotation                      — an attribution, under a quote
! a statement, set large           ![caption](picture.png)
= 91 | tools installed             a figure and what it counts
:: Keyless | nothing to sign up    a card
1. a numbered point                  - an indented sub-point
**bold**  *italic*  `code`         [label](https://…)
??? presenter notes                --- an explicit break
^ a kicker, above a heading
```

Small on purpose: an author should hold it in their head. Headings, statements,
quotes and pictures each begin a slide, so nothing needs a separator — and
**nothing the author wrote is ever dropped**, which a test asserts word by
word.

## Verified against the specification

- **ECMA-376 XSDs**, from Apache POI's `poi-ooxml-full` jar — every part
  validates: slides, presentation, master, layout, theme. (ECMA's own download
  URLs 404 now.)
- **python-pptx**, an independent implementation — opens the file, reads every
  slide's text, saves and reopens it.
- **Quick Look** — which previews `.pptx` on a Mac with **no Keynote,
  PowerPoint or LibreOffice installed**, measured on a machine with none of
  them.
- **LibreOffice**, headless, as a second renderer. Stricter than Quick Look
  about geometry: it honours the hanging indents Quick Look ignores and draws
  the table borders a writer leaves unsaid. (Headless on macOS it resolves
  none of the system fonts, so it checks structure, not typography.)

One known erratum: the first-edition XSD types `buSzPct` as a percent string
(`85%`). PowerPoint and LibreOffice both write and read the decimal form
(`85000`) — LibreOffice round-trips it unchanged — and so does this.

That last one is why `Preview` exists. Quick Look renders only the first slide
of a file, so each slide is rendered by previewing a **one-slide copy of the
deck**. A PDF drawn from the same layout model would only show what the model
intended; this shows what a reader sees, including PowerPoint's own line
breaking — the part a generator does not control.

## Speaker notes actually reach the file

`???` used to be parsed, exposed as `Slide.note`, asserted by a test — and
never written. Every note the author typed was dropped. There is a
`notesMaster` and a `notesSlide` part now, and the slide points at its notes
as well as the other way round: without that relationship a reader finds
nothing, which is how `has_notes_slide` stayed false while the part existed.

A deck with no notes carries no notes parts.

## Inline marks, lists and links

`**bold**`, `*italic*`, `` `code` `` (set in a monospaced face) and
`[label](url)` (a real external hyperlink) — one `<a:p>` holding several
`<a:r>`, which is how OOXML models it too.

An **unclosed** marker stays literal. It used to fall through to the italic
branch, which matched the *second* asterisk of a `**` pair, produced an empty
span and silently ate the marks.

Lists carry levels and numbering: two spaces of indent is one level, and
`1.` / `1)` become `buAutoNum` so **PowerPoint does the counting** — an author
who renumbers by hand always ends up with two number sevens. Indentation is
`marL` + a hanging `indent`, and deliberately **no `lvl`**: `lvl` selects a
list style from the master, and with none defined it overrode both and left
every sub-bullet's marker at the same x while only its text moved.

## Tables, numbers, layouts

A Markdown pipe table becomes a **real `<a:tbl>`**, not a picture of one — the
person you hand the deck to can edit a cell, which is the entire reason this
writes PowerPoint instead of a PDF. A lone `|` still means two columns; a pipe
with content round it means a table.

Slide numbers are a `<a:fld type="slidenum">`, so moving a slide renumbers it.
Off unless the design asks, and never on a title or section slide.

**Four layouts with real placeholders.** With one blank layout the recipient's
*New Slide* menu was empty, the **outline pane showed nothing** — no text sat
in a title placeholder, so PowerPoint had no idea which box was the heading —
and "Reset" did nothing. The file opened and looked right, and behaved like a
folder of pictures.

## Carrying the typeface

**The face is named on every run.** The theme carries the design's fonts, but
a text box that is not a placeholder inherits nothing from it in Quick Look:
set in Impact — impossible to mistake — the deck rendered in Helvetica, which
is how every earlier deck had rendered while the design said Avenir Next.
LibreOffice went further: after one run named Menlo, every run without a face
for the rest of the slide came out in a serif. Measured: with the face on the
run, Quick Look resolves Avenir Next, Helvetica Neue, Menlo, Futura, Gill
Sans, Georgia, Trebuchet, Verdana and Impact; `SF Mono` and `Inter` it does
not.

A `.pptx` **names** fonts; it does not carry them. A deck set in a face the
recipient has not got renders in whatever their machine substitutes — which is
why `SF Pro` is not an option (it is installed as `.SFNS-Regular` under
`.AppleSystemUIFont`, and asking for it by name returns Helvetica) and why
`Avenir Next`, lovely on a Mac, degrades on Windows.

`Embedding.bundled()` carries [Inter](https://github.com/rsms/inter) — SIL OFL
1.1, which explicitly permits embedding — as four `fntdata` parts, about
1.6 MB. **Optional, not assumed:** PowerPoint honours an embedded font,
Keynote and Google Slides largely ignore it, and no format solves those.

A file that is not a font is refused on its magic number, because a `.pptx`
carrying a text file named `.ttf` opens and then renders nothing, with no error
anywhere.

## The modern vocabulary

All of it is in OOXML and none of it was used at first, which is most of why
the first decks looked a decade old: flat fills, square corners, no depth, no
transparency, no tracking.

- **Gradient grounds** (`gradFill`), on feature slides and body slides alike
- **Cards** with hairline borders and **soft shadows** (`outerShdw`) — square
  and opaque by measurement (below); a design's translucency is composited
  over the ground at write time
- **Negative letter-spacing** (`spc`) on display type — the single change that
  most separates a modern heading from a dated one
- **Tightened line spacing** (`lnSpc`) for large headings
- **Stat** and **card** slide shapes, which a modern deck is built from

**Fonts are measured, not assumed.** `SF Pro Display`, `SF Pro Text` and
`Inter` do **not** resolve on macOS by those names — they fall back to a serif,
which is exactly what a dated deck looks like. `Avenir Next` does, and is the
best modern geometric sans available; the modern designs use it.

## One rhythm, not a number per slide

Type sizes are `base × ratio^step`, rounded to whole points. Vertical
positions come from three numbers: the margin, the heading band, and the gap.
A heading therefore sits in the same place on every slide of a deck, which is
most of the difference between a deck that looks designed and one that looks
assembled.

Three faults found by looking at the render rather than the code:

- **A heading that wrapped ran straight through the accent rule.** The heading
  box is anchored to its *bottom* now and the band is two heading lines deep by
  construction, so it grows upward into empty space.
- **A statement slide was set at heading size**, making the slide meant to be
  remembered look like an ordinary one. It is two steps larger.
- **`columns` had no grammar**, so the layout could never fire and every
  comparison came out as one long list.
- **`lnSpc` must come before `spcBef`.** Written the other way round it renders
  in Quick Look and `xmllint --schema pml.xsd` rejects it — a lenient
  previewer hides what PowerPoint might not forgive.

## Measured, then placed

Cards are as deep as the tallest one's content, a short list sits a little
above the centre of its room rather than dead in it, and both columns of a
comparison start on the same line — all from setting the text in its own face
with CoreText (`TextMetrics`), which `Check` shares. The hanging indent is
measured from the bullet: at 17pt the em dash touched its sentence in
LibreOffice and PowerPoint, where the text starts exactly at the indent, and
the 17 had been tuned on Quick Look, which pads a bullet by itself.

## What a second renderer found

Quick Look is lenient. Rendering the same deck through LibreOffice, and
setting a probe deck in Impact, found seven faults it had hidden:

- **The design's font never reached the text** — above.
- **Pictures were stretched to their box**: a 1:3 portrait arrived as a 3:1
  landscape. The frame is cut to the picture's proportions (read with ImageIO,
  without decoding) and centred in the box the layout offers.
- **Title and subtitle shared one placeholder**, so python-pptx read the title
  as `"Title\nSubtitle"`. They are `ctrTitle` and `subTitle`; a section's
  line is its `body`.
- **Tables drew a black grid** in LibreOffice: only the bottom border was
  written, and a reader fills the other three in from its own default. All
  four edges are stated.
- **`normAutofit`** invited every reader to shrink text by its own rule. The
  layout is measured, so text boxes say `noAutofit` and `Check` catches
  overflow.
- **The kicker was configured and never drawn.** `^ Results` above a heading
  sets it: uppercase, tracked, in the design's kicker colour, on a pill in
  the modern designs.
- **Translucent and rounded shapes leaked onto other slides in Quick Look** —
  the biggest, and the last found. Quick Look's generator renders any shape
  with an alpha channel *or* rounded corners to a PDF attachment, then places
  attachments on the wrong slides of a longer deck: a ten-slide deck's 9
  cards were drawn 17 times, on slides that had no cards. Two-slide probes
  never leak, which is why every earlier check passed, and shape ids made
  unique across the deck changed nothing. Square and opaque, the same card is
  a `div` and stays put. So: translucent fills are composited over the ground
  at write time (`Colour`), the modern designs are square, and a test runs the
  real generator on a ten-slide deck and asserts zero attachments.

## `Check` is an estimate, and says so

PowerPoint does its own line breaking, so nothing here can know exactly where
a line ends. `Check` measures the string in the same font at the same size with
CoreText, works out the lines that needs at the box's width, and compares the
block against the box. It shares its line-height formula with the layout — when
they differed, it reported a problem the layout did not have.

## Tested

112 tests: the grammar keeping every word, a quote's attribution staying with
its quote, a picture keeping the heading above it, the heading landing in the
same place on every slide shape, nothing placed outside the canvas, the same
deck writing byte-identical output, and `&`/`<` escaped while typographic
quotes are left alone.

## Licence

MIT. `Zip.swift` is copied from `swift-text-docx`, which needs the same
container for `.docx`.
