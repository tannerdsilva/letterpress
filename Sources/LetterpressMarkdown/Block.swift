// the block layer: the document model a markdown source parses into.

// MARK: - ListItem

/// one item of a bullet or ordered list: an ordered sequence of blocks.
///
/// an item holds blocks, not a bare string, so a list entry can carry a
/// paragraph, a nested list, a fenced code block, or a blockquote.
public struct ListItem: Sendable, Hashable {
	/// the blocks that make up this item (a paragraph, a nested list, ...).
	public var blocks: [Block]

	/// create an item from explicit blocks.
	public init(blocks: [Block]) {
		self.blocks = blocks
	}

	/// an item holding a single paragraph of inline runs.
	public init(_ runs: [InlineRun]) {
		self.blocks = [.paragraph(runs)]
	}
}

// MARK: - Block

/// one block-level unit of a markdown document.
///
/// `indirect` because a blockquote holds blocks and a list item holds blocks —
/// the two places markdown nests.
public indirect enum Block: Sendable, Hashable {
	/// an `# atx` or setext heading; `level` is 1...6.
	case heading(level: Int, [InlineRun])
	/// a flush paragraph of inline runs.
	case paragraph([InlineRun])
	/// an unordered list (`-`, `*`, `+`).
	case bullets([ListItem])
	/// an ordered list; `start` is the number of its first item.
	case ordered(start: Int, [ListItem])
	/// a blockquote (`> ...`), holding the quoted blocks.
	case quote([Block])
	/// a fenced code block (``` or ~~~); `language` is the info word.
	case code(language: String?, text: String)
	/// a thematic break (`---`, `***`, `___`).
	case rule
}

// MARK: - MarkdownDocument

/// a parsed markdown document: an ordered list of top-level blocks.
public struct MarkdownDocument: Sendable, Hashable {
	/// the document's top-level blocks.
	public var blocks: [Block]

	/// create a document from explicit blocks.
	public init(blocks: [Block]) {
		self.blocks = blocks
	}

	/// parse `source` into a document using `parser`.
	public init(parsing source: String, with parser: some MarkdownParser = BasicMarkdownParser()) {
		self = parser.parse(source)
	}

	/// the document's title: the text of its first level-1 heading, if any.
	public var title: String? {
		for block in blocks {
			if case .heading(let level, let runs) = block, level == 1 {
				return runs.map(\.text).joined()
			}
		}
		return nil
	}
}