import Foundation
import Testing
@testable import Letterpress

@Suite struct StringEscapingTests {
	@Test("escapes parens, backslash, whitespace")
	func delimiters() {
		#expect(pdfEscape("()") == "\\(\\)")
		#expect(pdfEscape("a\\b") == "a\\\\b")
		#expect(pdfEscape("a\nb") == "a\\nb")
		#expect(pdfEscape("a\rb") == "a\\rb")
		#expect(pdfEscape("a\tb") == "a\\tb")
	}

	@Test("ascii passes through untouched")
	func ascii() {
		#expect(pdfEscape("Hello, PDF 123!") == "Hello, PDF 123!")
	}

	@Test("latin-1 letters pass through")
	func latin1() {
		#expect(pdfEscape("café") == "café")
		#expect(pdfEscape("Ünïcödé") == "Ünïcödé")
	}

	@Test("typographic punctuation maps to cp1252 slots")
	func punctuation() {
		#expect(pdfEscape("—") == "\\227")
		#expect(pdfEscape("–") == "\\226")
		#expect(pdfEscape("…") == "\\205")
		#expect(pdfEscape("“") == "\\223")
		#expect(pdfEscape("”") == "\\224")
		#expect(pdfEscape("‘") == "\\221")
		#expect(pdfEscape("’") == "\\222")
		#expect(pdfEscape("€") == "\\200")
		#expect(pdfEscape("™") == "\\231")
		#expect(pdfEscape("•") == "\\225")
	}

	@Test("unsupported glyphs degrade to question marks")
	func unsupported() {
		#expect(pdfEscape("日本語") == "???")
		#expect(pdfEscape("emoji 🚀") == "emoji ?")
	}
}
