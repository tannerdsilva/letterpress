# letterpress

a declarative, zero-dependency pdf exporter for swift. the sibling of
[`no-webui`](../no-webui): same architecture, different wire format — instead
of html/css, it writes the pdf object model by hand.

## why "letterpress"

because that is exactly what it is. letterpress set every glyph by hand, one
piece of type at a time, long before engines took over. so does this package —
the pdf writer, the winansi encoder, and the base-14 font metrics are all
hand-set here, with no pdf engine and no external dependencies.

## quickstart

```swift
import Letterpress

let document = PDFDocument {
    PDFPage(.a4) {
        Text("hello, letterpress")
            .font(.helveticaBold, size: 32)
            .foregroundColor(.ink)
            .at(x: 72, y: 72)

        Paragraph("a mark protocol, a result-builder dsl, value-type "
                + "primitives, and modifiers that wrap content emission.")
            .font(.times, size: 12)
            .frame(maxWidth: 460)
            .lineHeight(1.5)
            .at(x: 72, y: 120)

        Rect(x: 72, y: 200, width: 130, height: 70, cornerRadius: 12)
            .fill(.sky.opacity(0.35))
            .stroke(.blue, width: 2)

        Ellipse(x: 240, y: 200, width: 90, height: 70)
            .fill(.amber.opacity(0.5))

        Line(from: Point(x: 72, y: 300), to: Point(x: 540, y: 300))
            .stroke(.indigo, width: 3)
    }
    .background(Color(hex: 0xF8FAFC))
}

let bytes = document.render()         // [UInt8]
try document.write(to: someURL)       // or straight to disk
```

## the model

| concept | pdf-land |
|---|---|
| a drawing instruction | `Mark` — `func write(to renderer: inout Renderer)` + `func sizeThatFits(_:in:)` |
| a mark that can state its path on demand | `PathMark` — `func writePath(to renderer: inout Renderer)`; lets a second paint in a chain restate the geometry the first one consumed |
| wraps a mark's emission | `MarkModifier` — balanced `q`/`Q` scopes |
| mark + modifier, types preserved | `ModifiedMark<Content, M>` |
| composition | `MarkBuilder` / `PageBuilder` result builders |
| auto-layout | `HStack` / `VStack` / `ZStack` — measured flex, `Spacer` distributes leftover |
| a proposal | `ProposedSize` — `nil` on an axis means "use your ideal size" |
| a body broken into pages | `Galley` — a paginated vertical stack, one logical body → N physical pages |
| a page | `PDFPage(size: PageSize)` |
| the document | `PDFDocument { pages }` → `render()` |

coordinates are **y-down, web-orientation, top-left origin** (points).
text anchors at the top-left of its first line; `.alignment(.center) / .trailing`
re-anchor on the measured text width. word wrap is `.frame(maxWidth:)` on a
`Paragraph`.

## auto layout

containers place their children, so you place the container and the children
flow — page-level `.at(x:y:)` stays explicit, only what's inside a container
auto-places:

```swift
VStack(spacing: 10) {
    Text("hello, letterpress").font(.helveticaBold, size: 22)
    Paragraph("wrapped column text ...").frame(maxWidth: 300).lineHeight(1.4)
    Rect(x: 0, y: 0, width: 300, height: 26).fill(.sky.opacity(0.35))
}
.at(x: 72, y: 72)

HStack(alignment: .center) {
    Spacer()
    Text("centered by flex").font(.helvetica, size: 12)
    Spacer()
}
.frame(maxWidth: 400)   // the only proposal producer: finite width enables flex
.at(x: 72, y: 200)
```

- every `Mark` answers `sizeThatFits(_ proposal:in:)`; stacks measure each
  child once, sum the main axis, and place children by the same pure function
  they measure with, so measure and render can never disagree
- `Spacer(minimumLength:)` absorbs leftover main-axis space and splits it
  equally among flex children (any `FlexibleMark`, not just `Spacer`) when
  a finite proposal exceeds the content; without a proposal (or flex
  children) a stack hugs and overflow is legal
- `frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:vertical:)`
  resolves a proposal and reports a box clamped from the content — a finite
  `maxWidth` re-wraps text, a `min` bound forces the box larger, and
  `alignment`/`vertical` center or push content inside it; when the box is
  smaller than the content, the content overflows visibly
- stroke width is included in a stroked mark's measured extent, so stacks
  and frames space for the bleed
- a child inside a container must not carry its own `.at` — the container
  places it
- `ZStack` layers children back-to-front at the container's origin
- flow pagination: a `Galley` breaks one logical body across physical pages
  at sibling boundaries — spacing never leaks across a break, each physical
  page is an ordinary `PDFPage` (same objects, resources, determinism), and
  a child taller than the content box overflows visibly rather than splitting
