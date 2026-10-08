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
let bytes = document.render(style: .standard)        // [UInt8]
let pages = document.pdfDocument(style: .standard)   // the pages, before writing
let (flowed, warnings) = document.pagination()       // + whatever would not fit
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
blockquotes, ordered and unordered lists nested by indent, thematic breaks,
`**strong**`, `*emphasis*`, `***both***`, `code spans`, `[links](url)`,
`![alt](url)`, backslash escapes, html entities, and hard breaks.

deliberately out of scope: tables, footnotes, reference links, task lists,
autolinks, raw html passthrough, and lazy blockquote continuation.

### the look is one value

`MarkdownStyle` carries the whole theme — page geometry, typefaces, sizes,
colours, and rhythm — in a single value type. pass a customised one to
`MarkdownDocument/pdfDocument(style:)` or `MarkdownDocument/render(style:)`.

## Topics

### Parsing

- ``MarkdownParser``
- ``BasicMarkdownParser``

### The document model

- ``MarkdownDocument``
- ``Block``
- ``ListItem``
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