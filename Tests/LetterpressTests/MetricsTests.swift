import Foundation
import Testing
@testable import Letterpress

@Suite struct FontMetricsTests {
	@Test("helvetica widths match the afm table")
	func helvetica() {
		#expect(Font.helvetica.width(of: "M", size: 1000) == 833)
		#expect(Font.helvetica.width(of: " ", size: 1000) == 278)
		#expect(Font.helvetica.width(of: "i", size: 1000) == 222)
		#expect(Font.helvetica.width(of: "W", size: 1000) == 944)
		#expect(Font.helvetica.width(of: "0", size: 1000) == 556)
	}

	@Test("times and courier widths match their tables")
	func families() {
		#expect(Font.times.width(of: "W", size: 1000) == 944)
		#expect(Font.times.width(of: "M", size: 1000) == 889)
		#expect(Font.times.width(of: "i", size: 1000) == 278)
		#expect(Font.courier.width(of: "M", size: 1000) == 600)
		#expect(Font.courier.width(of: "i", size: 1000) == 600)
	}

	@Test("widths scale linearly with size")
	func scaling() {
		#expect(Font.helvetica.width(of: "M", size: 12) == 9.996)
		#expect(Font.courier.width(of: "ab", size: 10) == 12)
	}

	@Test("widths are additive across characters")
	func additive() {
		#expect(Font.helvetica.width(of: "MW", size: 1000) == 833 + 944)
		#expect(Font.helvetica.width(of: "", size: 1000) == 0)
	}

	@Test("bold faces carry their own advances, not the regular table")
	func boldAdvances() {
		// adobe afm: Helvetica-Bold i/t/w differ from Helvetica's 222/278/722,
		// even though both faces share M = 833 — so M alone would miss this.
		#expect(Font.helveticaBold.width(of: "i", size: 1000) == 278)
		#expect(Font.helveticaBold.width(of: "t", size: 1000) == 333)
		#expect(Font.helveticaBold.width(of: "w", size: 1000) == 778)
		// poppler draws this bold word at exactly 2278 units. measuring it with
		// Helvetica's 2112 put the following word inside it.
		#expect(Font.helveticaBold.width(of: "what", size: 1000) == 2278)
		#expect(Font.helvetica.width(of: "what", size: 1000) == 2112)
	}

	@Test("every times face has its own advances")
	func timesAdvances() {
		#expect(Font.times.width(of: "M", size: 1000) == 889)
		#expect(Font.times.width(of: "m", size: 1000) == 778)
		#expect(Font.timesBold.width(of: "M", size: 1000) == 944)
		#expect(Font.timesBold.width(of: "t", size: 1000) == 333)
		#expect(Font.timesItalic.width(of: "M", size: 1000) == 833)
		#expect(Font.timesItalic.width(of: "m", size: 1000) == 722)
		#expect(Font.timesBoldItalic.width(of: "M", size: 1000) == 889)
		#expect(Font.timesBoldItalic.width(of: "m", size: 1000) == 778)
	}

	@Test("oblique faces are metric-identical to their upright sibling")
	func obliqueAdvances() {
		#expect(Font.helveticaOblique.width(of: "w", size: 1000) == Font.helvetica.width(of: "w", size: 1000))
		#expect(Font.helveticaBoldOblique.width(of: "w", size: 1000) == Font.helveticaBold.width(of: "w", size: 1000))
		#expect(Font.courierOblique.width(of: "w", size: 1000) == Font.courier.width(of: "w", size: 1000))
	}

	@Test("courier is monospaced across all four faces")
	func courierUniform() {
		for font in [Font.courier, .courierBold, .courierOblique, .courierBoldOblique] {
			#expect(font.width(of: "M", size: 1000) == 600)
			#expect(font.width(of: "i", size: 1000) == 600)
			#expect(font.width(of: "W", size: 1000) == 600)
		}
	}

	@Test("cp1252 punctuation measures at its real advance, not a flat fallback")
	func cp1252Advances() {
		// a flat 556 fallback under-reported the wide glyphs the encoder really
		// emits (… and — are 1000) and over-reported the narrow ones.
		#expect(Font.helvetica.width(of: "\u{2026}", size: 1000) == 1000)   // ellipsis
		#expect(Font.helvetica.width(of: "\u{2014}", size: 1000) == 1000)   // em dash
		#expect(Font.helvetica.width(of: "\u{2013}", size: 1000) == 556)    // en dash
		#expect(Font.helvetica.width(of: "\u{2022}", size: 1000) == 350)    // bullet
		#expect(Font.helvetica.width(of: "\u{2019}", size: 1000) == 222)    // right single quote
		#expect(Font.helvetica.width(of: "\u{201C}", size: 1000) == 333)    // left double quote
		#expect(Font.helvetica.width(of: "\u{00B7}", size: 1000) == 278)    // middle dot
		// latin-1 letters are per-face too: é is 556 in Helvetica, 444 in Times.
		#expect(Font.helvetica.width(of: "\u{00E9}", size: 1000) == 556)
		#expect(Font.times.width(of: "\u{00E9}", size: 1000) == 444)
		#expect(Font.courier.width(of: "\u{00E9}", size: 1000) == 600)
	}

	@Test("a scalar with no winansi glyph measures as this face's question mark")
	func unmappableFallback() {
		// 中 has no winansi glyph, so it renders as '?' — it must measure as '?',
		// which is a different advance in every face.
		let absent = "\u{4E2D}"
		#expect(Font.helvetica.width(of: absent, size: 1000) == 556)
		#expect(Font.helveticaBold.width(of: absent, size: 1000) == 611)
		#expect(Font.times.width(of: absent, size: 1000) == 444)
		#expect(Font.timesBold.width(of: absent, size: 1000) == 500)
		#expect(Font.courier.width(of: absent, size: 1000) == 600)
	}

	@Test("measurement agrees with the encoder, byte for byte")
	func measurementMatchesEncoder() {
		// whatever the encoder writes for a scalar is what the meter charges:
		// two spellings that encode to the same byte measure identically, and a
		// scalar that degrades to '?' measures as '?'.
		#expect(Font.helvetica.width(of: "\u{2026}", size: 1000)
			== Font.helvetica.width(of: "\u{0085}", size: 1000))
		#expect(Font.helvetica.width(of: "\u{2014}", size: 1000)
			== Font.helvetica.width(of: "\u{0097}", size: 1000))
		#expect(Font.helveticaBold.width(of: "\u{4E2D}", size: 1000)
			== Font.helveticaBold.width(of: "?", size: 1000))
	}
}
