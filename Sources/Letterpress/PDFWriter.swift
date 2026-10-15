// MARK: - PDFWriter

/// assembles a rendered document: page content streams, object numbering,
/// font/gstate catalogs, the xref table, and the trailer.
///
/// layout of object numbers:
///
///     1                    catalog
///     2                    pages tree
///     3 + 2i, 4 + 2i       page i object + its content stream
///     ...                  fonts (shared, deduped by basefont name)
///     ...                  ext-gstates (shared, deduped by alpha)
internal struct PDFWriter {
	let pages: [PDFPage]

	func render() -> [UInt8] {
		let streams = pages.map { page -> (bytes: [UInt8], fonts: [String], alphas: [Double]) in
			var renderer = Renderer(pageHeight: page.size.height)
			page.write(to: &renderer)
			return (renderer.bytes, renderer.fontNames, renderer.alphaValues)
		}

		// global catalogs, first-seen order
		var fontCatalog: [String] = []
		var alphaCatalog: [Double] = []
		for stream in streams {
			for name in stream.fonts where !fontCatalog.contains(name) { fontCatalog.append(name) }
			for alpha in stream.alphas where !alphaCatalog.contains(alpha) { alphaCatalog.append(alpha) }
		}

		let pageCount = pages.count
		let firstFontObject = 3 + 2 * pageCount
		let firstGStateObject = firstFontObject + fontCatalog.count
		let objectCount = 2 + 2 * pageCount + fontCatalog.count + alphaCatalog.count

		var output: [UInt8] = []
		var offsets = [Int](repeating: 0, count: objectCount + 1)

		func emit(_ string: String) {
			output.append(contentsOf: string.utf8)
		}
		func emitObject(_ objectNumber: Int, _ body: String) {
			offsets[objectNumber] = output.count
			emit("\(objectNumber) 0 obj\n")
			emit(body)
			emit("endobj\n")
		}

		// header + binary marker line (the spec's hint that this stream is binary)
		emit("%PDF-1.7\n")
		output.append(contentsOf: [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])

		// 1: catalog
		emitObject(1, "<< /Type /Catalog /Pages 2 0 R >>\n")

		// 2: pages tree
		var kids = ""
		for index in 0 ..< pageCount {
			kids += " \(3 + 2 * index) 0 R"
		}
		emitObject(2, "<< /Type /Pages /Kids [\(kids)] /Count \(pageCount) >>\n")

		// pages + content streams
		for (index, page) in pages.enumerated() {
			let pageObject = 3 + 2 * index
			let streamObject = 4 + 2 * index
			let stream = streams[index]

			var resources = "<< /Font <<"
			for (nameIndex, name) in stream.fonts.enumerated() {
				let globalIndex = fontCatalog.firstIndex(of: name)!
				resources += " /F\(nameIndex + 1) \(firstFontObject + globalIndex) 0 R"
			}
			resources += " >>"
			if !stream.alphas.isEmpty {
				resources += " /ExtGState <<"
				for (alphaIndex, alpha) in stream.alphas.enumerated() {
					let globalIndex = alphaCatalog.firstIndex(of: alpha)!
					resources += " /GS\(alphaIndex + 1) \(firstGStateObject + globalIndex) 0 R"
				}
				resources += " >>"
			}
			resources += " >>"

			let mediaBox = "0 0 \(PDFNumber(page.size.width)) \(PDFNumber(page.size.height))"
			emitObject(pageObject, "<< /Type /Page /Parent 2 0 R /MediaBox [\(mediaBox)] /Resources \(resources) /Contents \(streamObject) 0 R >>\n")
			// content streams are emitted by hand — the stream body sits
			// between `stream` and `endstream`, before `endobj`.
			offsets[streamObject] = output.count
			emit("\(streamObject) 0 obj\n")
			emit("<< /Length \(stream.bytes.count) >>\nstream\n")
			output.append(contentsOf: stream.bytes)
			emit("\nendstream\nendobj\n")
		}

		// fonts
		for (index, name) in fontCatalog.enumerated() {
			emitObject(firstFontObject + index, "<< /Type /Font /Subtype /Type1 /BaseFont /\(name) /Encoding /WinAnsiEncoding >>\n")
		}

		// ext-gstates
		for (index, alpha) in alphaCatalog.enumerated() {
			let value = PDFNumber(alpha, decimals: 4)
			emitObject(firstGStateObject + index, "<< /Type /ExtGState /ca \(value) /CA \(value) >>\n")
		}

		// xref
		let xrefOffset = output.count
		emit("xref\n0 \(objectCount + 1)\n")
		emit("0000000000 65535 f \n")
		for objectNumber in 1 ... objectCount {
			emit("\(padded10(offsets[objectNumber])) 00000 n \n")
		}

		// trailer
		emit("trailer\n<< /Size \(objectCount + 1) /Root 1 0 R >>\n")
		emit("startxref\n\(xrefOffset)\n")
		emit("%%EOF\n")

		return output
	}
}

/// zero-pad an integer to exactly 10 digits (xref offset column).
internal func padded10(_ value: Int) -> String {
	var string = String(value)
	while string.count < 10 {
		string = "0" + string
	}
	return string
}
