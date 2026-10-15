import LetterpressTestSupport
import Testing
@testable import Letterpress

// pagination coverage: the behaviour a long document depends on — a mark that
// does not fit continues on the next page, an unbreakable one is reported
// rather than silently clipped, and nothing is ever dropped.

/// a fixed-height mark so bucket arithmetic is exact.
private struct Bar: Mark {
	let height: Double

	func write(to renderer: inout Renderer) {
		renderer.append("0 0 10 \(PDFNumber(height)) re\n")
	}

	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: 10, height: height)
	}
}

/// a galley on a 200x100 page with a 10pt margin: content box 180x80.
private func galley(_ spacing: Double = 0, @MarkBuilder content: () -> [any Mark]) -> PDFDocument {
	PDFDocument {
		Galley(
			.custom(width: 200, height: 100),
			margins: Margins(top: 10, leading: 10, bottom: 10, trailing: 10),
			spacing: spacing
		) {
			content()
		}
	}
}

/// the same galley, expanded with its overflow report kept.
private func paginate(
	_ spacing: Double = 0, @MarkBuilder content: () -> [any Mark]
) -> (pages: [PDFPage], warnings: [PaginationWarning]) {
	Galley(
		.custom(width: 200, height: 100),
		margins: Margins(top: 10, leading: 10, bottom: 10, trailing: 10),
		spacing: spacing
	) {
		content()
	}
	.pagination()
}

/// `count` newline-joined lines, so a text mark's line count is exact.
private func lines(_ count: Int) -> String {
	(1 ... count).map { "l\($0)" }.joined(separator: "\n")
}

/// the content stream of the 0-based physical page.
private func stream(_ document: PDFDocument, page: Int) -> String? {
	let parsed = ParsedPDF(bytes: document.render())!
	return parsed.contentStream(4 + 2 * page)
}

/// every `(…) Tj` payload the given pages draw, joined by a single space.
///
/// `Paragraph` emits one operator per wrapped line, so joining the payloads
/// reconstitutes the text in reading order — which is what makes "no word was
/// lost" checkable.
private func drawnText(_ pages: [PDFPage]) -> String {
	let parsed = ParsedPDF(bytes: PDFDocument { pages }.render())!
	var result = ""
	for number in 4 ..< parsed.objectCount where number % 2 == 0 {
		guard let stream = parsed.contentStream(number) else { continue }
		for piece in stream.separated(by: "(").dropFirst() {
			guard let end = piece.firstRange(of: ") Tj") else { continue }
			result += piece[..<end.lowerBound] + " "
		}
	}
	return result
}

/// the `/BaseFont` of every font the given page's resource dictionary names.
private func pageFonts(_ document: PDFDocument, page: Int) -> String {
	let parsed = ParsedPDF(bytes: document.render())!
	let pageBody = parsed.objectBody(3 + 2 * page) ?? ""
	var result = ""
	for number in 1 ..< parsed.objectCount {
		guard let body = parsed.objectBody(number), body.contains("/Type /Font") else { continue }
		if pageBody.contains("/F1 \(number) 0 R") { result += body }
	}
	return result
}

@Suite struct PaginationTests {
	// MARK: continuing across pages

	@Test("a text mark taller than the content box continues on the next pages")
	func textContinues() throws {
		// helvetica 12 lines are 15pt tall; the 80pt box holds five.
		let doc = galley { Text(lines(12)).font(.helvetica, size: 12) }
		#expect(doc.pages.count == 3)
		let first = try #require(stream(doc, page: 0))
		#expect(first.contains("(l1) Tj"))
		#expect(first.contains("(l5) Tj"))
		#expect(!first.contains("(l6) Tj"))
		#expect(try #require(stream(doc, page: 2)).contains("(l12) Tj"))
	}

	@Test("a paragraph splits between wrapped lines and keeps every word")
	func paragraphContinues() {
		let words = (1 ... 60).map { "word\($0)" }.joined(separator: " ")
		let result = paginate { Paragraph(words).font(.helvetica, size: 12) }
		#expect(result.pages.count > 1)
		#expect(result.warnings.isEmpty)
		// every word is drawn exactly once, across however many pages.
		let tokens = drawnText(result.pages).split(separator: " ").map(String.init)
		#expect(tokens.count == 60)
		#expect(tokens.first == "word1")
		#expect(tokens.last == "word60")
	}

