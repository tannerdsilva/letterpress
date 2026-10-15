import Letterpress
import SystemPackage

// MARK: - demo document

let document = PDFDocument {
	PDFPage(.a4) {
		Text("letterpress")
			.font(.helveticaBold, size: 42)
			.foregroundColor(.ink)
			.at(x: 72, y: 72)

		// a paragraph rather than a `Text`: the sentence is wider than the sheet, and
		// word wrap is `.frame(maxWidth:)` on a paragraph. as a bare `Text` it ran
		// past the trim and the page clipped its last words.
		Paragraph("a declarative pdf exporter with zero dependencies. every glyph set by hand, no engine in sight.")
			.font(.helvetica, size: 13)
			.foregroundColor(.slate)
			.frame(maxWidth: 449)
			.at(x: 74, y: 122)

		// word-wrapped narrative
		Paragraph("this library mirrors the no-webui architecture: a Mark protocol with a result-builder DSL, value-type primitives, and modifiers that wrap content emission. everything below is drawn by this binary — no external dependencies, no frameworks, just the pdf object model written by hand.")
			.font(.times, size: 12)
			.foregroundColor(.ink)
			.frame(maxWidth: 460)
			.lineHeight(1.5)
			.at(x: 72, y: 170)

		// shapes
		Rect(x: 72, y: 360, width: 130, height: 70)
			.fill(.sky.opacity(0.35))
			.stroke(.blue, width: 2)

		Rect(x: 222, y: 360, width: 130, height: 70, cornerRadius: 14)
			.fill(.green.opacity(0.25))
			.stroke(.green, width: 2)

		Ellipse(x: 392, y: 360, width: 90, height: 70)
			.fill(.amber.opacity(0.5))
			.stroke(.orange, width: 2)

		Ellipse(x: 502, y: 340, width: 70, height: 70)
			.fill(.pink)

		Line(from: Point(x: 72, y: 470), to: Point(x: 540, y: 470))
			.stroke(.indigo, width: 3)

		Polygon([
			Point(x: 72, y: 510),
			Point(x: 172, y: 510),
			Point(x: 132, y: 580),
			Point(x: 232, y: 580),
			Point(x: 192, y: 510),
			Point(x: 352, y: 600),
		])
		.fill(.purple.opacity(0.45))
		.stroke(.purple, width: 1.5)

		// centered + trailing alignment
		Text("centered")
			.font(.helveticaBold, size: 16)
			.foregroundColor(.ink)
			.alignment(.center)
			.at(x: 306, y: 640)

		Text("trailing")
			.font(.helvetica, size: 13)
			.foregroundColor(.gray)
			.alignment(.trailing)
			.at(x: 540, y: 668)

		// typographic punctuation survives the winansi mapping
		Text("“quotes,” em dashes — ellipses… parentheses (and) backslashes \\ all escape cleanly. € ™")
			.font(.courier, size: 9)
			.foregroundColor(.darkGray)
			.at(x: 72, y: 700)
	}
	.background(Color(hex: 0xF8FAFC))

	PDFPage(.letter) {
		Text("page two — letter size")
			.font(.helveticaBold, size: 24)
			.foregroundColor(.ink)
			.at(x: 72, y: 72)

		Rect(x: 72, y: 140, width: 460, height: 28)
			.fill(.indigo.opacity(0.22))
		Rect(x: 72, y: 180, width: 460, height: 28)
			.fill(.indigo.opacity(0.45))
		Rect(x: 72, y: 220, width: 460, height: 28)
			.fill(.indigo.opacity(0.85))

		Paragraph("alpha values always wrap their mark in a balanced q/Q pair, so a translucent fill can never leak into the next mark. each unique alpha becomes one shared ext-gstate object, deduplicated across the whole document.")
			.font(.helvetica, size: 12)
			.foregroundColor(.ink)
			.frame(maxWidth: 460)
			.lineHeight(1.4)
			.at(x: 72, y: 290)
	}
	.background(.white)

	PDFPage(.letter) {
		Text("containers — auto placement, flex, and measurement")
			.font(.helveticaBold, size: 18)
			.foregroundColor(.ink)
			.at(x: 72, y: 72)

		VStack(spacing: 10) {
			Text("letterpress").font(.helveticaBold, size: 22).foregroundColor(.indigo)
			Paragraph("a stack measures every child, wraps text to the column width, and places the column for you — no coordinates past the stack's own .at.")
				.font(.helvetica, size: 10)
				.foregroundColor(.slate)
				.frame(maxWidth: 300)
				.lineHeight(1.4)
			Rect(x: 0, y: 0, width: 300, height: 26).fill(.sky.opacity(0.35))
		}
		.at(x: 72, y: 120)

		HStack(alignment: .center) {
			Spacer()
			Text("centered by two spacers under a 400pt proposal").font(.helvetica, size: 12).foregroundColor(.ink)
			Spacer()
		}
		.frame(maxWidth: 400)
		.at(x: 72, y: 300)

		Paragraph("a min-width band centers its content")
			.font(.helvetica, size: 10)
			.foregroundColor(.slate)
			.frame(minWidth: 300, alignment: .center)
			.at(x: 72, y: 335)

		HStack(alignment: .bottom, spacing: 6) {
			Rect(x: 0, y: 0, width: 24, height: 30).fill(.amber.opacity(0.6))
			Rect(x: 0, y: 0, width: 24, height: 46).fill(.green.opacity(0.6)).stroke(.indigo, width: 0.5)
			Rect(x: 0, y: 0, width: 24, height: 22).fill(.blue.opacity(0.6))
		}
		.at(x: 72, y: 380)
	}
	.background(.white)

	Galley(.a5, margins: Margins(top: 56, leading: 56, bottom: 56, trailing: 56), spacing: 14) {
		Paragraph("flow — one logical page, broken where the content box runs out")
			.font(.helveticaBold, size: 16)
			.foregroundColor(.indigo)

		Paragraph("a galley measures every child once at the column width, packs it down the content box, and materializes a physical page per bucket. spacing applies within a page but never across a break, so every page starts flush at the margin.")
			.font(.times, size: 12)
			.foregroundColor(.ink)
			.lineHeight(1.5)

		Rect(x: 0, y: 0, width: 200, height: 2).fill(.amber.opacity(0.9))

		Paragraph("the break is between siblings, never through a mark: a paragraph is a single atomic unit, and a nested stack stays together even when it forces a page break around itself. children taller than a full content box overflow visibly rather than splitting.")
			.font(.times, size: 12)
			.foregroundColor(.ink)
			.lineHeight(1.5)

		Paragraph("measurement drives both sides of the seam: the same column-width proposal that decides where to break is the proposal the page's stacked column renders under, so a paragraph re-wraps identically wherever it lands.")
			.font(.times, size: 12)
			.foregroundColor(.ink)
			.lineHeight(1.5)

		Paragraph("each physical page is an ordinary page — the object catalog, per-page resources, and byte determinism are the same machinery every other page uses. nothing downstream knows a galley was here.")
			.font(.times, size: 12)
			.foregroundColor(.ink)
			.lineHeight(1.5)

		Paragraph("five and six and seven — enough body copy to spill the galley past the first page, proving both the seam and the flush restart of page two.")
			.font(.times, size: 12)
			.foregroundColor(.ink)
			.lineHeight(1.5)

		Paragraph("and one more paragraph of body copy, so the break falls somewhere in the middle of the flow rather than exactly at its end — the spill is ordinary typesetting, not the last item.")
			.font(.times, size: 12)
			.foregroundColor(.ink)
			.lineHeight(1.5)

		VStack(spacing: 6) {
			Text("nested column").font(.helveticaBold, size: 12).foregroundColor(.ink)
			Paragraph("a container inside a galley flows as a single atomic unit.").font(.helvetica, size: 10).foregroundColor(.slate).frame(maxWidth: 240).lineHeight(1.4)
		}
	}
	.background(Color(hex: 0xF6F8FB))
}

// MARK: - render + write

let bytes = document.render()
print("pages: \(document.pages.count), bytes: \(bytes.count)")

// the exporter hands back bytes and stops there. writing them is the caller's
// business, and the demo does it the way any caller would: a file descriptor.
let output = FilePath("letterpress-example.pdf")
let file = try FileDescriptor.open(
	output, .writeOnly, options: [.create, .truncate], permissions: .ownerReadWrite)
_ = try file.closeAfter { try file.writeAll(bytes) }
print("wrote \(output.description)")
