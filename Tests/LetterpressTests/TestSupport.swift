import Foundation
@testable import Letterpress

// MARK: - structural pdf harness

/// parse a rendered pdf far enough to validate its object graph: xref
/// offsets, per-object bodies, and content streams.
struct ParsedPDF {
	let bytes: [UInt8]
	/// 1-indexed object offsets; -1 when the object has no entry.
	let objectOffsets: [Int]
	let xrefOffset: Int
	let objectCount: Int

	init?(bytes: [UInt8]) {
		guard bytes.count > 16,
			let first8 = String(data: Data(bytes.prefix(8)), encoding: .utf8),
			first8.hasPrefix("%PDF-")
		else { return nil }

		let text = String(decoding: bytes, as: UTF8.self)
		guard let xrefRange = text.range(of: "startxref\n"),
			let xrefLine = text[xrefRange.upperBound...].split(separator: "\n").first,
			let xrefOffset = Int(xrefLine),
			xrefOffset < bytes.count
		else { return nil }

		let xrefText = String(decoding: bytes[xrefOffset...], as: UTF8.self)
		guard xrefText.hasPrefix("xref\n"),
			let countLine = xrefText.split(separator: "\n").dropFirst().first,
			let countText = countLine.split(separator: " ").dropFirst().first,
			let objectCount = Int(countText)
		else { return nil }

		let headerLength = "xref\n0 \(objectCount)\n".utf8.count
		var offsets = [Int](repeating: -1, count: objectCount)
		for index in 0 ..< objectCount {
			let position = xrefOffset + headerLength + index * 20
			guard position + 10 <= bytes.count else { return nil }
			let entry = String(decoding: bytes[position ..< position + 10], as: UTF8.self)
			offsets[index] = Int(entry) ?? -1
		}

		self.bytes = bytes
		self.objectOffsets = offsets
		self.xrefOffset = xrefOffset
		self.objectCount = objectCount
	}

	/// the body between `N 0 obj` and `endobj` (stream bodies included).
	func objectBody(_ number: Int) -> String? {
		guard number > 0, number < objectCount, objectOffsets[number] >= 0 else { return nil }
		let offset = objectOffsets[number]
		let text = String(decoding: bytes.dropFirst(offset), as: UTF8.self)
		guard let bodyStart = text.range(of: "obj\n") else { return nil }
		guard let end = text.range(of: "endobj") else { return nil }
		return String(text[bodyStart.upperBound ..< end.lowerBound])
	}

	/// the raw content-stream body of a stream object.
	func contentStream(_ number: Int) -> String? {
		guard let body = objectBody(number), let start = body.range(of: "stream\n") else { return nil }
		let after = body[start.upperBound...]
		guard let end = after.range(of: "\nendstream") else { return nil }
		return String(after[..<end.lowerBound])
	}

	/// true when the given byte offset starts an object header for `number`.
	func objectHeader(at offset: Int, number: Int) -> Bool {
		guard offset >= 0, offset + 8 < bytes.count else { return false }
		let text = String(decoding: bytes[offset...], as: UTF8.self)
		return text.hasPrefix("\(number) 0 obj")
	}
}

// MARK: - render helpers

/// a one-page (or n-page) document built from raw marks.
func renderedPage(_ marks: [any Mark], size: PageSize = .a4) -> ParsedPDF {
	renderedDocument([marks], sizes: [size])
}

func renderedDocument(_ pageMarks: [[any Mark]], sizes: [PageSize]) -> ParsedPDF {
	let pages = pageMarks.enumerated().map { index, marks in
		PDFPage(sizes[index]) { marks }
	}
	let document = PDFDocument { pages }
	let bytes = document.render()
	return ParsedPDF(bytes: bytes)!
}

/// the first content stream's text of the rendered form of `mark`.
func contentStreamText(_ document: PDFDocument) -> String {
	let parsed = ParsedPDF(bytes: document.render())!
	// page objects: 3,5,7...; their streams: 4,6,8...
	return parsed.contentStream(4)!
}

/// all content streams of `document`, concatenated.
func allContentStreams(_ document: PDFDocument) -> String {
	let parsed = ParsedPDF(bytes: document.render())!
	var result = ""
	for number in 4 ..< parsed.objectCount where number % 2 == 0 {
		if let stream = parsed.contentStream(number) {
			result += stream
		}
	}
	return result
}
