# ``Letterpress``

a declarative, zero-dependency pdf exporter for swift.

letterpress describes pages the way swiftui describes views: you compose value
types that declare *what* is drawn, and a two-pass engine measures the layout
and then writes the pdf content stream. there is no imperative drawing api and
no third-party dependency — the pdf writer, the winansi encoder, and the
base-14 font metrics are all hand-set here.

## Overview

a document is a list of pages; a page is a size plus a list of marks:

```swift
import Letterpress

let document = PDFDocument {
    PDFPage(.a4) {
        Text("hello, letterpress")
            .font(.helveticaBold, size: 32)
            .foregroundColor(.ink)
            .at(x: 72, y: 72)

        Paragraph("a mark protocol, a result-builder dsl, and modifiers "
                + "that wrap content emission.")
            .font(.times, size: 12)
            .frame(maxWidth: 460)
            .lineHeight(1.5)
            .at(x: 72, y: 120)
    }
    .background(Color(hex: 0xF8FAFC))
}

let bytes = document.render()       // [UInt8]
try document.write(to: someURL)     // or straight to disk
```

every mark is a value type, and every modifier returns a new type —
`ModifiedMark<Content, Modifier>` — so the concrete type survives the whole
modifier chain. nothing is erased unless you ask for it, with `AnyMark`.

### the two passes

1. **measure.** `Mark.sizeThatFits(_:in:)` walks the tree with a
   `ProposedSize` and returns the `Size` a node wants. containers distribute
   space to their children here.
2. **write.** `Mark.write(to:)` walks the same tree with the resolved geometry
   and appends operators through a `Renderer`, which accumulates one page's
   content stream and tracks the resources that page references.

measurement and drawing therefore read the same numbers: a run is never drawn
at a position it was not first measured into, so a document renders
byte-identically on every run.

### coordinates

points (1/72 inch), **y-down**, top-left origin — the same orientation as a web
page. text anchors at the top-left of its first line, and
`.alignment(.center)` / `.trailing` re-anchor on the measured text width.

### composition

`Mark` and `MarkModifier` are implementable from outside the package. a
conformer composes the built-in marks, or appends raw operators through
`Renderer`. the paint helpers are declared on `PathMark`, so a mark with no
path cannot be painted — `Text("x").fill(.red)` does not compile.

## Topics

### Documents and pages

- ``PDFDocument``
- ``PDFPage``
- ``PageSize``
- ``Galley``
- ``Margins``
- ``PageBuilder``

### Marks

- ``Mark``
- ``Text``
- ``Paragraph``
- ``Rect``
- ``Ellipse``
- ``Line``
- ``Polygon``

### Containers and layout

- ``VStack``
- ``HStack``
- ``ZStack``
- ``Spacer``
- ``FlexibleMark``
- ``FrameModifier``
- ``ProposedSize``
- ``Point``
- ``Size``
- ``VerticalAlignment``
- ``TextAlignment``

### Pagination and break control

- ``Galley``
- ``PaginationWarning``
- ``BreakControlling``
- ``BreakModifier``
- ``Mark/split(available:width:in:)``
- ``linesFitting(count:available:lineHeight:orphans:widows:)``

### Modifiers

- ``MarkModifier``
- ``ModifiedMark``
- ``AlignmentModifier``
- ``FillModifier``
- ``StrokeModifier``
- ``ForegroundColorModifier``
- ``FontModifier``
- ``LineHeightModifier``
- ``PositionModifier``
- ``PathTransparentModifier``

### Paths

- ``PathMark``
- ``PaintedPathMark``

### Type erasure and builders

- ``AnyMark``
- ``EmptyMark``
- ``MarkBuilder``

### Styling

- ``Color``
- ``Font``

### Engine

- ``Renderer``
- ``TextState``
- ``MeasureContext``
- ``PDFNumber``
- ``pdfEscape(_:)``

### Articles

- <doc:Architecture>