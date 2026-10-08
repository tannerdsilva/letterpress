# the markdown pipeline

source text to blocks to marks to pages.

## parse: text becomes a tree of values

`MarkdownParser.parse(_:)` returns a `MarkdownDocument`, which is just an
ordered list of `Block` values. the block model is small and closed: headings,
paragraphs, bullets, ordered lists, quotes, code, and rules. `Block` is
`indirect` because exactly two cases nest — a quote holds blocks and a list
item holds blocks.

inline markup does not become a tree. a run of text is flattened at parse time
into a list of `InlineRun`, each carrying an `InlineTraits` option set. nesting
like bold-inside-a-link is resolved into trait bits immediately, so the renderer
never walks a tree to decide a font.

`InlineTraits` is an option set rather than three booleans so a run's styling is
one value that composes (`bold | italic`) and compares cleanly.

## compose: blocks become marks

each block becomes one `Mark`, and that mark's measured height includes the
block's share of vertical rhythm. baking the spacing into the mark means the
galley can lay blocks out with a plain stack and never needs to know about
markdown.

inline runs are laid out word by word, using only the exporter's public
surface: each placed word becomes an ordinary text mark pinned with `.at`.
wrapping, alignment, and code spans all fall out of that, and the markdown
layer stays a pure consumer of the exporter — it adds no api of its own.

## paginate: one galley, n pages

the composed marks go into a single `Galley` sized to the page and margins.
the galley measures the body at the column width, packs it into the content
box, and materialises one physical page per bucket. a document of any length
therefore needs no manual page breaks.

long blocks are continued rather than clipped. `RichText` splits between laid
lines, a `CodeBlock` between source lines, a `Quote` by handing its body through
to the same split, and a list between its items — an item is one row, so a list
is never divided mid-item. text breaks honour widow and orphan minima, and
headings are composed with `.keepWithNext()` so one is never stranded alone at
the foot of a page.

the pipeline never fails silently. `MarkdownDocument.pagination()` returns the
physical pages alongside a `PaginationWarning` for each mark the content box
could not hold. the one shape the pipeline cannot divide is a single list item
taller than the whole column, or a lone line of text larger than the box; both
are drawn, reported, and surfaced by the CLI as a non-zero exit.