import Testing
import Letterpress
import LetterpressMarkdown

// rendering coverage: the artifact's bytes — fonts, encoding declaration,
// pagination, determinism, and the cp1252 byte guard.

/// the rendered pdf as text. every non-ascii byte travels as a 7-bit octal
/// escape, so the document decodes as utf-8 cleanly.
private func pdfText(_ bytes: [UInt8]) -> String {
	String(decoding: bytes, as: UTF8.self)
}

@Suite struct MarkdownRenderTests {
	@Test("a document with every supported block renders to a page")
	func rendersAllBlocks() {
		let source = """
		# Title

		A paragraph with **bold**, *italic*, and `code`.

		- one
		- two

		1. first
		2. second

		> a quotation

		```swift
		let x = 1
		```

		---
		"""
		let document = MarkdownDocument(parsing: source)
		let pdf = document.pdfDocument()
		#expect(pdf.pages.count >= 1)
		let bytes = pdf.render()
		#expect(!bytes.isEmpty)
		let text = pdfText(bytes)
		#expect(text.hasPrefix("%PDF-1.7"))
		#expect(text.hasSuffix("%%EOF\n"))
	}

	@Test("a heading renders bold in the heading colour and body text in the body font")
	func fontsAreSelected() {
		let document = MarkdownDocument(parsing: "# Heading\n\nplain body text")
		let text = pdfText(document.render())
		#expect(text.contains("/BaseFont /Helvetica-Bold"))
		#expect(text.contains("/BaseFont /Helvetica"))
		#expect(text.contains("(Heading) Tj"))
	}

	@Test("bold and italic runs pick distinct faces")
	func inlineFaces() {
		let document = MarkdownDocument(parsing: "plain **bold** *italic* `code`")
		let text = pdfText(document.render())
		#expect(text.contains("/BaseFont /Helvetica-Bold"))
		#expect(text.contains("/BaseFont /Helvetica-Oblique"))
		#expect(text.contains("/BaseFont /Courier"))
	}

	@Test("code blocks draw a tinted panel behind monospaced lines")
	func codePanel() {
		let document = MarkdownDocument(parsing: "```\nhello code\n```")
		let text = pdfText(document.render())
		#expect(text.contains("/BaseFont /Courier"))
		#expect(text.contains("(hello code) Tj"))
		// a filled rectangle stands in for the panel.
		#expect(text.contains("re\nf"))
	}

	@Test("every font object declares WinAnsiEncoding")
	func winAnsiDeclared() {
		let document = MarkdownDocument(parsing: "# hi\n\ntext with “curly quotes” and an em—dash")
		let text = pdfText(document.render())
		let fontObjects = text.components(separatedBy: "/Type /Font").count - 1
		let declared = text.components(separatedBy: "/Encoding /WinAnsiEncoding").count - 1
		#expect(fontObjects > 0)
		#expect(fontObjects == declared)
	}

	@Test("typographic punctuation never leaks as raw utf-8 bytes")
	func noRawUtf8NonAscii() {
		// · (U+00B7) would ship as C2 B7 and × (U+00D7) as C3 97 if the
		// encoder appended a scalar instead of an octal escape.
		let document = MarkdownDocument(parsing: "a · b × c — d … e “f”")
		let bytes = document.render()
		#expect(!bytes.contains([0xC2, 0xB7]))
		#expect(!bytes.contains([0xC3, 0x97]))
	}

	@Test("a long document paginates across several pages")
	func paginates() {
		let paragraph = String(repeating: "the quick brown fox jumps over the lazy dog. ", count: 24)
		let source = (1 ... 12).map { "## Section \($0)\n\n\(paragraph)" }.joined(separator: "\n\n")
		let document = MarkdownDocument(parsing: source)
		let pdf = document.pdfDocument()
		#expect(pdf.pages.count > 1)
	}

	@Test("rendering is deterministic")
	func deterministic() {
		let source = "# Title\n\n- a\n- b\n\n> quote\n\n```\ncode\n```"
		let document = MarkdownDocument(parsing: source)
		#expect(document.render() == document.render())
	}

	@Test("an empty document still produces a valid pdf")
	func emptyDocument() {
		let bytes = MarkdownDocument(parsing: "").render()
		let text = pdfText(bytes)
		#expect(text.hasPrefix("%PDF-1.7"))
		#expect(text.hasSuffix("%%EOF\n"))
	}

	@Test("style knobs reach the artifact")
	func styleKnobs() {
		var style = MarkdownStyle()
		style.pageSize = .letter
		style.typeface = .serif
		let document = MarkdownDocument(parsing: "# Title\n\nbody")
		let text = pdfText(document.render(style: style))
		#expect(text.contains("/MediaBox [0 0 612 792]"))
		#expect(text.contains("/BaseFont /Times-Bold"))
	}
}