# ``LetterpressMarkdown``

typeset a markdown subset into a paginated pdf.

`LetterpressMarkdown` is a separate, zero-dependency target over the
`Letterpress` exporter. it parses markdown into a block model, composes each
block into ordinary marks, and flows the whole document through one galley so a
long document paginates with no manual page management.

## Overview

```swift
import LetterpressMarkdown

let document = MarkdownDocument(parsing: source)
let bytes = document.render(style: .standard)                 // [UInt8]
let pdf = document.pdfDocument(style: .standard)              // the document, before writing
let (pages, warnings) = document.pagination()                 // + whatever would not fit
```

`pagination()` is `pdfDocument()` with the overflow report kept: it returns the
same physical pages alongside one `PaginationWarning` per mark the text column
could not hold. `pdfDocument()` and `render()` discard that report, which is the
right default for a document you know fits.

the layered shape is deliberate:

1. **parse.** a `MarkdownParser` turns source text into a `MarkdownDocument` —
   an ordered list of `Block` values. `BasicMarkdownParser` is the shipped
   conformer.
2. **compose.** each block becomes a `Mark`, with its vertical rhythm baked
   into the mark's own height so the galley can space blocks with a plain
   stack.
3. **paginate.** the composed marks flow through a single `Galley`, which
   breaks them across physical pages — between blocks, and inside any block
   that can be continued: text between lines, a code block between lines, a
   list between items, a quote between its children.

because step 2 composes only from the exporter's public surface, this layer
adds no api to `Letterpress`. a different conformer — say, one backed by a full
CommonMark implementation — drops in without the renderer changing a line.

### what the shipped parser handles

atx and setext headings, paragraphs, fenced code with an info word,
blockquotes, ordered and unordered lists nested by indent, pipe tables
(a header row, a `| --- |` delimiter row with optional `:` alignment markers,
then body rows), thematic breaks, `**strong**`, `*emphasis*`, `***both***`,
`~~struck through~~`, `code spans`, `[links](url)`, `![alt](url)`, backslash
escapes, html entities, and hard breaks.

deliberately out of scope: footnotes, reference links, task lists,
autolinks, raw html passthrough, and lazy blockquote continuation.

### the look is one value

`MarkdownStyle` carries the whole theme — page geometry, typefaces, sizes,
colours, and rhythm — in a single value type. pass a customised one to
`MarkdownDocument/pdfDocument(style:)` or `MarkdownDocument/render(style:)`.

the shipped default is a letterpress scheme: prose sets in a serif on a
measured column that holds a line near eighty-five characters, structure
sets in a sans that never competes with it, and one accent ink is spent only
where it carries meaning — the accent segment of the rule under an `h1`, an
`h3` head, list markers, the quote bar, the rule beneath a table's header
row, the edge bar of a code panel, and the diamond of a thematic break.
every other separator is a hairline, so the page has no heavy rule anywhere.
the heading scale separates six levels: the display size for `h1`, then
`1.32×`, `1.14×` in the accent, body size, and finally small tracked
uppercase labels for `h5`/`h6`.

prose sets flush: every line the wrap breaks is opened out to the measure, up
to `justificationLimit` times the natural word space. a line that would need
more is left ragged, and the closing line of a paragraph always is — a
stretched line must never read worse than an uneven edge. the tracking of a
tracked label is folded into the word gap as well as into the glyphs, so an
uppercase label keeps its words apart instead of running them together.

a thematic break draws a set ornament — a hairline either side of a small
accent diamond — rather than a glyph: the base-14 winansi set carries no
fleuron or asterism, and a missing glyph would degrade to `?`.

every page carries a running folio: the document title in tracked uppercase at
the leading edge, the page number over the total at the trailing edge, over
one hairline across the measure. this is furniture rather than content, so it
never displaces a line the text column needs.

a wrap never opens a line with a lone punctuation mark: a mark that cannot fit
hangs past the column edge instead, which is why a paragraph that ends in a
bold run plus a colon closes the line rather than orphaning the mark.

a code panel sets at the largest size that still holds its longest line, so a
line a character or two over the measure is fitted rather than broken into an
orphan fragment. a block whose longest line no size can hold — a fenced log of
very long lines — keeps the full code size and wraps, because shrinking it
further would cost legibility without removing the wrap.

## Topics

### Parsing

- ``MarkdownParser``
- ``BasicMarkdownParser``

### The document model

- ``MarkdownDocument``
- ``Block``
- ``ListItem``
- ``Table``
- ``TableCell``
- ``TableRow``
- ``InlineRun``
- ``InlineTraits``

### Rendering

- ``MarkdownStyle``
- ``MarkdownTypeface``
- ``MarkdownDocument/pdfDocument(style:)``
- ``MarkdownDocument/pagination(style:)``
- ``MarkdownDocument/render(style:)``

### Articles

- <doc:MarkdownPipeline>