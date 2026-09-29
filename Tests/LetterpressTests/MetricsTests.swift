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

	@Test("all faces of a family share the family table")
	func faces() {
		#expect(Font.helveticaBold.width(of: "M", size: 1000) == Font.helvetica.width(of: "M", size: 1000))
		#expect(Font.timesItalic.width(of: "M", size: 1000) == Font.times.width(of: "M", size: 1000))
	}
}
