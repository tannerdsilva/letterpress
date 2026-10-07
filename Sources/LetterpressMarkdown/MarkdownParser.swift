// the parsing seam: the one protocol a markdown front-end conforms to.

// MARK: - MarkdownParser

/// turns markdown source text into a `MarkdownDocument`.
///
/// the protocol exists so the parser is a swappable strategy: the shipped
/// `BasicMarkdownParser` handles a focused subset, and a heavier conformer
/// (say, one backed by a full CommonMark implementation) can be dropped in
/// without the renderer or the CLI changing a line.
public protocol MarkdownParser: Sendable {
	/// parse `source` into a document.
	func parse(_ source: String) -> MarkdownDocument
}