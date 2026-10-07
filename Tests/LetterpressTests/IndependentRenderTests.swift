import Foundation
import Testing
@testable import Letterpress

// the independent check: render a page, then ask a parser we did not write where
// the glyphs actually landed. every real defect this exporter has had was found
// this way — by rasterizing and measuring against poppler — and none of them by
// its own tests, which validate the library against its own model of itself.
//
// the suite skips (visibly) where poppler is absent.

/// the independent parser, driven as a subprocess.
private enum Poppler {
	/// `/usr/bin/env` so the tool is found on PATH rather than hard-coded.
	private static let launcher = "/usr/bin/env"

	/// whether `pdftotext` exists on this host.
	static let available: Bool = {
		run(["pdftotext", "-v"]).status == 0
	}()

	/// one word and the horizontal extent the parser gave it.
	struct Word {
		let xMin: Double
		let xMax: Double
		let text: String
	}

	/// run a poppler tool and return its exit status and stdout.
	@discardableResult
	private static func run(_ arguments: [String]) -> (status: Int32, output: String) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: launcher)
		process.arguments = arguments
		let out = Pipe()
		process.standardOutput = out
		process.standardError = Pipe()
		do { try process.run() } catch { return (-1, "") }
		let data = out.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return (process.terminationStatus, String(decoding: data, as: UTF8.self))
	}

	/// every word on the page, with the box the parser drew around it.
	static func words(in url: URL) -> [Word] {
		let xml = run(["pdftotext", "-bbox", url.path, "-"]).output
		let pattern = #/<word xMin="([0-9.]+)"[^>]*xMax="([0-9.]+)"[^>]*>([^<]*)<\/word>/# 
		return xml.matches(of: pattern).compactMap { match in
			guard let xMin = Double(match.1), let xMax = Double(match.2) else { return nil }
			return Word(xMin: xMin, xMax: xMax, text: String(match.3))
		}
	}

	/// the plain text the parser extracts.
	static func text(in url: URL) -> String {
		run(["pdftotext", url.path, "-"]).output
	}
}

@Suite("independent parser check", .enabled(if: Poppler.available))
struct IndependentRenderTests {
	/// write `document` to a scratch file the caller removes.
	private func write(_ document: PDFDocument) throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("letterpress-independent-\(UUID().uuidString).pdf")
		try Data(document.render()).write(to: url)
		return url
	}

	private func remove(_ url: URL) {
		try? FileManager.default.removeItem(at: url)
	}

	@Test("a bold run does not overlap the word the library places after it")
	func boldRunDoesNotOverlap() throws {
		// the original defect's signature: bold measured with the regular table,
		// so the next word was placed inside the bold one. the second mark is
		// placed at exactly the advance the library reports, so if that advance
		// is short the parser sees the boxes collide.
		let size = 10.5
		let font = Font.helveticaBold
		let lead = "zero-dependency"
		let start = 40.0
		let offset = font.width(of: lead, size: size) + 2.92
		let url = try write(PDFDocument {
			PDFPage(.custom(width: 600, height: 200)) {
				Text(lead).font(font, size: size).at(x: start, y: 40)
				Text("markdown").font(.helvetica, size: size).at(x: start + offset, y: 40)
			}
		})
		defer { remove(url) }

		let words = Poppler.words(in: url)
		#expect(words.count == 2)
		guard words.count == 2 else { return }
		#expect(words[0].xMax <= words[1].xMin, "bold run overlaps the next word")
	}

	@Test("a cp1252 glyph run does not overlap the word after it")
	func glyphRunDoesNotOverlap() throws {
		// a flat non-ascii fallback measured the ellipsis at 556 when it draws
		// 1000, placing the next word hundreds of points inside the run.
		let size = 10.5
		let font = Font.helvetica
		let run = String(repeating: "\u{2026}", count: 30)
		let start = 40.0
		let space = font.width(of: " ", size: size)
		let url = try write(PDFDocument {
			PDFPage(.custom(width: 900, height: 200)) {
				Text(run).font(font, size: size).at(x: start, y: 40)
				Text("tail").font(font, size: size).at(x: start + font.width(of: run, size: size) + space, y: 40)
			}
		})
		defer { remove(url) }

		let words = Poppler.words(in: url)
		#expect(words.count == 2)
		guard words.count == 2 else { return }
		#expect(words[0].xMax <= words[1].xMin, "glyph run overlaps the next word")
		// and the run occupies its true advance: 30 ellipses at 10.5pt
		#expect(abs((words[0].xMax - start) - 30 * size) < 0.05)
		// the gap is exactly one space, so alignment maths stays honest
		#expect(abs((words[1].xMin - words[0].xMax) - space) < 0.05)
	}

	@Test("every glyph the library emits round-trips through the parser")
	func textRoundTrips() throws {
		let sample = "em\u{2014}dash and ellipsis\u{2026} and bullet \u{2022} and \u{201C}quotes\u{201D}"
		let url = try write(PDFDocument {
			PDFPage(.custom(width: 900, height: 200)) {
				Text(sample).font(.helvetica, size: 12).at(x: 20, y: 20)
			}
		})
		defer { remove(url) }

		let extracted = Poppler.text(in: url)
		for token in ["em\u{2014}dash", "ellipsis\u{2026}", "bullet \u{2022}", "\u{201C}quotes\u{201D}"] {
			#expect(extracted.contains(token), "\(token) did not survive the round trip")
		}
	}
}