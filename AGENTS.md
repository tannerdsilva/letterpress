# AGENTS.md — letterpress

operational guidance for autonomous agents. this is not api reference — the
inline `///` comments and the docc catalogs are. this file records the laws
that are not visible in any one file, the things that were removed on purpose,
and the pitfalls that cost real cycles.

## 1. what this repository is

a declarative, dependency-free pdf exporter for swift, plus a markdown layer
and a cli on top of it.

- `Letterpress` — the exporter. a `Mark` protocol, a result-builder dsl, value
  type primitives, a two-pass measure/write engine, and a hand-written pdf
  object model (writer, winansi encoder, base-14 afm metrics).
- `LetterpressMarkdown` — a markdown subset parsed into blocks, composed into
  marks, and flowed through one galley. a pure consumer of the exporter: it
  adds no api to `Letterpress`.
- `letterpress-md` — the cli. reads markdown (or stdin), writes a pdf, prints a
  compact json summary.
- `LetterpressExample` — the demo document, rendered to `letterpress-example.pdf`.

## 2. the laws of the land

these are load-bearing. a change that breaks one of them is wrong even if every
test passes.

**no Foundation, anywhere.** not in the libraries, not in the executables, not
in the tests. the `Letterpress` module imports *nothing at all* — verify with
`grep -rn "^import" Sources/Letterpress/` (only the docc markdown should
appear). file i/o goes through `swift-system`; the test harness reaches the c
library directly for the three things `SystemPackage` does not cover
(`posix_spawn`, `unlink`, `TMPDIR`).

**no dependencies in the libraries.** `Letterpress` and `LetterpressMarkdown`
declare none. `letterpress-md` takes `swift-argument-parser` and `swift-system`;
the example takes `swift-system`; the test harness takes `swift-system`. a new
dependency in the core needs to be argued for as if it were a breaking change,
because it is one.

**the exporter never touches the filesystem.** `PDFDocument.render()` returns
`[UInt8]` and that is the whole contract. there is no `write(to:)`, no path
handling, no temp file. writing is the caller's job — see the `WritingBytes`
article. this is what keeps the core portable and byte-deterministic.

**overflow is visible, never silent.** a mark the content box cannot hold is
drawn, never dropped, and reported as a `PaginationWarning`; the cli prints it
and exits non-zero (writing the artifact either way). do not "fix" an overflow
by clipping.

**measure and render cannot disagree.** every `Mark` answers
`sizeThatFits(_:in:)` and `write(to:)` as pure functions of the same inputs.
a change that special-cases one side of that seam is a bug waiting.

**byte determinism.** the same document renders the same bytes on every run, on
every platform, under every locale. `PDFNumber` formats with integer arithmetic
for exactly this reason — never reach for a locale-aware formatter.

## 3. the architecture map

```
Sources/Letterpress/            the exporter — no deps, no imports
  Mark.swift · Marks.swift      the protocol, and Text/Paragraph/Rect/…
  Layout.swift · Geometry.swift HStack/VStack/ZStack, Spacer, ProposedSize
  Modifiers.swift               MarkModifier, ModifiedMark<Content, M>
  Galley.swift                  pagination, break policy, PaginationWarning
  Renderer.swift · PDFWriter.swift · PDFNumber.swift · PDFString.swift
  Font.swift · Color.swift      base-14 afm metrics, device-rgb
  PDFDocument.swift             PDFDocument / PDFPage / PageSize / builders
Sources/LetterpressMarkdown/    the markdown layer — depends on Letterpress only
  BasicMarkdownParser.swift     blocks: headings, lists, quotes, code, tables
  InlineParser.swift · Inline.swift   inline runs, InlineTraits
  MarkdownLayout.swift          blocks → marks → one galley
  MarkdownStyle.swift           the whole theme, one value type
  Marks.swift                   the block-level marks (quotes, code, tables)
Sources/LetterpressMarkdownCLI/ the cli — ArgumentParser + SystemPackage
Sources/LetterpressExample/     the demo — SystemPackage
Tests/Support/                  LetterpressTestSupport: Spawn, Scratch, separated(by:)
```

`Tests/Support` is a real target (not a test target) because three test targets
need the same harness and test targets cannot import each other. it is not a
product, so it ships nowhere.

## 4. build, test, verify

```bash
swift build                 # products, no tests
swift build --build-tests   # tests compile
swift test                  # 222 tests, 26 suites
```

verify the artifacts, not just the suite — the suite validates the library
against its own model of pdf:

```bash
swift run LetterpressExample                                  # letterpress-example.pdf
swift run letterpress-md Examples/markdown-sample.md -o sample.pdf
pdfinfo letterpress-example.pdf
pdftotext sample.pdf - | head
pdftoppm -png -r 100 sample.pdf /tmp/page && open /tmp/page-1.png
```

determinism is a property you can check in one line — render twice, compare:

```bash
swift run letterpress-md Examples/markdown-sample.md -o /tmp/a.pdf
swift run letterpress-md Examples/markdown-sample.md -o /tmp/b.pdf
shasum -a 256 /tmp/a.pdf /tmp/b.pdf
```

the package builds and tests clean on macOS (arm64) and Linux (x86_64) with
Swift 6.4. cross-platform claims get verified on both, never assumed.

## 5. the two suites that matter most

`independent parser check` and `markdown visual check` drive **poppler** as a
subprocess and measure where the glyphs actually landed, because a
self-referential test can only confirm the library agrees with itself. both
skip visibly where `pdftotext` is absent — a skip is not a pass, and adding a
test that only exercises the library's own arithmetic adds little.

