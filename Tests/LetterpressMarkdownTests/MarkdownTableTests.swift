import Letterpress
import LetterpressMarkdown
import LetterpressTestSupport
import Testing

// table coverage: GFM pipe-table parsing (delimiter, alignment, escapes, code
// spans, ragged rows) and the rendered/paginated artifact.

@Suite struct MarkdownTableTests {
	// MARK: parsing

	@Test("a pipe table parses into a header, alignments, and body rows")
	func parses() {
		let document = MarkdownDocument(parsing: """
		| Name | Role | Score |
		| --- | --- | ---: |
		| Ada | Engineer | 10 |
		| Grace | Admiral | 9 |
		""")
		guard case .table(let table) = document.blocks.first else { Issue.record("not a table"); return }
		#expect(table.header.count == 3)
		#expect(table.header.map { $0.map(\.text).joined() } == ["Name", "Role", "Score"])
		#expect(table.alignments == [.leading, .leading, .trailing])
		#expect(table.rows.count == 2)
		#expect(table.rows[0].map { $0.map(\.text).joined() } == ["Ada", "Engineer", "10"])
		#expect(table.columnCount == 3)
	}

	@Test("colon markers choose column alignment")
	func alignment() {
		let document = MarkdownDocument(parsing: """
		| a | b | c | d |
		| --- | :--- | ---: | :---: |
		""")
		guard case .table(let table) = document.blocks.first else { Issue.record("not a table"); return }
		#expect(table.alignments == [.leading, .leading, .trailing, .center])
	}

	@Test("leading and trailing pipes are optional")
	func optionalPipes() {
		let document = MarkdownDocument(parsing: """
		a | b
		--- | ---
		1 | 2
		""")
		guard case .table(let table) = document.blocks.first else { Issue.record("not a table"); return }
		#expect(table.header.count == 2)
		#expect(table.rows.count == 1)
	}

	@Test("a pipe table needs a delimiter row — otherwise it is a paragraph")
	func delimiterRequired() {
		let document = MarkdownDocument(parsing: "a | b\nc | d")
		#expect(document.blocks.count == 1)
		guard case .paragraph = document.blocks.first else { Issue.record("a pipe line without a delimiter is not a table"); return }
	}

	@Test("a ragged body row is padded or trimmed to the header width")
	func raggedRows() {
		let document = MarkdownDocument(parsing: """
		| a | b | c |
		| --- | --- | --- |
		| 1 |
		| 1 | 2 | 3 | 4 |
		""")
		guard case .table(let table) = document.blocks.first else { Issue.record("not a table"); return }
		#expect(table.rows[0].count == 3)
		#expect(table.rows[0][1].isEmpty)
		#expect(table.rows[1].count == 3)
	}

