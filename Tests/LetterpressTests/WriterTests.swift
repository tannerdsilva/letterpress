import LetterpressTestSupport
import Testing
@testable import Letterpress

/// helper: one page with a couple of marks exercising fonts, fills, and alpha.
private func sampleDocument() -> PDFDocument {
	PDFDocument {
		PDFPage(.a4) {
			Text("a").font(.helvetica, size: 12).at(x: 10, y: 10)
			Text("b").font(.times, size: 12).at(x: 10, y: 30)
			Rect(x: 10, y: 50, width: 20, height: 20).fill(.sky.opacity(0.5))
		}
		PDFPage(.a4) {
			Text("c").font(.helvetica, size: 12).at(x: 10, y: 10)
		}
	}
}

@Suite struct WriterStructureTests {
	@Test("file starts with the pdf header and binary marker")
	func header() {
		let bytes = sampleDocument().render()
		let head = String(decoding: bytes.prefix(9), as: UTF8.self)
		#expect(head == "%PDF-1.7\n")
		#expect(bytes[9] == 0x25)  // second '%'
		#expect(bytes[10] >= 0x80) // non-ascii marker bytes
	}

	@Test("ends with eof")
	func eof() {
		let bytes = sampleDocument().render()
		#expect(String(decoding: bytes.suffix(6), as: UTF8.self) == "%%EOF\n")
	}

	@Test("trailer references the catalog root")
	func trailer() throws {
		let parsed = try #require(ParsedPDF(bytes: sampleDocument().render()))
		let text = String(decoding: parsed.bytes, as: UTF8.self)
		#expect(text.contains("trailer\n<< /Size \(parsed.objectCount) /Root 1 0 R >>\n"))
	}

	@Test("every xref entry points at its object header")
	func xrefResolution() throws {
		let parsed = try #require(ParsedPDF(bytes: sampleDocument().render()))
		for number in 1 ..< parsed.objectCount {
			let offset = parsed.objectOffsets[number]
			#expect(offset >= 0, "object \(number) has an offset")
			#expect(parsed.objectHeader(at: offset, number: number), "object \(number) header at \(offset)")
		}
	}

	@Test("first xref entry is the free head")
	func freeEntry() throws {
		let parsed = try #require(ParsedPDF(bytes: sampleDocument().render()))
		let headerLength = "xref\n0 \(parsed.objectCount)\n".utf8.count
		let entry = String(decoding: parsed.bytes[parsed.xrefOffset + headerLength ..< parsed.xrefOffset + headerLength + 20], as: UTF8.self)
		#expect(entry == "0000000000 65535 f \n")
	}

	@Test("startxref points at the xref table")
	func startxref() throws {
		let bytes = sampleDocument().render()
		let text = String(decoding: bytes, as: UTF8.self)
		let marker = try #require(text.firstRange(of: "startxref\n"))
		let offset = Int(text[marker.upperBound...].prefix { $0 != "\n" })!
		// the parsed model reports the same offset, and it really is 'x'
		let parsed = try #require(ParsedPDF(bytes: bytes))
		#expect(parsed.xrefOffset == offset)
		#expect(bytes[offset] == UInt8(ascii: "x"))
	}

	@Test("catalog and pages tree exist")
	func catalog() throws {
		let parsed = try #require(ParsedPDF(bytes: sampleDocument().render()))
		#expect(parsed.objectBody(1)?.contains("/Type /Catalog /Pages 2 0 R") == true)
		#expect(parsed.objectBody(2)?.contains("/Type /Pages") == true)
		#expect(parsed.objectBody(2)?.contains("/Count 2") == true)
	}

	@Test("page objects carry size, resources, and their stream")
	func pageObjects() throws {
		let parsed = try #require(ParsedPDF(bytes: sampleDocument().render()))
		let pageBody = try #require(parsed.objectBody(3))
		#expect(pageBody.contains("/MediaBox [0 0 595.28 841.89]"))
		#expect(pageBody.contains("/Contents 4 0 R"))
		#expect(pageBody.contains("/F1"))
		#expect(pageBody.contains("/F2"))
		#expect(pageBody.contains("/GS1"))
	}

	@Test("content streams are raw and unwrapped")
	func contentRaw() throws {
		let parsed = try #require(ParsedPDF(bytes: sampleDocument().render()))
		let stream = try #require(parsed.contentStream(4))
		#expect(stream.contains("Tj"))
		#expect(!stream.contains("/Filter"))
	}

	@Test("shared fonts dedupe to one font object")
	func fontDedup() throws {
		let text = String(decoding: sampleDocument().render(), as: UTF8.self)
		// helvetica appears on both pages, times on one
		#expect(text.separated(by: "/BaseFont /Helvetica").count == 2)
		#expect(text.separated(by: "/BaseFont /Times-Roman").count == 2)
	}
}

@Suite struct WriterResourceTests {
	@Test("alpha values dedupe to one ext-gstate object")
	func alphaDedup() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Rect(x: 0, y: 0, width: 10, height: 10).fill(.red.opacity(0.5))
				Rect(x: 20, y: 0, width: 10, height: 10).fill(.blue.opacity(0.5))
			}
		}
		let text = String(decoding: doc.render(), as: UTF8.self)
		#expect(text.separated(by: "/ca 0.5").count == 2)
		#expect(text.separated(by: "/GS1 gs").count == 3)  // both fills use GS1
	}

	@Test("distinct alphas produce distinct ext-gstates")
	func distinctAlphas() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Rect(x: 0, y: 0, width: 10, height: 10).fill(.red.opacity(0.5))
				Rect(x: 20, y: 0, width: 10, height: 10).fill(.blue.opacity(0.25))
			}
		}
		let text = String(decoding: doc.render(), as: UTF8.self)
		#expect(text.contains("/GS1 gs"))
		#expect(text.contains("/GS2 gs"))
	}

	@Test("rendering is deterministic")
	func deterministic() {
		#expect(sampleDocument().render() == sampleDocument().render())
	}

	@Test("an empty document still parses")
	func empty() throws {
		let doc = PDFDocument {}
		let parsed = try #require(ParsedPDF(bytes: doc.render()))
		// a document always has at least one page: catalog + pages tree
		// + the blank page + its content stream, plus the free entry.
		#expect(parsed.objectCount == 5)
		let pages = try #require(parsed.objectBody(2))
		#expect(pages.contains("/Count 1"))
		#expect(pages.contains("/Kids [ 3 0 R]"))
	}

	@Test("render output round-trips through the xref parser")
	func roundTrip() throws {
		for _ in 0 ..< 5 {
			let parsed = try #require(ParsedPDF(bytes: sampleDocument().render()))
			#expect(parsed.objectCount > 4)
		}
	}
}
