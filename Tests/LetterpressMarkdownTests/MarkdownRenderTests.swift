import Letterpress
import LetterpressMarkdown
import LetterpressTestSupport
import Testing

// rendering coverage: the artifact's bytes — fonts, encoding declaration,
// pagination, determinism, and the cp1252 byte guard.

/// the rendered pdf as text. every non-ascii byte travels as a 7-bit octal
/// escape, so the document decodes as utf-8 cleanly.
private func pdfText(_ bytes: [UInt8]) -> String {
	String(decoding: bytes, as: UTF8.self)
}

/// the rectangle operations a rendered document emits, one per line, so two
/// documents can be differenced by the rules one drew and the other did not.
private func rectLines(_ text: String) -> Set<String> {
	var lines: Set<String> = []
	for line in text.separated(by: "\n") where line.hasSuffix(" re") {
		lines.insert(line)
	}
	return lines
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

	@Test("a heading renders bold in the heading face and body text in the body face")
	func fontsAreSelected() {
		let document = MarkdownDocument(parsing: "# Heading\n\nplain body text")
		let text = pdfText(document.render())
		// the theme pairs a sans head with a serif column; read both faces
		// from the theme rather than naming one, or the assertion can pass on a
		// face the document never drew (`/Helvetica` is a prefix of
		// `/Helvetica-Bold`).
		let style = MarkdownStyle.standard
		#expect(text.contains("/BaseFont /\(style.headingFont(1).baseName)"))
		#expect(text.contains("/BaseFont /\(style.typeface.font(bold: false, italic: false).baseName)"))
		#expect(text.contains("(Heading) Tj"))
	}

	@Test("bold and italic runs pick distinct faces")
	func inlineFaces() {
		let document = MarkdownDocument(parsing: "plain **bold** *italic* `code`")
		let text = pdfText(document.render())
		// each emphasis bit selects its own face of the body typeface.
		let body = MarkdownStyle.standard.typeface
		#expect(text.contains("/BaseFont /\(body.font(bold: true, italic: false).baseName)"))
		#expect(text.contains("/BaseFont /\(body.font(bold: false, italic: true).baseName)"))
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
		let fontObjects = text.separated(by: "/Type /Font").count - 1
		let declared = text.separated(by: "/Encoding /WinAnsiEncoding").count - 1
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

	@Test("style knobs reach the artifact")
	func styleKnobs() {
		let document = MarkdownDocument(parsing: "# Title\n\nbody")

		var letter = MarkdownStyle()
		letter.pageSize = .letter
		#expect(pdfText(document.render(style: letter)).contains("/MediaBox [0 0 612 792]"))

		// the body face follows the typeface knob, for every face it offers.
		for typeface in MarkdownTypeface.allCases {
			var style = MarkdownStyle()
			style.typeface = typeface
			let face = typeface.font(bold: false, italic: false).baseName
			#expect(
				pdfText(document.render(style: style)).contains("/BaseFont /\(face)"),
				"the \(typeface) body face did not reach the artifact")
		}
	}

	@Test("a struck run draws one rule, as wide as the glyphs it runs through")
	func strikethroughDraws() {
		let style = MarkdownStyle.standard
		let plain = pdfText(MarkdownDocument(parsing: "withdrawn").render())
		let struck = pdfText(MarkdownDocument(parsing: "~~withdrawn~~").render())
		#expect(struck.contains("(withdrawn) Tj"))
		#expect(!struck.contains("(~"))
		// the strike adds exactly one rule to the page, and it spans the
		// advance of the word it strikes — no more, no less.
		let added = rectLines(struck).subtracting(rectLines(plain))
		#expect(added.count == 1)
		let fields = (added.first ?? "").separated(by: " ")
		#expect(fields.count == 5)
		let advance = style.typeface.font(bold: false, italic: false)
			.width(of: "withdrawn", size: style.bodySize)
		// the page writes its numbers to two decimals, so the rule matches the
		// advance to within that rounding and no further.
		let width = Double(fields[2]) ?? 0
		#expect(abs(width - advance) < 0.01)
		#expect(Double(fields[3]) == 0.6)
	}

	@Test("a struck run keeps its rule when the line is opened out to the measure")
	func strikethroughSurvivesJustification() {
		// justification re-lays every word of a broken line, so a strike that
		// is not carried through the rebuild would vanish from the page.
		let filler = Array(repeating: "measure", count: 60).joined(separator: " ")
		let struck = pdfText(MarkdownDocument(parsing: "~~withdrawn~~ \(filler)").render())
		let plain = pdfText(MarkdownDocument(parsing: filler).render())
		#expect(struck.contains("(withdrawn) Tj"))
		#expect(rectLines(struck).subtracting(rectLines(plain)).count == 1)
	}

	@Test("a struck phrase draws one rule across it, word spaces included")
	func strikethroughCoalesces() {
		let style = MarkdownStyle.standard
		let face = style.typeface.font(bold: false, italic: false)
		let words = ["alpha", "beta", "gamma", "delta"]
		let line = words.joined(separator: " ")
		let plain = pdfText(MarkdownDocument(parsing: line).render())
		let struck = pdfText(MarkdownDocument(parsing: "~~\(line)~~").render())
		// the four words sit on one line, so the strike crosses them as one
		// rule rather than one rule per word.
		let added = rectLines(struck).subtracting(rectLines(plain))
		#expect(added.count == 1)
		let width = Double((added.first ?? "").separated(by: " ")[2]) ?? 0
		let glyphs = words.reduce(0.0) { $0 + face.width(of: $1, size: style.bodySize) }
		// the rule runs past the last glyph — it strikes the word spaces too.
		#expect(width > glyphs + 0.5)
	}
}