	@Test("an escaped pipe stays in the cell, and a pipe in a code span does not split")
	func escapesAndCode() {
		let document = MarkdownDocument(parsing: #"""
		| x | y |
		| --- | --- |
		| a \| b | `c|d` |
		"""#)
		guard case .table(let table) = document.blocks.first else { Issue.record("not a table"); return }
		let firstCell = table.rows[0][0].map(\.text).joined()
		#expect(firstCell == "a | b")
		let secondCell = table.rows[0][1]
		#expect(secondCell.map(\.text).joined() == "c|d")
		#expect(secondCell.contains { $0.traits.contains(.code) })
	}

	@Test("inline emphasis inside a cell parses like everywhere else")
	func inlineInCells() {
		let document = MarkdownDocument(parsing: """
		| k | v |
		| --- | --- |
		| **bold** | *em* |
		""")
		guard case .table(let table) = document.blocks.first else { Issue.record("not a table"); return }
		#expect(table.rows[0][0].contains { $0.text == "bold" && $0.traits.contains(.bold) })
		#expect(table.rows[0][1].contains { $0.text == "em" && $0.traits.contains(.italic) })
	}

	@Test("a table is separated by a blank line from a following paragraph")
	func followedByParagraph() {
		let document = MarkdownDocument(parsing: """
		| a | b |
		| --- | --- |
		| 1 | 2 |

		after the table
		""")
		#expect(document.blocks.count == 2)
		guard case .table = document.blocks[0] else { Issue.record("first block is not a table"); return }
		guard case .paragraph = document.blocks[1] else { Issue.record("second block is not a paragraph"); return }
	}

	// MARK: rendering

	@Test("a table renders a tinted header band, a bold header, and rules")
	func renders() {
		let document = MarkdownDocument(parsing: """
		| Name | Role |
		| --- | --- |
		| Ada | Engineer |
		""")
		let text = String(decoding: document.render(), as: UTF8.self)
		// header cells render bold in the body typeface; body cells in it too.
		let body = MarkdownStyle.standard.typeface
		#expect(text.contains("/BaseFont /\(body.font(bold: true, italic: false).baseName)"))
		#expect(text.contains("(Name) Tj"))
		#expect(text.contains("(Ada) Tj"))
		#expect(text.contains("(Engineer) Tj"))
		// the header band is a filled rectangle, and rules are stroked.
		#expect(text.contains("re\nf"))
		#expect(text.contains("S\n"))
	}

	@Test("deterministic rendering with a table")
	func deterministic() {
		let document = MarkdownDocument(parsing: "| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n")
		#expect(document.render() == document.render())
	}

	// MARK: pagination

	/// `count` single-word body cells, so any cell is searchable in the artifact.
	private func numberedTable(_ count: Int) -> String {
		let body = (1 ... count).map { "| v\($0) | row \($0) |" }.joined(separator: "\n")
		return "| key | value |\n| --- | --- |\n\(body)\n"
	}

	private func rendered(_ pages: [PDFPage]) -> String {
		String(decoding: PDFDocument { pages }.render(), as: UTF8.self)
	}

	@Test("a table taller than a page breaks across pages and keeps every cell")
	func tableSplits() {
		let result = MarkdownDocument(parsing: numberedTable(200)).pagination()
		#expect(result.pages.count > 1)
		#expect(result.warnings.isEmpty)
		let text = rendered(result.pages)
		let missing = (1 ... 200).filter { !text.contains("(v\($0)) Tj") }
		#expect(missing.isEmpty)
	}

	@Test("the header repeats on every page a table spans")
	func headerRepeats() {
		let result = MarkdownDocument(parsing: numberedTable(200)).pagination()
		let text = rendered(result.pages)
		let headerMentions = text.separated(by: "(key) Tj").count - 1
		#expect(result.pages.count > 2)
		// one header per page the table occupies, so it repeats, never fewer.
		#expect(headerMentions >= result.pages.count)
	}

	@Test("a document ending in a table has no blank trailing page")
	func noBlankTrailingPage() {
		let result = MarkdownDocument(parsing: numberedTable(200)).pagination()
		let lastText = String(
			decoding: PDFDocument { [result.pages[result.pages.count - 1]] }.render(),
			as: UTF8.self)
		// the final page carries the last body cell, not just trailing rhythm.
		#expect(lastText.contains("(v200) Tj"))
	}

	@Test("a long document with tables paginates with no overflow at all")
	func mixedDocumentClean() {
		let source = (1 ... 6).map { index in
			"""
			## Section \(index)

			\(numberedTable(40))

			| left | center | right |
			| :--- | :---: | ---: |
			| a | b | c |
			"""
		}.joined(separator: "\n\n")
		let result = MarkdownDocument(parsing: source).pagination()
		#expect(result.pages.count > 3)
		#expect(result.warnings.isEmpty)
	}

	@Test("a single row taller than a page breaks inside itself and loses no cell text")
	func tallRowSplits() {
		// one body cell far taller than a page. there is no row boundary to
		// break on, so the row has to break within itself or its tail is
		// clipped off the page and never drawn again.
		let cell = Array(repeating: "overflowing", count: 400).joined(separator: " ")
		let source = "| key | value |\n| --- | --- |\n| \(cell) | tail |\n"
		let result = MarkdownDocument(parsing: source).pagination()
		#expect(result.warnings.isEmpty, "the tall row still overflows: \(result.warnings)")
		#expect(result.pages.count > 2, "the tall row did not span several pages")
		let text = rendered(result.pages)
		// every word of the tall cell survives the break, none is dropped.
		let kept = text.separated(by: "(overflowing) Tj").count - 1
		#expect(kept == 400, "the break lost \(400 - kept) words of the tall row")
		// and the header rides along on each page the row reaches.
		let headers = text.separated(by: "(key) Tj").count - 1
		#expect(headers == result.pages.count, "the header did not repeat on all \(result.pages.count) pages")
	}

	@Test("a table's columns do not depend on where it breaks")
	func splitKeepsColumnGeometry() {
		// row one is short and row two is far taller than a page. the same table
		// is set once on a page too short to hold it and once on a page tall
		// enough that it never breaks. the columns must land identically, because
		// a break is not a chance to re-lay the table — a piece that re-derived
		// its columns from whichever rows it held would shuffle them.
		let row = Array(repeating: "overflowing", count: 400).joined(separator: " ")
		let source = "| key | value |\n| --- | --- |\n| v1 | short |\n| v2 | \(row) |\n"
		let document = MarkdownDocument(parsing: source)

		var tall = MarkdownStyle.standard
		tall.pageSize = .custom(width: MarkdownStyle.standard.pageSize.size.width, height: 30_000)

		let split = document.pagination()
		let whole = document.pagination(style: tall)
		#expect(split.warnings.isEmpty)
		#expect(split.pages.count > 2, "the table did not break")
		#expect(whole.pages.count == 1, "the tall page still broke the table")

		// the x of the second column's header cell, read from the `Tm` placing it.
		func valueColumnOrigins(_ pages: [PDFPage]) -> Set<String> {
			var origins: Set<String> = []
			let lines = rendered(pages).separated(by: "\n")
			for (index, line) in lines.enumerated() where line == "(value) Tj" {
				guard index > 0 else { continue }
				let parts = lines[index - 1].separated(by: " ")
				// the line reads "1 0 0 1 <x> <y> Tm".
				guard parts.count == 7, parts[6] == "Tm" else { continue }
				origins.insert(parts[4])
			}
			return origins
		}
		let origins = valueColumnOrigins(split.pages)
		#expect(origins.count == 1, "the pieces disagreed on the second column's origin")
		#expect(origins == valueColumnOrigins(whole.pages), "breaking the table moved its columns")
	}

	// MARK: column sizing

	@Test("a narrow id column sets its whole id, never a broken one")
	func idColumnKeepsTokenWhole() {
		// the id column is the narrow one, and the wide cells push the table
		// past its column so the whole set is scaled down. a bare constant
		// floor leaves the id column a third of a point short of its own token,
		// and the wrap sets `T13` as `T1` / `3`.
		let source = """
		| # | Defect | Measured | Evidence |
		| --- | --- | --- | --- |
		| T13 | a defect description long enough that its single line passes the column cap | 9 | `STABILITY.md:98-104` |
		| T14 | another description, also long enough to keep the wide columns wide | 16 | `STABILITY.md:111-120` |
		"""
		let text = rendered(MarkdownDocument(parsing: source).pagination().pages)
		#expect(text.contains("(T13) Tj"))
		#expect(text.contains("(T14) Tj"))
		#expect(!text.contains("(T1) Tj"))
	}

	@Test("a struck run inside a table cell draws its rule too")
	func strikethroughInCell() {
		// a cell lays its own lines out. when it drew them through its own
		// loop rather than the shared emitter, a strike inside a cell parsed
		// but was never painted.
		let plain = rendered(MarkdownDocument(parsing: "| a |\n| --- |\n| gone |\n").pagination().pages)
		let struck = rendered(MarkdownDocument(parsing: "| a |\n| --- |\n| ~~gone~~ |\n").pagination().pages)
		#expect(struck.contains("(gone) Tj"))
		#expect(!struck.contains("(~"))
		let plainRects = plain.separated(by: " re\n").count
		let struckRects = struck.separated(by: " re\n").count
		#expect(struckRects == plainRects + 1)
	}

	@Test("a long identifier breaks on its own humps, never mid-word")
	func identifierBreaksAtHumps() {
		// four long paths force the column set wider than the measure, so each
		// cell is narrower than its own token and every one has to break. a
		// piece must start a word: snapping wherever the measure happened to
		// run out leaves `WebSocketProtocolFra` / `meEncoder.swift`.
		let source = """
		| WebSocketProtocolFrameEncoder.swift | SomeLongishPathName.swift | AnotherLongPathHere.swift | FourthLongPathName.swift |
		| --- | --- | --- | --- |
		| x | 1 | 2 | 3 |
		"""
		let text = rendered(MarkdownDocument(parsing: source).pagination().pages)

		// the paths really did break, or the fixture proves nothing.
		#expect(!text.contains("(WebSocketProtocolFrameEncoder.swift) Tj"))

		// every path piece on the page: word-like, so it carries a capital.
		let pieces = text.separated(by: "\n")
			.filter { $0.hasPrefix("(") && $0.hasSuffix(") Tj") }
			.map { String($0.dropFirst().dropLast(5)) }
			.filter { $0.contains(where: \.isUppercase) }
		#expect(!pieces.isEmpty)
		#expect(
			pieces.allSatisfy { $0.first?.isUppercase == true },
			"a piece broke mid-identifier: \(pieces)")
	}
}