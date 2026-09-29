import Foundation
import Testing
@testable import Letterpress

@Suite struct DocumentTests {
	@Test("page size variants report correct dimensions")
	func sizes() {
		#expect(PageSize.a4.size == (595.28, 841.89))
		#expect(PageSize.letter.size == (612, 792))
		#expect(PageSize.a5.size == (419.53, 595.28))
		#expect(PageSize.custom(width: 100, height: 200).size == (100, 200))
		#expect(PageSize.letter.width == 612)
		#expect(PageSize.letter.height == 792)
	}

	@Test("letter page emits a letter media box")
	func letterMediaBox() throws {
		let doc = PDFDocument {
			PDFPage(.letter) { Text("x").at(x: 10, y: 10) }
		}
		let parsed = try #require(ParsedPDF(bytes: doc.render()))
		#expect(parsed.objectBody(3)?.contains("/MediaBox [0 0 612 792]") == true)
	}

	@Test("page background paints a full-bleed rect first")
	func background() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Text("x").at(x: 10, y: 10)
			}
			.background(Color(hex: 0xF8FAFC))
		}
		let s = allContentStreams(doc)
		let rect = "0 0 595.28 841.89 re f"
		#expect(s.contains(rect))
		#expect(s.contains("0.972549 0.980392 0.988235 rg"))
	}

	@Test("two pages render two page objects and content streams")
	func multiplePages() throws {
		let doc = PDFDocument {
			PDFPage(.a4) { Text("one").at(x: 10, y: 10) }
			PDFPage(.a4) { Text("two").at(x: 10, y: 10) }
		}
		let parsed = try #require(ParsedPDF(bytes: doc.render()))
		let pages = try #require(parsed.objectBody(2))
		#expect(pages.contains("/Count 2"))
		#expect(pages.contains("3 0 R"))
		#expect(pages.contains("5 0 R"))
		#expect(parsed.contentStream(4)?.contains("(one)") == true)
		#expect(parsed.contentStream(6)?.contains("(two)") == true)
	}

	@Test("builder supports conditionals and optionals")
	func builderConditionals() throws {
		let show = true
		let hidden = false
		let doc = PDFDocument {
			PDFPage(.a4) {
				if show {
					Text("shown").at(x: 10, y: 10)
				}
				if hidden {
					Text("hidden").at(x: 10, y: 30)
				} else {
					Text("else-branch").at(x: 10, y: 30)
				}
			}
		}
		let s = allContentStreams(doc)
		#expect(s.contains("(shown)"))
		#expect(!s.contains("(hidden)"))
		#expect(s.contains("(else-branch)"))
	}

	@Test("marks render through AnyMark unchanged")
	func anyMark() throws {
		let doc = PDFDocument {
			PDFPage(.a4) {
				AnyMark(Text("erased").at(x: 10, y: 10))
			}
		}
		let s = allContentStreams(doc)
		#expect(s.contains("(erased)"))
	}

	@Test("write(to:) produces a file with the same bytes")
	func writeToURL() throws {
		let doc = PDFDocument {
			PDFPage(.a4) { Text("disk").font(.helveticaBold, size: 20).at(x: 72, y: 72) }
		}
		let expected = doc.render()
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("letterpress-test-\(UUID().uuidString).pdf")
		try doc.write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }
		let onDisk = try Data(contentsOf: url)
		#expect(Array(onDisk) == expected)
	}

	@Test("example document renders and writes")
	func exampleDocument() throws {
		// mirror the shipped example's surface so the demo never rots
		let doc = PDFDocument {
			PDFPage(.a4) {
				Text("letterpress").font(.helveticaBold, size: 42).foregroundColor(.ink).at(x: 72, y: 72)
				Paragraph("wrapped body text.").font(.times, size: 12).frame(maxWidth: 460).lineHeight(1.5).at(x: 72, y: 170)
				Rect(x: 72, y: 360, width: 130, height: 70).fill(.sky.opacity(0.35)).stroke(.blue, width: 2)
				Ellipse(x: 392, y: 360, width: 90, height: 70).fill(.amber.opacity(0.5))
				Line(from: Point(x: 72, y: 470), to: Point(x: 540, y: 470)).stroke(.indigo, width: 3)
				Polygon([Point(x: 72, y: 510), Point(x: 172, y: 510), Point(x: 132, y: 580)]).fill(.purple.opacity(0.45))
			}
			.background(Color(hex: 0xF8FAFC))

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
		let parsed = try #require(ParsedPDF(bytes: doc.render()))
		// catalog + pages tree + 4 pages (2 declared + 2 galley) + 4 streams
		// + shared fonts {helveticaBold, times, helvetica} = 3 and alphas
		// {0.35, 0.5, 0.45, 0.6, 0.9} = 5 (catalogs dedup globally across
		// pages) = 18 objects, plus the free head.
		#expect(parsed.objectCount == 18 + 1)
	}
}