	@Test("a stack splits between its children")
	func stackSplits() throws {
		let doc = galley {
			VStack(spacing: 0) {
				Bar(height: 50)
				Bar(height: 50)
			}
		}
		#expect(doc.pages.count == 2)
		#expect(try #require(stream(doc, page: 0)).contains("0 0 10 50 re"))
		#expect(try #require(stream(doc, page: 1)).contains("0 0 10 50 re"))
	}

	@Test("a split keeps the font its modifier pushed")
	func splitKeepsStyle() throws {
		let doc = galley { Text(lines(12)).font(.courier, size: 12) }
		#expect(doc.pages.count == 3)
		// the second page draws in courier: the piece carried the font, so
		// the split was taken through the modifier rather than around it.
		#expect(pageFonts(doc, page: 1).contains("/Courier"))
	}

	// MARK: widow and orphan control

	@Test("a paragraph too short to satisfy the widow minimum moves whole")
	func widowsRespected() throws {
		// 65pt of content leaves room for exactly one line — one orphan line
		// would violate the two-line minimum, so the paragraph moves entire.
		let doc = galley {
			Bar(height: 65)
			Paragraph(lines(4)).font(.helvetica, size: 12)
		}
		#expect(doc.pages.count == 2)
		#expect(stream(doc, page: 0)?.contains("(l1) Tj") == false)
		#expect(stream(doc, page: 1)?.contains("(l1) Tj") == true)
	}

	// MARK: overflow is reported, never silent

	@Test("a mark that cannot break takes its own page and is reported")
	func atomicOverflowReported() {
		let result = paginate {
			Bar(height: 30)
			Bar(height: 90)
		}
		#expect(result.pages.count == 2)
		#expect(result.warnings.count == 1)
		#expect(result.warnings.first?.page == 2)
		#expect(result.warnings.first?.markIndex == 1)
		#expect(result.warnings.first?.overflow == 10)
	}

	@Test("two oversized marks are reported separately, one page each")
	func twoOversized() {
		let result = paginate {
			Bar(height: 30)
			Bar(height: 90)
			Bar(height: 95)
		}
		#expect(result.pages.count == 3)
		#expect(result.warnings.map(\.overflow) == [10, 15])
	}

