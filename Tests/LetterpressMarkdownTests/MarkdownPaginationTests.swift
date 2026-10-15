import Testing
import Letterpress
import LetterpressMarkdown
import LetterpressTestSupport

// pagination coverage for the markdown pipeline: a document longer than a page
// must keep every word, and must not need a warning to say so.

/// `count` numbered words, so any word can be searched for in the artifact.
private func numbered(_ count: Int) -> String {
	(1 ... count).map { "word\($0)" }.joined(separator: " ")
}

/// the rendered pages as text — every stream concatenated, since a word may
/// land on any page.
private func rendered(_ pages: [PDFPage]) -> String {
	String(decoding: PDFDocument { pages }.render(), as: UTF8.self)
}

@Suite struct MarkdownPaginationTests {
	@Test("every word of a paragraph longer than a page survives the breaks")
	func paragraphWordsRecoverable() {
		let source = numbered(1500)
		let result = MarkdownDocument(parsing: source).pagination()
		#expect(result.pages.count > 1)
		#expect(result.warnings.isEmpty)
		let text = rendered(result.pages)
		let missing = (1 ... 1500).filter { !text.contains("(word\($0)) Tj") }
		#expect(missing.isEmpty)
	}

	@Test("a code block longer than a page splits and keeps every line")
	func codeBlockSplits() {
		let body = (1 ... 120).map { "let value\($0) = \($0)" }.joined(separator: "\n")
		let result = MarkdownDocument(parsing: "```swift\n\(body)\n```").pagination()
		#expect(result.pages.count > 1)
		#expect(result.warnings.isEmpty)
		let text = rendered(result.pages)
		#expect(text.contains("(let value1 = 1) Tj"))
		#expect(text.contains("(let value60 = 60) Tj"))
		#expect(text.contains("(let value120 = 120) Tj"))
	}

	@Test("a blockquote longer than a page splits and keeps its bar")
	func quoteSplits() {
		let result = MarkdownDocument(parsing: "> " + numbered(1500)).pagination()
		#expect(result.pages.count > 1)
		#expect(result.warnings.isEmpty)
		// the bar is a filled rectangle: every page of the quote paints one.
		let bars = rendered(result.pages).separated(by: "re\n").count - 1
		#expect(bars >= result.pages.count)
	}

	@Test("a long mixed document paginates with no overflow at all")
	func mixedDocumentClean() {
		let body = numbered(120)
		let source = (1 ... 8).map { index in
			"""
			## Section \(index)

			\(body)

			- item one
			- item two

			> \(body)

			```
			let x\(index) = \(index)
			```
			"""
		}.joined(separator: "\n\n")
		let result = MarkdownDocument(parsing: source).pagination()
		#expect(result.pages.count > 4)
		#expect(result.warnings.isEmpty)
	}

	@Test("an empty document renders one blank page, not an invalid tree")
	func emptyDocument() {
		let text = String(decoding: MarkdownDocument(parsing: "").render(), as: UTF8.self)
		#expect(text.hasPrefix("%PDF-1.7"))
		#expect(text.hasSuffix("%%EOF\n"))
		// one real page, not a zero-count tree that no reader will open.
		#expect(text.contains("/Count 1"))
		#expect(!text.contains("/Kids []"))
	}

	@Test("a single list item taller than the column is reported, not dropped")
	func oversizedListItemReported() {
		let source = "- " + numbered(1200)
		let result = MarkdownDocument(parsing: source).pagination()
		#expect(!result.warnings.isEmpty)
		#expect(result.warnings.allSatisfy { $0.overflow > 0 })
	}
}