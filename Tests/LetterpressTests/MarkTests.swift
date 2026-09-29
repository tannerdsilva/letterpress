import Foundation
import Testing
@testable import Letterpress

private let a4Height = 841.89

@Suite struct TextMarkTests {
	@Test("single line text emits a full text object")
	func basic() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Text("hi").font(.helveticaBold, size: 12).at(x: 100, y: 100)
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains("BT\n"))
		#expect(s.contains("/F1 12 Tf\n"))
		// baseline: 100 + 0.8 * 12 = 109.6, flipped on a4
		#expect(s.contains("1 0 0 1 100 732.29 Tm\n"))
		#expect(s.contains("(hi) Tj\n"))
		#expect(s.hasSuffix("ET\n"))
	}

	@Test("y coordinates are flipped to pdf's y-up space")
	func flip() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Text("top").font(.helvetica, size: 10).at(x: 10, y: 10)
				Text("bottom").font(.helvetica, size: 10).at(x: 10, y: 800)
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains("1 0 0 1 10 823.89 Tm\n"))   // near the top of the page
		#expect(s.contains("1 0 0 1 10 33.89 Tm\n"))    // near the bottom
	}

	@Test("foregroundColor sets fill color without painting")
	func foregroundColor() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Text("red").font(.helvetica, size: 12).foregroundColor(.red).at(x: 72, y: 200)
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains("0.86 0.15 0.15 rg\n"))
		#expect(s.contains("(red) Tj\n"))
		#expect(!s.contains(" f\n"))
	}

	@Test("centered and trailing alignment shift the anchor")
	func alignment() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				// courier: "hi" = 1200 units * 12 / 1000 = 14.4 wide (exact)
				Text("hi").font(.courier, size: 12).alignment(.center).at(x: 306, y: 200)
				Text("hi").font(.courier, size: 12).alignment(.trailing).at(x: 306, y: 220)
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains("1 0 0 1 298.8 "))
		#expect(s.contains("1 0 0 1 291.6 "))
	}

	@Test("font state is restored after the modifier scope")
	func stateRestoration() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Text("big").font(.helvetica, size: 99).at(x: 10, y: 10)
				Text("default").at(x: 10, y: 30)
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains("/F1 99 Tf\n"))
		#expect(s.contains("/F1 12 Tf\n"))
	}

	@Test("two fonts register two resources")
	func twoFonts() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Text("a").font(.helvetica, size: 12).at(x: 10, y: 10)
				Text("b").font(.times, size: 12).at(x: 10, y: 30)
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains("/F1 12 Tf\n"))
		#expect(s.contains("/F2 12 Tf\n"))
	}

	@Test("embedded newlines emit stacked lines")
	func multiline() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Text("one\ntwo").font(.helvetica, size: 10).at(x: 10, y: 10)
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains("(one) Tj\n"))
		#expect(s.contains("(two) Tj\n"))
	}

	@Test("paragraph wraps words into the frame")
	func wrap() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Paragraph("aaa bbb ccc")
					.font(.helvetica, size: 10)
					.frame(maxWidth: 50)
					.at(x: 10, y: 10)
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains("(aaa bbb) Tj\n"))
		#expect(s.contains("(ccc) Tj\n"))
	}
}

@Suite struct ShapeMarkTests {
	@Test("filled rect emits color, path, paint, scope")
	func filledRect() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Rect(x: 72, y: 360, width: 130, height: 70).fill(.red)
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains("q\n"))
		#expect(s.contains("0.86 0.15 0.15 rg\n"))
		// bottom-left pdf coords: y=360 → 841.89-360=481.89, minus height
		#expect(s.contains("72 411.89 130 70 re\n"))
		#expect(s.contains("f\n"))
		#expect(s.contains("Q\n"))
	}

	@Test("fill then stroke paints path, fill, stroke in that order")
	func fillStroke() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Rect(x: 72, y: 360, width: 130, height: 70)
					.fill(.red)
					.stroke(.blue, width: 2)
			}
		}
		let s = contentStreamText(doc)
		let pathEnd = try #require(s.range(of: "re\n"))
		let fill = try #require(s.range(of: "f\n"))
		let stroke = try #require(s.range(of: "S\n"))
		#expect(pathEnd.lowerBound < fill.lowerBound)
		#expect(fill.upperBound < stroke.lowerBound)
		#expect(s.contains("2 w\n"))
		#expect(s.contains("0.15 0.39 0.92 RG\n"))
	}

	@Test("translucent fill registers an ext-gstate and scopes it")
	func translucent() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Rect(x: 10, y: 10, width: 10, height: 10).fill(.sky.opacity(0.35))
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains("/GS1 gs\n"))
	}

	@Test("rounded rect emits bezier path instead of re")
	func rounded() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Rect(x: 10, y: 10, width: 100, height: 50, cornerRadius: 10).fill(.green)
			}
		}
		let s = contentStreamText(doc)
		#expect(!s.contains(" re\n"))
		#expect(s.contains(" m\n"))
		#expect(s.contains(" c\n"))
		#expect(s.contains("h\n"))
		#expect(s.contains("f\n"))
	}

	@Test("ellipse emits a closed bezier outline")
	func ellipse() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Ellipse(x: 10, y: 10, width: 90, height: 70).fill(.amber)
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains(" m\n"))
		#expect(s.contains(" c\n"))
		#expect(s.contains("f\n"))
	}

	@Test("line strokes from point to point")
	func line() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Line(from: Point(x: 72, y: 470), to: Point(x: 540, y: 470)).stroke(.indigo, width: 3)
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains("72 371.89 m\n"))   // flipped
		#expect(s.contains("540 371.89 l\n"))
		#expect(s.contains("3 w\n"))
		#expect(s.contains("S\n"))
	}

	@Test("polygon emits a closed path")
	func polygon() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Polygon([Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)]).fill(.purple)
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains(" m\n"))
		#expect(s.contains(" l\n"))
		#expect(s.hasSuffix("h\nf\nQ\n"))
	}

	@Test("empty mark and any-mark eraser render nothing extra")
	func emptyAndErasure() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				EmptyMark()
				AnyMark(Text("x").at(x: 10, y: 10))
			}
		}
		let s = contentStreamText(doc)
		#expect(s.contains("(x) Tj\n"))
	}

	@Test("chained mark is a generic nesting")
	func nestedType() {
		let mark = Text("hi").font(.helvetica, size: 12).at(x: 0, y: 0)
		let reflect = String(describing: type(of: mark))
		#expect(reflect.contains("ModifiedMark"))
		#expect(reflect.contains("FontModifier"))
		#expect(reflect.contains("PositionModifier"))
	}
}
