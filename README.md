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

Four designs — `studio`, `mono`, `warm`, `slate` — or your own JSON.

## Why a .pptx and not a PDF

`press` in this fleet already sets Markdown as a designed PDF. Nobody can edit
a PDF in a meeting, and the person you hand a deck to wants to change slide
four.

## The grammar

```
# Title, then a section divider          ## A slide heading
- a point                                | splits the points into two columns
> a quotation                            — an attribution, under a quote
! a statement, set large                 ![caption](picture.png)
??? presenter notes                      --- an explicit break
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

That last one is why `Preview` exists. Quick Look renders only the first slide
of a file, so each slide is rendered by previewing a **one-slide copy of the
deck**. A PDF drawn from the same layout model would only show what the model
intended; this shows what a reader sees, including PowerPoint's own line
breaking — the part a generator does not control.

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

## `Check` is an estimate, and says so

PowerPoint does its own line breaking, so nothing here can know exactly where
a line ends. `Check` measures the string in the same font at the same size with
CoreText, works out the lines that needs at the box's width, and compares the
block against the box. It shares its line-height formula with the layout — when
they differed, it reported a problem the layout did not have.

## Tested

28 tests: the grammar keeping every word, a quote's attribution staying with
its quote, a picture keeping the heading above it, the heading landing in the
same place on every slide shape, nothing placed outside the canvas, the same
deck writing byte-identical output, and `&`/`<` escaped while typographic
quotes are left alone.

## Licence

MIT. `Zip.swift` is copied from `swift-text-docx`, which needs the same
container for `.docx`.