- measurement is exact: the same afm widths drive wrapping, alignment, and
  auto layout, so a stacked column is byte-identical on every render

## features

- all 12 base-14 fonts by name (`Font.helveticaBold`, `Font.times`, ...), with
  each face's OWN afm advance widths compiled in for measurement, alignment,
  and wrapping — a bold or italic face never borrows its regular sibling's
  metrics (only the oblique faces are genuinely metric-identical to their
  upright sibling, and only courier is uniform across its four faces)
- shapes: `Rect` (incl. rounded), `Ellipse` (circles via square bounds),
  `Line`, `Polygon`, full-bleed page `background`
- auto layout: `HStack`/`VStack` flex containers with `Spacer` distribution,
  `ZStack` layering, and a `.frame(maxWidth:maxHeight:)` proposal — every
  mark measures itself exactly (afm-width text, shape geometry)
- flow pagination: a `Galley` measures a body at the column width, packs it
  into the content box, and materializes one plain physical page per bucket
- `Color` with hex/int initializers and `.opacity(_:)` — transparency renders
  through shared, deduplicated `/ExtGState` resources
- winansi text encoding: the content stream stays 7-bit — latin-1 letters and
  the cp1252 punctuation slots travel as three-digit octal escapes, typographic
  punctuation (`"`, `'`, `—`, `–`, `…`, `€`, `™`, ...) is mapped to its cp1252
  slot, and every font dict declares `/Encoding /WinAnsiEncoding`
- paint composition: `.fill(...).stroke(...)` paints both — a paint ends with a
  path-consuming operator (`f`/`S`) and pdf has no paint that leaves the path
  intact, so the outer paint restates the geometry through `PathMark`
- deterministic output (byte-identical across runs), minimal numbers
  (`612`, not `612.00`), trimmed trailing zeros
- pure swift, no Foundation beyond `Date`/`URL`/`Data`/`FileManager`; the
  renderer accumulates `[UInt8]`

## markdown → pdf

`LetterpressMarkdown` is a separate, zero-dependency target that typesets a
markdown subset into a paginated document. `letterpress-md` is the CLI over it;
the CLI is the only target in the package that takes a dependency
(`swift-argument-parser` — the exporter and the markdown layer stay clean).

```bash
swift run letterpress-md Examples/markdown-sample.md -o sample.pdf
swift run letterpress-md - -o out.pdf < input.md        # stdin
```

```swift
import LetterpressMarkdown

let document = MarkdownDocument(parsing: source)
let bytes = document.render(style: .standard)   // or .pdfDocument() for the pages
```

- `BasicMarkdownParser` (a `MarkdownParser`) handles atx/setext headings,
  paragraphs, fenced code, blockquotes, ordered and unordered lists (nested by
  indent), thematic breaks, `**bold**`, `*italic*`, `***both***`, `` `code` ``,
  `[links](url)`, `![alt](url)`, backslash escapes, entities, and hard breaks
- blocks compose into `Mark`s and flow through one `Galley`, so a long document
  paginates with no manual page management
- `MarkdownStyle` carries the whole look — page geometry, typefaces, sizes,
  colours, rhythm — in one value type
- inline runs are laid out word by word using only the exporter's public
  surface, so the markdown layer adds no API to `Letterpress`
- the CLI is a `ParsableCommand`: `--help`/`--version` are free, a bad value or
  unknown flag exits 64 with usage, an unreadable input exits 1 with a message,
  and `--quiet`/`--no-quiet` is a proper flag pair. it prints a compact json
  summary (`{"blocks":…,"pages":…,"bytes":…}`) so it composes with other tools

## verify

```bash
swift test                              # 144 tests, 19 suites
swift run LetterpressExample            # writes letterpress-example.pdf
swift run letterpress-md Examples/markdown-sample.md -o sample.pdf
pdfinfo/pdftotext/pdftoppm letterpress-example.pdf   # independent parser check
```

the pdf is verified against poppler's `pdfinfo`/`pdftotext`/`pdftoppm`, which
have caught real operator bugs a self-referential test cannot.

## limitations (v1, by design)

- base-14 fonts only — no embedding, no unicode beyond winansi; glyphs
  outside it degrade to `?`. every font dict declares
  `/Encoding /WinAnsiEncoding`, so the cp1252 escapes behind typographic
  punctuation (`—`, `…`, `“` `”`, `€`, `™`) both render and round-trip
  through `pdftotext`
- no images, no flate compression, no links/form fields
- text is measured from afm advance widths (no kerning); line position uses
  an 0.8em baseline approximation

## docs

api docs are inline `///` comments; this README is the reference for the
architecture, the y-down coordinate law, auto layout, and pagination.
