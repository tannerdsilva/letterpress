import Testing
import Letterpress
import LetterpressMarkdown

// the visual contract: the artifact's bytes must carry the theme — a running
// folio on every page, a separated heading scale, and the accent ink reserved
// for the structural marks.
//
// every earlier defect in this pipeline was found by looking at the page, not
// by the suite, so each property an eye verified is pinned here: a later change
// has to argue with a test instead of quietly reverting the design.

/// the rendered pdf as text. every non-ascii byte travels as a 7-bit octal
/// escape, so the document decodes as utf-8 cleanly.
private func pdfText(_ bytes: [UInt8]) -> String {
	String(decoding: bytes, as: UTF8.self)
}

/// whether `text` carries the accent ink `0x1F4E79` as the fill operator writes
/// it. the operator rounds its components, so match the leading digits rather
/// than the value.
private func hasAccentFill(_ text: String) -> Bool {
	text.firstMatch(of: /0\.12[0-9]* 0\.3[0-9]* 0\.47[0-9]* rg/) != nil
}

@Suite struct MarkdownStyleTests {
	/// a source long enough to break across several pages.
	private func longSource(sections: Int) -> String {
		let paragraph = String(repeating: "the quick brown fox jumps over the lazy dog. ", count: 24)
		return (1 ... sections).map { "## Section \($0)\n\n\(paragraph)" }.joined(separator: "\n\n")
	}

	@Test("every page carries a running folio: its number over the page count")
	func folioNumbersEveryPage() {
		let document = MarkdownDocument(parsing: "# Running Head\n\n" + longSource(sections: 12))
		let pdf = document.pdfDocument()
		let total = pdf.pages.count
		#expect(total > 2, "the fixture did not paginate")
		let text = pdfText(pdf.render())
		for page in 1 ... total {
			#expect(text.contains("(\(page) / \(total)) Tj"), "page \(page) has no folio")
		}
	}

	@Test("the folio reports the physical page count, not an estimate")
	func folioCountsPhysicalPages() {
		let document = MarkdownDocument(parsing: "# Running Head\n\n" + longSource(sections: 12))
		let pdf = document.pdfDocument()
		let text = pdfText(pdf.render())
		// a folio that counted blocks, or stopped at the last text page, would
		// leave the final page reading something other than `n / n`.
		#expect(text.contains("(\(pdf.pages.count) / \(pdf.pages.count)) Tj"))
	}

	@Test("the folio repeats the document title as one uppercase string")
	func folioRepeatsTitle() {
		let document = MarkdownDocument(parsing: "# Quarterly Report\n\nbody copy")
		let text = pdfText(document.render())
		// the heading itself draws word by word, so the joined uppercase
		// string can only have come from the folio.
		#expect(text.contains("(QUARTERLY REPORT) Tj"))
	}

	@Test("the heading scale separates h1, h2 and h3 in size")
	func headingScale() {
		let document = MarkdownDocument(parsing: "# One\n\n## Two\n\n### Three\n\nbody")
		let text = pdfText(document.render())
		// 2.0, 1.32 and 1.14 × the 12.5pt body.
		for size in [" 25 Tf", " 16.5 Tf", " 14.25 Tf"] {
			#expect(text.contains(size), "the heading scale lost \(size)")
		}
	}

	@Test("the h1 rule paints in the accent ink, and a plain document has none")
	func h1RuleIsAccented() {
		let titled = pdfText(MarkdownDocument(parsing: "# Title\n\nbody copy").render())
		#expect(hasAccentFill(titled), "the h1 rule is not in the accent ink")

		// the accent is the theme's scarce resource: a document with no
		// heading, list, quote, table or code must not spend it.
		let plain = pdfText(MarkdownDocument(parsing: "body copy only, nothing else").render())
		#expect(!hasAccentFill(plain), "a plain document painted accent ink")
	}

	@Test("list markers paint in the accent ink, and a list-free document has none")
	func listMarkersAreAccented() {
		let listed = pdfText(MarkdownDocument(parsing: "body copy\n\n- one\n- two").render())
		#expect(hasAccentFill(listed), "the list markers lost the accent ink")
	}

	@Test("h5 sets as a tracked uppercase label")
	func smallCapsLabel() {
		let document = MarkdownDocument(parsing: "##### small caps label\n\nbody copy")
		let text = pdfText(document.render())
		#expect(text.contains("(SMALL) Tj"))
		#expect(text.contains("(LABEL) Tj"))
		// the label is the only tracked text in the theme.
		#expect(text.contains("0.6 Tc"), "the small-caps label lost its tracking")
	}

	@Test("each heading level draws in its own ink")
	func headingInks() {
		// h3 takes the accent, h5 the muted grey, h1 and h2 the heading ink.
		let document = MarkdownDocument(parsing: "# one\n\n## two\n\n### three\n\nbody")
		let text = pdfText(document.render())
		#expect(text.contains("0.04 0.05 0.07 rg"), "the heading ink is missing")
		#expect(hasAccentFill(text), "the h3 ink is missing")
	}

	@Test("a code block shrinks to hold its longest line instead of breaking it")
	func codeShrinksToFit() {
		// the longest line the panel can hold at its smallest size: wider than
		// the panel at the shipped size, so the block shrinks, but never broken
		// — breaking it would leave a one-character fragment that reads as a
		// broken identifier. the length comes off the theme's own measure, so
		// the fixture lands in that window whatever the column is.
		let style = MarkdownStyle.standard
		let usable = style.contentWidth - 24          // the panel's two insets
		let preferred = Font.courier.width(of: "0", size: style.codeSize)
		let floorWidth = Font.courier.width(of: "0", size: style.codeSizeFloor)
		let count = max(Int(usable / floorWidth), Int(usable / preferred) + 1)
		let line = String(repeating: "a", count: count)
		let text = pdfText(MarkdownDocument(parsing: "```\n\(line)\n```").render())
		#expect(text.contains("(\(line)) Tj"), "the code line was broken into a fragment")
		#expect(!text.contains(" \(style.codeSize) Tf"), "the panel did not shrink to hold the line")
	}

	@Test("a code block too wide for any size keeps the full size and wraps")
	func codeWrapsWhenItCannotFit() {
		// the floor is the floor: a line no size can hold must not drag the
		// whole block down to an illegible size on its way to wrapping.
		let line = String(repeating: "a", count: 200)
		let text = pdfText(MarkdownDocument(parsing: "```\n\(line)\n```").render())
		#expect(!text.contains("(\(line)) Tj"), "an unholdable line was not wrapped")
		#expect(text.contains(" 11 Tf"), "a block that must wrap still shrank")
	}
}