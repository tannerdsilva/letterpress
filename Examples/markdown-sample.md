# letterpress markdown

A **zero-dependency** markdown-to-pdf pipeline built on the `Letterpress`
declarative exporter. Write prose in markdown, get a typeset document.

## what it supports

- headings (`#` through `######`, plus `===` and `---` underlines)
- paragraphs with `**bold**`, `*italic*`, `***both***`, and `_underscored_`
- inline `` `code spans` `` and fenced code blocks with an info word
- ordered (`1.`, `2)`) and unordered (`-`, `*`, `+`) lists, nested by indent
- pipe tables with per-column alignment
- blockquotes, thematic breaks, `[links](https://example.com)`, and images

### nested lists

- a list item may hold
  - a nested list
  - or a second block
- and the marker gutter stays put

## tables

| feature | status | notes |
| :--- | :---: | ---: |
| tables | supported | `\|` escapes, code spans, alignment |
| footnotes | not yet | out of scope |
| raw html | not yet | deliberately out of scope |

> A quote sets in the muted ink behind an accent bar — the same restrained
> palette the section rules, list markers and code panels use.

#### four levels deep

Body copy sits at the working size on a generous leading, measured to a
column that keeps a line near the comfortable reading range.

##### small caps label

Weights and colours carry the hierarchy from here down.

## code

```swift
let document = MarkdownDocument(parsing: source)
let bytes = document.render(style: .standard)
```

1. parse the markdown into a block model
2. compose each block into a `Mark`
3. hand the marks to a `Galley` and let it paginate

---

Fin.