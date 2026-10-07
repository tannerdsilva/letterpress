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

	@Test("latin-1 letters and cp1252 bytes become octal escapes")
	func latin1() {
		// the stream must stay 7-bit: a bare scalar would be utf-8-encoded and
		// rasterize as mojibake ("cafÃ©", "Â·")
		#expect(pdfEscape("café") == "caf\\351")
		#expect(pdfEscape("Ünïcödé") == "\\334n\\357c\\366d\\351")
		#expect(pdfEscape("·") == "\\267")
		#expect(pdfEscape("×") == "\\327")
	}

	@Test("a rendered stream carries no bare multi-byte utf-8 for latin-1 text")
	func latin1Stream() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Text("·×— café").font(.helvetica, size: 12).at(x: 10, y: 10)
			}
		}
		let stream = contentStreamText(doc)
		#expect(stream.contains("(\\267\\327\\227 caf\\351) Tj"))

		let bytes = doc.render()
		#expect(countOccurrences(bytes, [0xC2, 0xB7]) == 0, "middle dot shipped as utf-8")
		#expect(countOccurrences(bytes, [0xC3, 0x97]) == 0, "multiplication sign shipped as utf-8")
		#expect(countOccurrences(bytes, [0xC3, 0xA9]) == 0, "e-acute shipped as utf-8")
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
