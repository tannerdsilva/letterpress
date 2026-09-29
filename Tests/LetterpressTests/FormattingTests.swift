import Foundation
import Testing
@testable import Letterpress

@Suite struct PDFNumberTests {
	@Test("fixed decimals with trailing zeros trimmed")
	func decimals() {
		#expect(PDFNumber(1.5).description == "1.5")
		#expect(PDFNumber(0).description == "0")
		#expect(PDFNumber(12.345, decimals: 4).description == "12.345")
	}

	@Test("no negative zero")
	func negativeZero() {
		#expect(PDFNumber(-0.0).description == "0")
		#expect(PDFNumber(0.0).description == "0")
	}

	@Test("negatives")
	func negatives() {
		#expect(PDFNumber(-3.14159).description == "-3.14")
		#expect(PDFNumber(-0.5).description == "-0.5")
	}

	@Test("rounding")
	func rounding() {
		#expect(PDFNumber(0.005).description == "0.01")
		#expect(PDFNumber(19.996, decimals: 2).description == "20")
		#expect(PDFNumber(19.9, decimals: 0).description == "20")
	}

	@Test("whole numbers at zero decimals drop the point")
	func zeroDecimals() {
		#expect(PDFNumber(5, decimals: 0).description == "5")
		#expect(PDFNumber(0, decimals: 0).description == "0")
	}
}

@Suite struct PaddedTenTests {
	@Test("zero pads to ten digits")
	func padding() {
		#expect(padded10(0) == "0000000000")
		#expect(padded10(42) == "0000000042")
		#expect(padded10(1234567890) == "1234567890")
		#expect(padded10(12345678901) == "12345678901")
	}
}
