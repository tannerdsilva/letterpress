import Testing
@testable import Letterpress

/// a fixed-height mark so bucket arithmetic is exact.
private struct Rule: Mark {
	let height: Double

	func write(to renderer: inout Renderer) {
		renderer.append("0 0 10 \(PDFNumber(height)) re\n")
	}

	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: 10, height: height)
	}
}

/// the content stream of the 0-based physical page.
private func stream(_ document: PDFDocument, page: Int) -> String? {
	let parsed = ParsedPDF(bytes: document.render())!
	return parsed.contentStream(4 + 2 * page)
}

/// a galley on a 200x100 page with a 10pt margin: content box 180x80.
private func galley(_ spacing: Double = 0, @MarkBuilder content: () -> [any Mark]) -> PDFDocument {
	PDFDocument {
		Galley(.custom(width: 200, height: 100), margins: Margins(top: 10, leading: 10, bottom: 10, trailing: 10), spacing: spacing) {
			content()
		}
	}
}

@Suite struct GalleyTests {
	@Test("children bucket across pages by content-box height")
	func buckets() throws {
		let doc = galley(10) {
			Rule(height: 30)
			Rule(height: 30)
			Rule(height: 30)
		}
		#expect(doc.pages.count == 2)
		let page1 = try #require(stream(doc, page: 0))
		let page2 = try #require(stream(doc, page: 1))
		// page 1 holds two rules: starts flush, second after 30 + spacing.
		#expect(page1.contains("1 0 0 1 10 -10 cm"))
		#expect(page1.contains("1 0 0 1 10 -50 cm"))
		// page 2 starts flush at the box top — spacing never leaks across a break.
		#expect(page2.contains("1 0 0 1 10 -10 cm"))
		#expect(!page2.contains("1 0 0 1 10 -50 cm"))
	}

	@Test("an exact-fit child stays on the current page")
	func exactFitStays() {
		#expect(galley {
			Rule(height: 40)
			Rule(height: 40)
		}.pages.count == 1)
		#expect(galley {
			Rule(height: 40)
			Rule(height: 40)
			Rule(height: 40)
		}.pages.count == 2)
	}

	@Test("text marks paginate on their measured line heights")
	func textBuckets() {
		// helvetica 12 lines are 15pt tall; five fit in an 80pt box.
		let doc = galley {
			for _ in 0 ..< 6 {
				Text("a").font(.helvetica, size: 12)
			}
		}
		#expect(doc.pages.count == 2)
		#expect(stream(doc, page: 0)?.contains("(a) Tj") == true)
		#expect(stream(doc, page: 1)?.contains("(a) Tj") == true)
	}

	@Test("a child taller than the content box overflows its own page")
	func tallChildOverflows() throws {
		let doc = galley {
			Rule(height: 90)
			Rule(height: 30)
		}
		#expect(doc.pages.count == 2)
		let page1 = try #require(stream(doc, page: 0))
		let page2 = try #require(stream(doc, page: 1))
		#expect(page1.contains("90 re"))
		#expect(page2.contains("30 re"))
	}

	@Test("paragraphs wrap at the content-box width while paging")
	func columnWrap() throws {
		let doc = PDFDocument {
			Galley(.custom(width: 100, height: 100), margins: Margins(top: 10, leading: 10, bottom: 10, trailing: 10)) {
				Paragraph("aa aa aa aa aa aa aa").font(.helvetica, size: 12)
			}
		}
		#expect(doc.pages.count == 1)
		let s = try #require(stream(doc, page: 0))
		#expect(s.contains("(aa aa aa aa) Tj"))
		#expect(s.contains("(aa aa aa) Tj"))
	}

	@Test("an empty galley expands to no pages and stays orderable")
	func empty() {
		let document = PDFDocument {
			PDFPage(.a4) { Text("before").at(x: 10, y: 10) }
			Galley(.custom(width: 200, height: 100), margins: Margins(top: 10, leading: 10, bottom: 10, trailing: 10)) { }
			PDFPage(.a4) { Text("after").at(x: 10, y: 10) }
		}
		#expect(document.pages.count == 2)
	}

	@Test("background paints on every physical page")
	func backgroundEveryPage() throws {
		let doc = PDFDocument {
			Galley(.custom(width: 200, height: 100), margins: Margins(top: 10, leading: 10, bottom: 10, trailing: 10), spacing: 10) {
				Rule(height: 30)
				Rule(height: 30)
				Rule(height: 30)
			}
			.background(Color(hex: 0xF8FAFC))
		}
		let page1 = try #require(stream(doc, page: 0))
		let page2 = try #require(stream(doc, page: 1))
		#expect(page1.contains("0 0 200 100 re f"))
		#expect(page2.contains("0 0 200 100 re f"))
	}

	@Test("a nested stack moves whole when it cannot split usefully")
	func nestedAtomic() {
		// a nested stack of two 30pt rules is 66 tall (30 + 6 + 30). the stack
		// is breakable, but 14pt of remainder cannot take even its first rule,
		// so the stack moves whole rather than splitting to nothing.
		let one = galley(10) {
			VStack(spacing: 6) {
				Rule(height: 30)
				Rule(height: 30)
			}
		}
		#expect(one.pages.count == 1)

		let three = galley(10) {
			VStack(spacing: 6) {
				Rule(height: 30)
				Rule(height: 30)
			}
			VStack(spacing: 6) {
				Rule(height: 30)
				Rule(height: 30)
			}
			VStack(spacing: 6) {
				Rule(height: 30)
				Rule(height: 30)
			}
		}
		// the cursor tracks remaining space: 66; remaining 14 is smaller
		// than the next stack's 76, so each lands on its own page.
		#expect(three.pages.count == 3)
	}

	@Test("a galley's physical pages follow declared pages in order")
	func ordering() throws {
		let document = PDFDocument {
			PDFPage(.a4) { Text("fixed").at(x: 10, y: 10) }
			Galley(.custom(width: 200, height: 100), margins: Margins(top: 10, leading: 10, bottom: 10, trailing: 10)) {
				Rule(height: 30)
				Rule(height: 30)
				Rule(height: 30)
			}
		}
		#expect(document.pages.count == 3)
		#expect(stream(document, page: 0)?.contains("(fixed) Tj") == true)
		#expect(stream(document, page: 1)?.contains("1 0 0 1 10 -10 cm") == true)
	}

	@Test("flow pagination is deterministic")
	func deterministic() {
		func build() -> [UInt8] {
			galley(8) {
				Rule(height: 30)
				Paragraph("aa aa aa aa aa aa aa").font(.helvetica, size: 12).frame(maxWidth: 60)
				Rule(height: 30)
				Rule(height: 30)
				Rule(height: 30)
				Rule(height: 30)
			}
			.render()
		}
		#expect(build() == build())
		#expect(!build().isEmpty)
	}
}
