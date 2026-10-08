# the two-pass engine

why letterpress measures before it draws, and what that buys you.

## one tree, walked twice

every `Mark` answers two questions: how much space do you want, and how do you
draw yourself. those are `sizeThatFits(_:in:)` and `write(to:)`, and the engine
never calls one without a plan to call the other.

measurement runs top-down. a `ProposedSize` is handed to the root, each
container measures its children under a derived proposal, and the returned
`Size` bubbles back up. drawing then runs down the same tree with the geometry
that measurement resolved.

the payoff is that the two phases cannot disagree. a `Paragraph` wraps at the
width it was measured at because the wrap width is produced by the same call
that reported the paragraph's height. a `.frame(maxWidth:)` re-wraps text
because the frame threads its resolved box into the child's proposal.

## proposals, not constraints

`ProposedSize` carries an optional width and height. `nil` on an axis means
*no constraint*: use your ideal size. this is what makes a stack hug its
content by default and only flex when something finite is proposed.

finite space is the trigger for distribution. `FlexibleMark` marks a child that
can absorb leftover main-axis space — `Spacer` is the simple case — and a stack
with a finite proposal splits the remainder equally among its flex children.
without a finite proposal, or without flex children, the stack hugs and any
overflow is visible and legal.

containers place their children, so a child must not carry its own `.at`; the
container is positioned, and everything inside flows.

## paint composition and paths

pdf has no paint operator that leaves a path intact. `f` and `S` consume the
path they paint, so `.fill(...).stroke(...)` cannot naively draw twice.

letterpress solves this by giving paths a way to restate themselves. a
`PathMark` can draw its path and can also state that path on demand through
`writePath(to:)`; when a second paint follows a first, the outer paint asks for
the geometry again rather than relying on it still being current. a
`PathTransparentModifier` is a modifier that paints without moving the geometry
it wraps, which is what makes a chain of paints compose.

this is also why the paint helpers live on `PathMark` and not on `Mark`. a text
run has no path to fill, so `Text("x").fill(.red)` is a compile error rather
than a quiet no-op.

## modifiers preserve types

a modifier returns a new type rather than mutating in place. `.font(...)`
applied to a `Text` yields a `ModifiedMark<Text, FontModifier>`, and the next
modifier wraps that. the compiler keeps the whole chain in the type, so nothing
is boxed and every modifier is a visible, inspectable layer.

type erasure is available when it is genuinely needed — a heterogeneous array
of marks is `[any Mark]`, and `AnyMark` boxes a single mark for storage outside
a builder. the erasure is explicit, never implicit.

## pagination

a `Galley` is unpaginated typeset material: a vertical stack measured at the
content box. when a `Galley` appears in a `PDFDocument`'s `PageBuilder`, it
expands into as many physical pages as the content needs. spacing never leaks
across a break, and each resulting page is an ordinary `PDFPage` — same
objects, same resources, same determinism.

breaking happens in two places. between siblings, always: a child that does not
fit opens the next page. and *inside* a child that offers to be continued —
`Mark.split(available:width:in:)` returns the piece that fits and the runover,
and the paginator carries the runover onto the next page. `Text`, `Paragraph`,
`RichText`, `CodeBlock`, and `VStack` implement it; the protocol's default
returns `nil`, which is exactly how a mark declares itself atomic.

the contract is guaranteed progress: an accepted split must be strictly smaller
than what it replaces, so the walk terminates. a conformer that ignores that is
caught by a step bound which then places the remainder rather than dropping it.

text breaks between wrapped lines under widow and orphan minima — two lines
each by default — so a break never strands a single line. `MarkModifier`
forwards `split`, which is why a split preserves the style its modifier
pushed: both pieces are re-wrapped in the same `ModifiedMark` the original
went through, so a split paragraph keeps its font, and a split quote keeps
its bar.

break policy is a modifier rather than a layout property. `.pageBreak()` starts
a fresh page before a mark; `.keepWithNext()` keeps a mark with the flow after
it, so a heading is never stranded at a page foot. the paginator reads both
through `BreakControlling`, which means the policy travels as data on the mark
instead of state a container has to be told about.

overflow is visible, never silent. a mark that cannot break and does not fit
takes its own page when that helps, and otherwise is drawn past the bottom edge
— never dropped — and recorded as a `PaginationWarning` returned from
`pagination()`. a document also always has at least one page: an empty flow, or
margins that consume the whole page, yield one blank `PDFPage` rather than a
zero-count tree that no reader will open.

`Galley.furniture` closes the loop. a closure of `(page, total) -> [any Mark]`
is drawn on every physical page after its flow, so page numbers, running heads,
and footers need nothing from the paginator beyond the number it already knows.