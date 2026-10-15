import Foundation
import Testing
import Letterpress
import LetterpressMarkdown

// where the glyphs actually landed, asked of a parser we did not write.
//
// the layer's own tests agree with its own arithmetic, so the two properties
// that depend on cross-mark alignment — a list marker against its item's
// baseline, and a hanging punctuation mark against the line it closes — are
// measured out of the artifact instead.
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

	/// one word and the box the parser drew around it.
	struct Word {
		let xMin: Double
		let yMin: Double
		let xMax: Double
		let yMax: Double
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
		let pattern = #/<word xMin="([0-9.]+)" yMin="([0-9.]+)" xMax="([0-9.]+)" yMax="([0-9.]+)">([^<]*)<\/word>/# 
		return xml.matches(of: pattern).compactMap { match in
			guard let xMin = Double(match.1), let yMin = Double(match.2),
			      let xMax = Double(match.3), let yMax = Double(match.4)
			else { return nil }
			return Word(xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax, text: String(match.5))
		}
	}

	/// the plain text the parser extracts.
	static func text(in url: URL) -> String {
		run(["pdftotext", url.path, "-"]).output
	}
}

@Suite("markdown visual check", .enabled(if: Poppler.available))
struct MarkdownVisualTests {
	/// write `document` to a scratch file the caller removes.
	private func write(_ document: MarkdownDocument, style: MarkdownStyle = .standard) throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("letterpress-markdown-\(UUID().uuidString).pdf")
		try Data(document.render(style: style)).write(to: url)
		return url
	}

	@Test("the bullet glyph sits on its item's baseline, not below it")
	func bulletOnBaseline() throws {
		// the shipped bullet is set at 1.15 × the body size, and a larger size
		// draws its baseline lower on the line; the layer lifts it back. if the
		// lift is dropped the two baselines separate by ~1.3pt.
		let url = try write(MarkdownDocument(parsing: "- alpha beta\n- gamma delta"))
		defer { try? FileManager.default.removeItem(at: url) }

		let words = Poppler.words(in: url)
		guard let bullet = words.first(where: { $0.text == "\u{2022}" }),
		      let first = words.first(where: { $0.text == "alpha" })
		else {
			Issue.record("the parser did not report both the bullet and its item")
			return
		}

		// poppler reports the font box, not the ink: the box runs from ascent
		// to descent, so the baseline sits the face's own ascender below the
		// top — 0.683 em for Times, 0.718 for Helvetica. both the bullet and
		// its item set in the body face.
		let style = MarkdownStyle.standard
		let ascent: Double = style.typeface == .serif ? 0.683 : 0.718
		let body = style.bodySize
		let bulletBaseline = bullet.yMin + ascent * body * 1.15
		let textBaseline = first.yMin + ascent * body
		#expect(
			abs(bulletBaseline - textBaseline) < 0.05,
			"the bullet sits \(bulletBaseline - textBaseline)pt off its item's baseline")
	}

	@Test("a lone punctuation mark closes a line instead of opening one")
	func hangingPunctuation() throws {
		// the defect: a bold run fills the measure, the punctuation closing it
		// cannot fit, and the mark opens a line alone. the fixture is built
		// from the shipped metrics so it provably lands on that wrap point
		// instead of merely happening to.
		let style = MarkdownStyle.standard
		let size = style.bodySize
		let measure = style.contentWidth
		let filler = "aa"
		let bold = "n"
		// the fixture is built from the theme's own faces, so it provably
		// lands on the wrap point whatever the body typeface is.
		let body = style.typeface.font(bold: false, italic: false)
		let boldFace = style.typeface.font(bold: true, italic: false)
		let space = body.width(of: " ", size: size)
		let colon = body.width(of: ":", size: size)

		var source: String?
		for letters in 1 ... 200 {
			let run = Double(letters) * boldFace.width(of: bold, size: size)
			// the greedy fill: the most filler tokens that still leave the run
			// room on the same line.
			var fillers = 0
			var line = 0.0
			while fillers < 400 {
				let next = line + (fillers == 0 ? 0 : space) + body.width(of: filler, size: size)
				guard next + space + run <= measure else { break }
				fillers += 1
				line = next
			}
			guard fillers >= 1 else { continue }
			let filled = line + space + run
			// the bold run closes the line, and the colon does not fit after it.
			if filled <= measure, filled + colon > measure {
				let prefix = Array(repeating: filler, count: fillers).joined(separator: " ")
				source = "\(prefix) **\(String(repeating: bold, count: letters))**:"
				break
			}
		}
		guard let source else {
			Issue.record("no filler lands the punctuation at the wrap point")
			return
		}

		let url = try write(MarkdownDocument(parsing: source))
		defer { try? FileManager.default.removeItem(at: url) }

		let extracted = Poppler.text(in: url)
		for line in extracted.split(separator: "\n", omittingEmptySubsequences: false) {
			#expect(!line.hasPrefix(":"), "a colon opened a line: \"\(line)\"")
		}
		// and the mark stayed with the text it closes rather than vanishing.
		#expect(extracted.contains(":"), "the colon was dropped entirely")
	}

	@Test("the folio sits below the content box, clear of the last line")
	func folioClearsContent() throws {
		let paragraph = String(repeating: "the quick brown fox jumps over the lazy dog. ", count: 24)
		let document = MarkdownDocument(parsing: (1 ... 3).map { "## Section \($0)\n\n\(paragraph)" }
			.joined(separator: "\n\n"))
		let url = try write(document)
		defer { try? FileManager.default.removeItem(at: url) }

		let words = Poppler.words(in: url)
		guard let folio = words.first(where: { $0.text == "/" }) else {
			Issue.record("the parser found no folio on the page")
			return
		}
		// poppler's y grows down from the page top, as does the theme's, so
		// the folio line must be the lowest word on the page.
		let lowest = words.map(\.yMax).max() ?? 0
		#expect(abs(folio.yMax - lowest) < 0.5, "content draws below the folio")
	}

	@Test("a tracked label keeps its word spaces open")
	func trackedLabelKeepsWordSpaces() throws {
		// the defect: a `Tc` widens the glyphs but not the gap between two
		// words, so a tracked uppercase label ran its words together —
		// `SMALLCAPSLABEL`. the wrap folds the tracking into the gap as well.
		let url = try write(MarkdownDocument(parsing: "##### small caps label\n\nbody"))
		defer { try? FileManager.default.removeItem(at: url) }

		let words = Poppler.words(in: url)
		guard let small = words.first(where: { $0.text == "SMALL" }),
		      let caps = words.first(where: { $0.text == "CAPS" })
		else {
			Issue.record("the parser did not report the label words")
			return
		}
		// the gap must carry the tracking the glyphs got, or the words close up.
		let style = MarkdownStyle.standard
		let face = style.headingTypeface.font(bold: true, italic: false)
		let expected = face.width(of: " ", size: style.headingSize(5)) + style.headingTracking(5)
		let gap = caps.xMin - small.xMax
		#expect(abs(gap - expected) < 0.05, "the label gap was \(gap)pt, expected \(expected)pt")
	}

	@Test("a justified paragraph opens every wrapped line to the measure")
	func justifiedToMeasure() throws {
		let paragraph = String(
			repeating: "the quick brown fox jumps over the lazy dog and runs on ", count: 8)
		let url = try write(MarkdownDocument(parsing: paragraph))
		defer { try? FileManager.default.removeItem(at: url) }

		let style = MarkdownStyle.standard
		let column = style.pageSize.width - style.margins.trailing
		let contentBottom = style.pageSize.height - style.margins.bottom
		let body = Poppler.words(in: url).filter { $0.yMax < contentBottom }

		var edges: [Double: Double] = [:]
		for word in body { edges[word.yMin] = max(edges[word.yMin] ?? 0, word.xMax) }
		let lines = edges.sorted { $0.key < $1.key }.map(\.value)
		#expect(lines.count > 3, "the fixture did not wrap into several lines")
		// every line but the paragraph's closing one is flush to the measure.
		let flush = lines.dropLast().filter { abs($0 - column) < 1.2 }.count
		#expect(flush == lines.count - 1, "\(flush) of \(lines.count - 1) lines reached the measure")
		// and the closing line is not stretched: it keeps its ragged end.
		#expect((lines.last ?? column) < column - 1, "the closing line was stretched")
	}
}