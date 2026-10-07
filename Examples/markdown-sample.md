# letterpress markdown

A **zero-dependency** markdown-to-pdf pipeline built on the `Letterpress`
declarative exporter. Write prose in markdown, get a typeset document.

## what it supports

- headings (`#` through `######`, plus `===` and `---` underlines)
- paragraphs with `**bold**`, `*italic*`, `***both***`, and `_underscored_`
- inline `` `code spans` `` and fenced code blocks with an info word
- ordered (`1.`, `2)`) and unordered (`-`, `*`, `+`) lists, nested by indent
- blockquotes with a left rule
- thematic breaks (`---`, `***`, `___`)
- `[links](https://example.com)` and `![alt text](image.png)`

## a table, eventually

| feature | status |
| --- | --- |
| tables | not yet |
| footnotes | not yet |

> Note — tables and footnotes are deliberately out of scope for now. Everything
> above rides on the same hand-set pdf writer: no engine, no cmark, no C.

### code

```swift
let document = MarkdownDocument(parsing: source)
let bytes = document.render(style: .standard)
```

1. parse the markdown into a block model
2. compose each block into a `Mark`
3. hand the marks to a `Galley` and let it paginate

---

Fin.