the harness that drives them is `Tests/Support/Support.swift`. it is
foundation-free on purpose and uses `posix_spawn` with stdout/stderr redirected
to files rather than pipes (a child writing more than a pipe buffer would
deadlock against a parent that is not draining it).

`LetterpressPublicAPITests` deliberately does **not** use `@testable`: it
implements a `Mark` and a `MarkModifier` from outside the module, so its
compilation *is* the assertion that the public surface is sufficient. if it
stops compiling, the fix is to open the api, never to add `@testable`.

## 6. docs

inline `///` on every public symbol, plus a docc catalog per module with a
curated landing page (every public type is named in its Topics) and articles.

build them with `docc` directly — the package takes no `swift-docc-plugin`:

```bash
sg=$(mktemp -d)
swift build --target Letterpress \
  -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc "$sg"
xcrun docc convert Sources/Letterpress/Letterpress.docc \
  --additional-symbol-graph-dir "$sg" -o /tmp/Letterpress.doccarchive \
  --warnings-as-errors
```

`LetterpressMarkdown` needs one more step, and this is the step that is easy to
get wrong: a `--target` build emits a symbol graph for **everything that target
depends on**, and `docc` refuses inputs describing more than one module. so a
per-module directory is not enough on its own — it has to hold that module's
graph and nothing else:

```bash
sg=$(mktemp -d)
swift build --target LetterpressMarkdown \
  -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc "$sg"
rm "$sg/Letterpress.symbols.json"   # emitted as a dependency of the target
xcrun docc convert Sources/LetterpressMarkdown/LetterpressMarkdown.docc \
  --additional-symbol-graph-dir "$sg" -o /tmp/LetterpressMarkdown.doccarchive \
  --warnings-as-errors
```

both must convert with zero warnings. an api change means updating the inline
docs, the landing page Topics if a type was added, and the README table.

## 7. conventions

- **comments are lowercase prose**, in `///` docs and `//` notes alike.
  backticked identifiers, quoted literals, CLI flags and acronyms keep their
  case. no sentence capitalization.
- **tabs**, four-space runs converted to one tab.
- **Swift Testing** (`import Testing`, `@Test`, `#expect`) for all tests. one
  suite per file. `#require` for anything a later line dereferences.
- **no `fatalError`, no `try!`, no `as!`** in shipped code. a macro would emit
  a diagnostic; this tree has no macros, so an impossible state is a
  `precondition` with a message that names the invariant.
- cli errors print as `Error: <message>` on stderr with exit 1; usage errors
  and unknown flags exit 64 via `swift-argument-parser`.

## 8. removed — do not resurrect

- **`PDFDocument.write(to url: URL)`** — removed deliberately. the exporter has
  no file api; writing lives in the callers. it was the *only* reason the core
  needed Foundation, and `PDFNumber`'s `pow` was the other; both are gone.
- **`import Foundation` anywhere in this tree** — removed from all four source
  targets and all four test targets. if a change seems to need it, that change
  belongs in an executable target or belongs to `swift-system`.
- **`components(separatedBy:)` / `range(of:)` in tests** — Foundation spellings.
  the standard library's `firstRange(of:)` and `ranges(of:)` replaced them, and
  the multi-character "split keeping empty pieces" shape lives in
  `Tests/Support/Scanning.swift` as `separated(by:)`.
- **a `dlopen`-able `swift-docc-plugin` dependency** — the recipe in §6 is the
  supported path.

## 9. pitfalls (each cost real cycles)

- **docc multi-module inputs.** see §6. "one directory per module" is not
  enough; filter the dependency's `.symbols.json` out.
- **`posix_spawn_file_actions_t` is a struct on Glibc and a pointer on
  Darwin.** `var actions: posix_spawn_file_actions_t?` compiles on macOS and
  *fails* on Linux with a pointee mismatch, so the harness carries the tree's
  only platform-conditional code for exactly this — two
  `#if canImport(Darwin)` blocks in one file, one for the module name and one
  for this local. `baseAddress` of an
  `argv`/`envp` array is optional on Linux as well — unwrap it rather than
  passing it straight through.
- **`WIFEXITED`/`WEXITSTATUS` are not importable.** the low seven bits of the
  wait status are zero for a normal exit: `(status & 0x7f) == 0 ? (status >> 8) & 0xff : status`.
  reporting the raw status for a signalled child keeps a crash from reading as
  success.
- **macOS sets `TMPDIR` with a trailing separator**, which `FilePath` reads as
  a trailing empty component. trim it before appending.
- **`FilePath` has no `stringValue`.** use `.description` for display and
  `withPlatformString { }` when a c string is needed.
- **`String(validatingUTF8:)` is deprecated** in the 6.4 toolchain — the
  spelling is `String(validatingCString:)`.
- **`.frame(maxWidth:)` on a `Text` does not wrap.** a long line is a
  `Paragraph`; a bare `Text` runs past the page trim and the page clips it
  silently. this is exactly how the example shipped clipped text once.
- **`closeAfter` returns the body's value**, so `try file.closeAfter { try
  file.writeAll(bytes) }` warns unless the result is discarded.

## 10. status

v1 surface, feature-complete for the documented scope. known limits are
enumerated in the README's `limitations (v1, by design)` section and are
deliberate, not gaps: base-14 fonts only (no embedding, no unicode beyond
winansi), no images, no flate compression, no links or form fields, no kerning,
and an unbreakable mark taller than the content box still overflows visibly.