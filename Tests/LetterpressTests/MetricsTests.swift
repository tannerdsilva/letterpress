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
}