	@Test("content that fits reports no warnings")
	func fitsClean() {
		#expect(paginate {
			Bar(height: 30)
			Bar(height: 30)
		}.warnings.isEmpty)
	}

	@Test("a warning names its page and its overflow")
	func warningDescription() {
		let warning = PaginationWarning(page: 3, markIndex: 7, overflow: 12.5)
		#expect(warning.description.contains("page 3"))
		#expect(warning.description.contains("child 7"))
		#expect(warning.description.contains("12.5pt"))
	}

	// MARK: break policy

	@Test("keepWithNext moves a heading that would be stranded")
	func keepWithNext() {
		let stranded = paginate {
			Bar(height: 60)
			Bar(height: 15).keepWithNext()
			Bar(height: 40)
		}
		#expect(stranded.pages.count == 2)
		#expect(stranded.warnings.isEmpty)

		let fine = paginate {
			Bar(height: 30)
			Bar(height: 15).keepWithNext()
			Bar(height: 30)
		}
		#expect(fine.pages.count == 1)
	}

	@Test("a forced page break starts the mark on a fresh page")
	func forcedBreak() throws {
		let doc = galley {
			Bar(height: 10)
			Bar(height: 10).pageBreak()
			Bar(height: 10)
		}
		#expect(doc.pages.count == 2)
		#expect(try #require(stream(doc, page: 0)).contains("0 0 10 10 re"))
		#expect(try #require(stream(doc, page: 1)).contains("0 0 10 10 re"))
	}

	@Test("a break on the flow's first child is a no-op")
	func leadingBreakIsNoop() {
		#expect(galley {
			Bar(height: 10).pageBreak()
			Bar(height: 10)
		}.pages.count == 1)
	}

	// MARK: furniture

	@Test("page furniture draws on every page with its number")
	func furniture() throws {
		let doc = PDFDocument {
			Galley(
				.custom(width: 200, height: 100),
				margins: Margins(top: 10, leading: 10, bottom: 10, trailing: 10),
				spacing: 10
			) {
				Bar(height: 30)
				Bar(height: 30)
				Bar(height: 30)
			}
			.furniture { page, total in
				[Text("\(page)/\(total)").font(.helvetica, size: 8).at(x: 150, y: 90)]
			}
		}
		#expect(doc.pages.count == 2)
		#expect(try #require(stream(doc, page: 0)).contains("(1/2) Tj"))
		#expect(try #require(stream(doc, page: 1)).contains("(2/2) Tj"))
	}

	// MARK: degenerate documents

	@Test("an empty document renders one blank page, not an invalid tree")
	func emptyDocument() throws {
		let doc = PDFDocument {}
		#expect(doc.pages.count == 1)
		let parsed = try #require(ParsedPDF(bytes: doc.render()))
		let pages = try #require(parsed.objectBody(2))
		#expect(pages.contains("/Count 1"))
		#expect(pages.contains("/Kids [ 3 0 R]"))
	}

	@Test("an empty galley contributes no pages")
	func emptyGalley() {
		#expect(PDFDocument {
			Galley(.custom(width: 200, height: 100), margins: .standard) { }
		}.pages.count == 1)
	}

	@Test("margins that leave no content box still render one page")
	func degenerateMargins() {
		let doc = PDFDocument {
			Galley(
				.custom(width: 100, height: 100),
				margins: Margins(top: 60, leading: 10, bottom: 60, trailing: 10)
			) {
				Bar(height: 10)
			}
		}
		#expect(doc.pages.count == 1)
	}

	@Test("negative spacing clamps to zero so flow content never overlaps")
	func negativeSpacing() throws {
		let galley = Galley(
			.custom(width: 200, height: 100),
			margins: Margins(top: 10, leading: 10, bottom: 10, trailing: 10),
			spacing: -20
		) {
			Bar(height: 30)
			Bar(height: 30)
		}
		#expect(galley.spacing == 0)
		let page = try #require(stream(PDFDocument { galley }, page: 0))
		// the second bar starts one full bar-height down, not overlapped.
		#expect(page.contains("1 0 0 1 10 -40 cm"))
		#expect(!page.contains("1 0 0 1 10 -20 cm"))
	}

	// MARK: determinism

	@Test("split pagination is deterministic")
	func deterministic() {
		func build() -> [UInt8] {
			galley {
				Bar(height: 30)
				Paragraph(lines(12)).font(.helvetica, size: 12)
				Bar(height: 30)
			}
			.render()
		}
		#expect(build() == build())
		#expect(!build().isEmpty)
	}

	// MARK: the shared line arithmetic

	@Test("linesFitting honours orphan, widow, and fit minima")
	func lineArithmetic() {
		// five 10pt lines fit in 50pt: the whole run fits, so no break.
		#expect(linesFitting(count: 5, available: 50, lineHeight: 10, orphans: 1, widows: 1) == nil)
		// room for two of six, and two lines may stay behind.
		#expect(linesFitting(count: 6, available: 25, lineHeight: 10, orphans: 2, widows: 2) == 2)
		// a single orphan line is forbidden.
		#expect(linesFitting(count: 6, available: 15, lineHeight: 10, orphans: 2, widows: 2) == nil)
		// room for two of three, but taking two would strand a lone widow
		// line, so only one line goes.
		#expect(linesFitting(count: 3, available: 20, lineHeight: 10, orphans: 1, widows: 2) == 1)
		// a two-line run can never break: one line would be a widow.
		#expect(linesFitting(count: 2, available: 10, lineHeight: 10, orphans: 1, widows: 2) == nil)
		// a one-line run never breaks.
		#expect(linesFitting(count: 1, available: 10, lineHeight: 10, orphans: 1, widows: 1) == nil)
		// no line fits at all.
		#expect(linesFitting(count: 4, available: 5, lineHeight: 10, orphans: 1, widows: 1) == nil)
	}
}