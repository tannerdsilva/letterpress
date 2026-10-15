import Letterpress

// MARK: - MarkdownTypeface

/// the three base-14 families a markdown document draws from, each with its
/// four faces selected from the bold/italic bits an inline run carries.
public enum MarkdownTypeface: String, Sendable, Hashable, CaseIterable {
	/// Helvetica.
	case sans
	/// Times.
	case serif
	/// Courier.
	case mono

	/// the font face for the given emphasis.
	public func font(bold: Bool, italic: Bool) -> Font {
		switch self {
		case .sans:
			return bold ? (italic ? .helveticaBoldOblique : .helveticaBold)
				: (italic ? .helveticaOblique : .helvetica)
		case .serif:
			return bold ? (italic ? .timesBoldItalic : .timesBold)
				: (italic ? .timesItalic : .times)
		case .mono:
			return bold ? (italic ? .courierBoldOblique : .courierBold)
				: (italic ? .courierOblique : .courier)
		}
	}
}

// MARK: - Gap

/// a blank spacer of a fixed size, used to bake markdown rhythm (space before a
/// heading, between list items, around a rule) into a block's own height.
struct Gap: Mark {
	var width: Double
	var height: Double

	init(width: Double = 0, height: Double = 0) {
		self.width = width
		self.height = height
	}

	func write(to renderer: inout Renderer) {}

	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: width, height: height)
	}
}

// MARK: - TrackingModifier

/// sets pdf character spacing (`Tc`) around the wrapped text, so a small
/// uppercase label reads as set rather than typed. text state is part of the
/// graphics state, so the `q`/`Q` pair restores the previous spacing.
struct TrackingModifier: MarkModifier {
	/// the extra advance added after every character, in points.
	let amount: Double
	/// how many characters the wrapped text draws, for measurement.
	let characters: Int

	func apply<Content: Mark>(content: Content, to renderer: inout Renderer) {
		renderer.append("q\n")
		renderer.append("\(PDFNumber(amount)) Tc\n")
		content.write(to: &renderer)
		renderer.append("Q\n")
	}

	/// the wrapped text measures without tracking; add the advance `Tc` draws.
	func sizeThatFits<Content: Mark>(
		content: Content, proposal: ProposedSize, in context: inout MeasureContext
	) -> Size {
		var size = content.sizeThatFits(proposal, in: &context)
		size.width += amount * Double(max(characters - 1, 0))
		return size
	}
}

// MARK: - RichText

/// a run list laid out as wrapped, styled lines.
///
/// takes its column width up front rather than reading an ambient proposal,
/// which keeps measurement and drawing reading the same number. each laid-out
/// word becomes an ordinary `Text` mark pinned with `.at`, so the whole mark
/// composes from the exporter's public surface.
struct RichText: Mark {
	let runs: [InlineRun]
	let width: Double
	let size: Double
	let lineHeight: Double
	let typeface: MarkdownTypeface
	let codeTypeface: MarkdownTypeface
	let color: Color
	let linkColor: Color
	let codeColor: Color
	/// break a single word wider than the column instead of letting it run
	/// past the column edge. off by default (prose keeps its words whole);
	/// a table cell — where one long `file:line,line,line` token is common —
	/// turns it on so no cell text is ever silently clipped.
	var breaksLongWords: Bool = false
	/// extra advance added after every character, in points — the `Tc` a
	/// tracked label draws with. folded into the wrap so a tracked line
	/// measures and draws with the same word spaces.
	var tracking: Double = 0
	/// set prose flush to the measure. only the lines the wrap itself broke
	/// are opened out; a line a `\n` or the end of the paragraph closed stays
	/// ragged, and so does any line that would need more than
	/// `justificationLimit` times the natural word space.
	var justify: Bool = false
	/// the widest a justified word space may open, as a multiple of the
	/// natural advance. a line that would need more is left ragged.
	var justificationLimit: Double = 1.7

	/// one word placed on a line at `x` points from the column's left edge.
	struct Placed {
		let text: String
		let font: Font
		let color: Color
		let x: Double
		/// whether a space advance sits before this word — the only gaps
		/// justification is allowed to open.
		var gapBefore: Bool = false
		/// whether a rule is drawn through the word — `~~struck~~`.
		var struck: Bool = false
	}

	// MARK: layout

	/// the advance of `text` in this mark's face and size, including the
	/// tracking the wrap folds in after every character but the last.
	private func advance(_ text: String, _ font: Font) -> Double {
		font.width(of: text, size: size) + tracking * Double(max(text.count - 1, 0))
	}

	/// greedy word wrap over the run list; a `\n` run forces a fresh line.
	///
	/// the wrap bakes its refinements into the placed words themselves, so
	/// measurement and drawing read the same numbers: `tracking` opens both
	/// the glyphs and the word gap (a bare `Tc` widens only the glyphs, which
	/// runs tracked words together), and `justify` opens every line the wrap
	/// itself broke out to the measure — never a line a `\n` or the end of the
	/// paragraph closed.
	func lines() -> [[Placed]] {
		var result: [[Placed]] = []
		var broke: [Bool] = []
		var current: [Placed] = []
		var x = 0.0
		var pendingSpace = false
		let spaceWidth = typeface.font(bold: false, italic: false).width(of: " ", size: size) + tracking

		func flushLine(_ overflowed: Bool) {
			result.append(current)
			broke.append(overflowed)
			current = []
			x = 0
			pendingSpace = false
		}

		for run in runs {
			if run.text == "\n" {
				flushLine(false)
				continue
			}
			let font = font(for: run)
			let paint = paint(for: run)
			let struck = run.traits.contains(.strikethrough)
			var word = ""

			func place() {
				guard !word.isEmpty else { return }
				let wordWidth = advance(word, font)
				var gap = 0.0
				if !current.isEmpty, pendingSpace { gap = spaceWidth }
				// a lone punctuation mark hangs past the column edge rather
				// than opening a line: a line ending in `.` or `:` reads far
				// better than one beginning with it.
				let hangs = word.count == 1 && word.first.map { ".,;:!?…".contains($0) } == true
				if !current.isEmpty, !hangs, x + gap + wordWidth > width {
					flushLine(true)
					gap = 0
				}
				if hangs || !breaksLongWords || x + gap + wordWidth <= width {
					let px = x + gap
					current.append(Placed(
						text: word, font: font, color: paint, x: px, gapBefore: gap > 0,
						struck: struck))
					x = px + wordWidth
					pendingSpace = false
					word = ""
					return
				}
				// the word alone is wider than the whole line: break it into
				// chunks that fit, preferring a break after punctuation, so the
				// cell grows instead of clipping.
				let characters = Array(word)
				var start = 0
				var first = true
				while start < characters.count {
					let px = first ? x + gap : 0
					let available = max(width - px, 1)
					let end = chunkEnd(characters, from: start, available: available, font: font)
					let chunk = String(characters[start ..< end])
					let chunkWidth = advance(chunk, font)
					current.append(Placed(
						text: chunk, font: font, color: paint, x: px, gapBefore: first && gap > 0,
						struck: struck))
					x = px + chunkWidth
					start = end
					first = false
					if start < characters.count { flushLine(true) }
				}
				pendingSpace = false
				word = ""
			}

			for character in run.text {
				if character == " " || character == "\t" {
					place()
					if !current.isEmpty { pendingSpace = true }
				} else {
					word.append(character)
				}
			}
			place()
		}

		if !current.isEmpty {
			result.append(current)
			// the closing line was never broken by the wrap, so it is never
			// justified — it keeps the paragraph's ragged last line.
			broke.append(false)
		}
		guard justify else { return result }
		return justified(result, broke: broke, spaceWidth: spaceWidth)
	}

	/// open each wrap-broken line out to the measure, up to the stretch
	/// limit. a line with no open gap, or one whose residual would open the
	/// space past the limit, is returned ragged — the whole point being that
	/// a stretched line must never look worse than an uneven edge.
	private func justified(_ lines: [[Placed]], broke: [Bool], spaceWidth: Double) -> [[Placed]] {
		let maxExtra = spaceWidth * (max(justificationLimit, 1) - 1)
		var result: [[Placed]] = []
		result.reserveCapacity(lines.count)
		for (index, line) in lines.enumerated() {
			guard broke[index], !line.isEmpty else { result.append(line); continue }
			let extent = line.map { $0.x + advance($0.text, $0.font) }.max() ?? 0
			let residual = width - extent
			let gaps = line.reduce(0) { $0 + ($1.gapBefore ? 1 : 0) }
			guard gaps > 0, residual > 0.01, residual / Double(gaps) <= maxExtra else {
				result.append(line)
				continue
			}
			let share = residual / Double(gaps)
			var shift = 0.0
			result.append(line.map { placed in
				if placed.gapBefore { shift += share }
				return Placed(
					text: placed.text, font: placed.font, color: placed.color,
					x: placed.x + shift, gapBefore: placed.gapBefore, struck: placed.struck)
			})
		}
		return result
	}

	/// the end index of the longest run of `characters` from `start` that fits
	/// `available` points, backing up to a boundary inside the run so a long
	/// unbreakable token reads in sensible pieces rather than snapping wherever
	/// the measure happened to run out.
	///
	/// a path or word separator is the best break and is preferred. failing one,
	/// an identifier still breaks at its own camelCase hump: `WebSocketProtocol`
	/// run out of measure reads as `WebSocket` / `Protocol`, which is legible,
	/// where `WebSocketProtoco` / `l` is not.
	private func chunkEnd(_ characters: [Character], from start: Int, available: Double, font: Font) -> Int {
		var end = start
		var width = 0.0
		while end < characters.count {
			let characterWidth = font.width(of: String(characters[end]), size: size)
			if end > start, width + characterWidth > available { break }
			width += characterWidth
			end += 1
		}
		if end == start { end = start + 1 }
		guard end < characters.count else { return end }
		// a separator first, then a hump, each taking the last one in reach —
		// the longest first piece, and so the fewest pieces.
		for prefersSeparator in [true, false] {
			var boundary = start
			for index in (start + 1) ... end where Self.isBreak(characters, at: index, separator: prefersSeparator) {
				boundary = index
			}
			if boundary >= start + 2 { return boundary }
		}
		return end
	}

	/// whether a line may break immediately after this character.
	private static func breaksAfter(_ character: Character) -> Bool {
		switch character {
		case "/", ".", ":", ",", ";", "-", "_", ")", "(": return true
		default: return false
		}
	}

	/// whether a line may break at `index`: after a separator, or — when
	/// `separator` is false — at a camelCase hump, where an identifier's own
	/// word boundary falls.
	private static func isBreak(_ characters: [Character], at index: Int, separator: Bool) -> Bool {
		let before = characters[index - 1]
		if separator { return breaksAfter(before) }
		return before.isLowercase && characters[index].isUppercase
	}

	private func font(for run: InlineRun) -> Font {
		let bold = run.traits.contains(.bold)
		let italic = run.traits.contains(.italic)
		if run.traits.contains(.code) {
			return codeTypeface.font(bold: bold, italic: italic)
		}
		return typeface.font(bold: bold, italic: italic)
	}

	private func paint(for run: InlineRun) -> Color {
		if run.url != nil { return linkColor }
		if run.traits.contains(.code) { return codeColor }
		return color
	}

	// MARK: Mark

	func write(to renderer: inout Renderer) {
		emitPlaced(lines(), size: size, lineHeight: lineHeight, tracking: tracking, renderer: &renderer)
	}

	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: width, height: Double(lines().count) * size * lineHeight)
	}

	/// break between laid-out lines, so a long paragraph continues on the next
	/// page instead of overflowing. every word keeps its own font and paint,
	/// because a piece carries the placed words themselves.
	func split(available: Double, width: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)? {
		let laid = lines()
		let step = size * lineHeight
		guard let take = linesFitting(
			count: laid.count, available: available, lineHeight: step,
			orphans: 2, widows: 2) else { return nil }
		return (
			AnyMark(PlacedLines(lines: Array(laid[0..<take]), size: size, lineHeight: lineHeight, tracking: tracking)),
			AnyMark(PlacedLines(lines: Array(laid[take...]), size: size, lineHeight: lineHeight, tracking: tracking))
		)
	}
}

// MARK: - PlacedLines

/// already-laid-out rich-text lines — the piece a `RichText` split hands back.
///
/// it draws exactly the lines it was given, so a piece keeps every word's font
/// and colour, and it breaks again on the next page.
struct PlacedLines: Mark {
	let lines: [[RichText.Placed]]
	let size: Double
	let lineHeight: Double
	/// the tracking the run draws under; a piece must open its glyphs exactly
	/// as the run it came from did.
	var tracking: Double = 0

	func write(to renderer: inout Renderer) {
		emitPlaced(lines, size: size, lineHeight: lineHeight, tracking: tracking, renderer: &renderer)
	}

	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		var extent = 0.0
		for line in lines {
			for placed in line {
				let trailing = tracking * Double(max(placed.text.count - 1, 0))
				extent = max(extent, placed.x + placed.font.width(of: placed.text, size: size) + trailing)
			}
		}
		return Size(width: extent, height: Double(lines.count) * size * lineHeight)
	}

	func split(available: Double, width: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)? {
		guard let take = linesFitting(
			count: lines.count, available: available, lineHeight: size * lineHeight,
			orphans: 2, widows: 2) else { return nil }
		return (
			AnyMark(PlacedLines(lines: Array(lines[0..<take]), size: size, lineHeight: lineHeight, tracking: tracking)),
			AnyMark(PlacedLines(lines: Array(lines[take...]), size: size, lineHeight: lineHeight, tracking: tracking))
		)
	}
}

// MARK: - placed-line emission

/// draw one laid line with its origin at `(originX, lineTop)`: every word an
/// ordinary `Text` at its own anchor, then a rule for each struck stretch.
///
/// every consumer of laid lines draws through here — the flowing emitter and a
/// table cell alike — so a refinement to how a word is set reaches both, and a
/// run cannot be laid out one way and painted another.
private func drawPlacedLine(
	_ line: [RichText.Placed],
	originX: Double,
	lineTop: Double,
	size: Double,
	tracking: Double,
	renderer: inout Renderer
) {
	for placed in line {
		Text(placed.text)
			.font(placed.font, size: size)
			.foregroundColor(placed.color)
			.at(x: originX + placed.x, y: lineTop)
			.write(to: &renderer)
	}
	for span in strikeSpans(line, size: size, tracking: tracking) {
		Rect(
			x: originX + span.start, y: lineTop + size * strikeOffset,
			width: span.end - span.start, height: strikeThickness
		)
		.fill(span.color)
		.write(to: &renderer)
	}
}

/// the stretches of one laid line that carry a strike, as `(start, end, ink)`.
///
/// consecutive struck words join into a single stretch, the word spaces
/// between them included — a rule per word leaves every space unstruck and
/// reads as a dotted line rather than a strike. a word that is not struck
/// closes the stretch, so an unstruck word in the middle of a passage breaks
/// the rule exactly where the passage does.
private func strikeSpans(
	_ line: [RichText.Placed], size: Double, tracking: Double
) -> [(start: Double, end: Double, color: Color)] {
	var spans: [(start: Double, end: Double, color: Color)] = []
	var open: (start: Double, end: Double, color: Color)?
	for placed in line {
		let extent = placed.x + placed.font.width(of: placed.text, size: size)
			+ tracking * Double(max(placed.text.count - 1, 0))
		if placed.struck {
			if let current = open {
				open = (current.start, extent, current.color)
			} else {
				open = (placed.x, extent, placed.color)
			}
		} else if let closed = open {
			spans.append(closed)
			open = nil
		}
	}
	if let closed = open { spans.append(closed) }
	return spans
}

/// where a strike rule sits in the line box, as a fraction of the type size.
/// the renderer sets a baseline at 0.80 of the box; a strike sits a quarter of
/// an em above the baseline, which is where a struck passage wants it.
private let strikeOffset = 0.55

/// the struck rule's thickness in points — the hairline the set devices are
/// drawn with.
private let strikeThickness = 0.6

/// draw a laid-out line list: each word an ordinary `Text` at its own anchor,
/// under a `Tc` when the run carries tracking — so the glyphs open exactly the
/// way the wrap measured them.
private func emitPlaced(
	_ lines: [[RichText.Placed]],
	size: Double,
	lineHeight: Double,
	tracking: Double,
	renderer: inout Renderer
) {
	let tracked = tracking != 0
	if tracked {
		renderer.append("q\n")
		renderer.append("\(PDFNumber(tracking)) Tc\n")
	}
	for (index, line) in lines.enumerated() {
		drawPlacedLine(
			line, originX: 0, lineTop: Double(index) * size * lineHeight,
			size: size, tracking: tracking, renderer: &renderer)
	}
	if tracked { renderer.append("Q\n") }
}

// MARK: - Ornament

/// a thematic break as a set device: a hairline rule either side of a small
/// diamond in the accent ink, centred on the measure.
///
/// drawn from primitives rather than set from a glyph. the base-14 winansi set
/// carries no fleuron or asterism, so such a glyph in the source would
/// degrade to `?` — and a drawn device measures exactly and never depends on what a
/// reader happens to have installed.
struct Ornament: Mark {
	/// the width of the device itself, before it is centred.
	let span: Double
	/// the measure the device centres within.
	let columnWidth: Double
	/// the ink of the two rules.
	let ruleColor: Color
	/// the ink of the diamond.
	let accent: Color
	/// the diamond's half-diagonal, in points.
	let diamond: Double

	private var height: Double { diamond * 2 + 1 }
	private var left: Double { (columnWidth - span) / 2 }

	func write(to renderer: inout Renderer) {
		let half = span / 2
		let middle = height / 2
		let ruleLength = max(half - diamond - 4, 0)
		let ruleHeight = 0.6
		Rect(x: left, y: middle - ruleHeight / 2, width: ruleLength, height: ruleHeight)
			.fill(ruleColor)
			.write(to: &renderer)
		Rect(x: left + span - ruleLength, y: middle - ruleHeight / 2, width: ruleLength, height: ruleHeight)
			.fill(ruleColor)
			.write(to: &renderer)
		let centerX = left + half
		Polygon([
			Point(x: centerX, y: middle - diamond),
			Point(x: centerX + diamond, y: middle),
			Point(x: centerX, y: middle + diamond),
			Point(x: centerX - diamond, y: middle),
		]).fill(accent).write(to: &renderer)
	}

	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: columnWidth, height: height)
	}
}

// MARK: - TitleRule

/// the device under a document title: a hairline spanning the measure, with a
/// short, heavier accent segment at its leading end.
struct TitleRule: Mark {
	/// the measure the rule spans.
	let width: Double
	/// the length of the accent segment at the leading end.
	let accentLength: Double
	/// the ink of the accent segment.
	let accent: Color
	/// the ink of the hairline.
	let hairline: Color

	private var height: Double { 1.6 }

	func write(to renderer: inout Renderer) {
		Rect(x: 0, y: 0, width: width, height: 0.6).fill(hairline).write(to: &renderer)
		Rect(x: 0, y: 0, width: min(accentLength, width), height: height).fill(accent).write(to: &renderer)
	}

	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: width, height: height)
	}
}

// MARK: - CodeBlock

/// a fenced code block: a tinted panel of monospaced lines, hard-wrapped at
/// the panel width (monospace makes the character count exact).
struct CodeBlock: Mark {
	let text: String
	let width: Double
	let codeTypeface: MarkdownTypeface
	let size: Double
	let color: Color
	let background: Color
	/// the accent edge bar painted down the panel's leading side.
	let accent: Color

	private static let edgeWidth: Double = 3
	private static let insetLeft: Double = 14
	private static let insetRight: Double = 10
	private static let insetY: Double = 9
	private var lineHeight: Double { size * 1.45 }
	private var charWidth: Double { codeTypeface.font(bold: false, italic: false).width(of: "0", size: size) }
	private var charactersPerLine: Int {
		max(Int(max(width - Self.insetLeft - Self.insetRight, 1) / max(charWidth, 0.001)), 1)
	}

	/// the size `text` should set at inside a panel `width` wide: the preferred
	/// size, shrunk just enough for its longest line to fit, or the preferred
	/// size again when even `minimum` cannot hold that line — a block that has
	/// to wrap anyway loses nothing by keeping the full size.
	///
	/// without this, a line one character over the panel width becomes a full
	/// line plus an orphan fragment, and in a monospaced panel a fragment reads
	/// as a broken identifier rather than as a wrap.
	static func fittingSize(
		text: String,
		width: Double,
		preferred: Double,
		minimum: Double,
		codeTypeface: MarkdownTypeface
	) -> Double {
		let usable = max(width - insetLeft - insetRight, 1)
		let font = codeTypeface.font(bold: false, italic: false)
		let widest = text.split(separator: "\n", omittingEmptySubsequences: false)
			.map { font.width(of: String($0), size: preferred) }
			.max() ?? 0
		guard widest > usable else { return preferred }
		let scaled = preferred * (usable - 0.01) / widest
		guard scaled >= minimum else { return preferred }
		// two decimals keeps the emitted size tidy and still holds the line.
		return (scaled * 100).rounded(.down) / 100
	}

	private func wrapped() -> [String] {
		var out: [String] = []
		for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
			let string = String(line)
			if string.isEmpty {
				out.append("")
				continue
			}
			var start = string.startIndex
			while start < string.endIndex {
				let end = string.index(start, offsetBy: charactersPerLine, limitedBy: string.endIndex) ?? string.endIndex
				out.append(String(string[start ..< end]))
				start = end
			}
		}
		return out
	}

	private var height: Double {
		Self.insetY * 2 + Double(wrapped().count) * lineHeight
	}

	func write(to renderer: inout Renderer) {
		let lines = wrapped()
		let boxHeight = Self.insetY * 2 + Double(lines.count) * lineHeight
		Rect(x: 0, y: 0, width: width, height: boxHeight).fill(background).write(to: &renderer)
		Rect(x: 0, y: 0, width: Self.edgeWidth, height: boxHeight).fill(accent).write(to: &renderer)
		let font = codeTypeface.font(bold: false, italic: false)
		for (index, line) in lines.enumerated() {
			Text(line)
				.font(font, size: size)
				.foregroundColor(color)
				.at(x: Self.insetLeft, y: Self.insetY + Double(index) * lineHeight)
				.write(to: &renderer)
		}
	}

	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: width, height: height)
	}

	/// break between wrapped lines, so a code block longer than a page
	/// continues instead of overflowing. each piece keeps its own tinted
	/// panel, so both read as the same block.
	func split(available: Double, width: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)? {
		let lines = wrapped()
		let usable = available - Self.insetY * 2
		guard usable > 0, let take = linesFitting(
			count: lines.count, available: usable, lineHeight: lineHeight,
			orphans: 1, widows: 1) else { return nil }
		return (
			AnyMark(panel(lines[0..<take])),
			AnyMark(panel(lines[take...]))
		)
	}

	private func panel(_ lines: ArraySlice<String>) -> CodeBlock {
		CodeBlock(
			text: lines.joined(separator: "\n"),
			width: width,
			codeTypeface: codeTypeface,
			size: size,
			color: color,
			background: background,
			accent: accent
		)
	}
}

// MARK: - Quote

/// a block quote: a tinted bar beside the quoted blocks.
///
/// breakable — it splits its quoted content and redraws the bar for the piece
/// that fits, so a quote longer than a page continues with its bar intact
/// instead of overflowing.
struct Quote: Mark {
	let children: [any Mark]
	let barWidth: Double
	let indent: Double
	let color: Color
	let trailing: Double

	private var body: VStack {
		VStack(alignment: .leading, spacing: 0) { children }
	}

	/// the whole quote — bar, quoted content, trailing rhythm — assembled from
	/// the pieces, so measurement and drawing agree by construction.
	private func assembled(in context: inout MeasureContext) -> any Mark {
		let extent = body.sizeThatFits(ProposedSize(width: nil, height: nil), in: &context)
		return VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .top, spacing: 0) {
				Rect(x: 0, y: 0, width: barWidth, height: extent.height).fill(color)
				Gap(width: max(indent - barWidth, 0))
				body
			}
			Gap(height: trailing)
		}
	}

	func write(to renderer: inout Renderer) {
		var context = MeasureContext(text: renderer.text)
		assembled(in: &context).write(to: &renderer)
	}

	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		var local = context
		let size = assembled(in: &local).sizeThatFits(proposal, in: &context)
		return size
	}

	func split(available: Double, width: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)? {
		let bodyWidth = max(width - indent, 1)
		guard let pieces = body.split(available: available, width: bodyWidth, in: &context) else {
			return nil
		}
		// the piece that fits keeps the bar but not the trailing rhythm (the
		// page ends there); the runover keeps both.
		return (
			AnyMark(Quote(children: [pieces.fits], barWidth: barWidth, indent: indent, color: color, trailing: 0)),
			AnyMark(Quote(children: [pieces.runover], barWidth: barWidth, indent: indent, color: color, trailing: trailing))
		)
	}
}

// MARK: - TableMark

/// a pipe table: a tinted header band, a rule beneath it, body rows with thin
/// separators, and light column dividers.
///
/// cells wrap through the same measured wrap `RichText` uses (word by word,
/// per-cell font and colour), so a cell grows its row rather than overflowing.
/// breakable between body rows: a table taller than a page continues on the
/// next with its header repeated. a single row taller than the space a page
/// has left breaks at a cell line boundary instead of being clipped, so a
/// table no longer loses content to one outsized row; the paginator reports
/// only what still cannot fit — a row one line taller than the whole box.
struct TableMark: Mark {
	let header: TableRow
	let alignments: [TextAlignment]
	let rows: [TableRow]
	let width: Double
	let bodySize: Double
	let lineHeight: Double
	let typeface: MarkdownTypeface
	let codeTypeface: MarkdownTypeface
	let textColor: Color
	let linkColor: Color
	let codeColor: Color
	let headerBackground: Color
	let borderColor: Color
	/// the accent rule the header row sits on.
	let accentColor: Color
	let padding: Double

	/// the column geometry a split piece carries, so every page of one table
	/// shares one column set instead of re-deriving it from whichever rows
	/// happened to land on that page.
	var laidColumns: [Double]? = nil
	/// body rows already wrapped, carried by a split piece so a break lands on
	/// exactly the lines the whole table would have drawn.
	var laidRows: [RowLayout]? = nil

	// MARK: layout model

	/// one laid-out row: the wrapped lines of each cell, and the row's height.
	struct RowLayout {
		let lines: [[[RichText.Placed]]]
		let height: Double
	}

	/// a fully computed table: column geometry plus every row's wrapped lines.
	private struct TableLayout {
		let columnX: [Double]
		let columnWidths: [Double]
		let header: RowLayout
		let rows: [RowLayout]
		var height: Double { header.height + rows.reduce(0) { $0 + $1.height } }
	}

	private var columnCount: Int { max(header.count, alignments.count, 1) }

	private func alignment(_ index: Int) -> TextAlignment {
		index < alignments.count ? alignments[index] : .leading
	}

	/// the alignment factor: 0 leading, 0.5 centre, 1 trailing.
	private func factor(_ alignment: TextAlignment) -> Double {
		switch alignment {
		case .leading: return 0
		case .center: return 0.5
		case .trailing: return 1
		}
	}

	private func font(for run: InlineRun, bold: Bool) -> Font {
		let bold = bold || run.traits.contains(.bold)
		let italic = run.traits.contains(.italic)
		if run.traits.contains(.code) {
			return codeTypeface.font(bold: bold, italic: italic)
		}
		return typeface.font(bold: bold, italic: italic)
	}

	/// the single-line width of a cell, for sizing its column.
	private func naturalWidth(_ runs: [InlineRun], bold: Bool) -> Double {
		runs.reduce(0) { total, run in
			total + font(for: run, bold: bold).width(of: run.text, size: bodySize)
		}
	}

	/// the widest single token in a cell that cannot break inside itself, for
	/// the column's floor.
	///
	/// the wrap breaks a token only when the column is narrower than the token,
	/// so a column at least as wide as its widest token never wraps one — which
	/// is what keeps a three-character id (`T13`) from setting as `T1` / `3`.
	private func widestToken(_ runs: [InlineRun], bold: Bool) -> Double {
		var widest = 0.0
		for run in runs where run.text != "\n" {
			let font = font(for: run, bold: bold)
			for token in run.text.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
				widest = max(widest, font.width(of: String(token), size: bodySize))
			}
		}
		return widest
	}

	/// the wrapped lines of one cell, through the same wrap `RichText` uses.
	private func laidOut(_ runs: [InlineRun], columnWidth: Double, bold: Bool) -> [[RichText.Placed]] {
		let styled = bold
			? runs.map { InlineRun($0.text, traits: $0.traits.union(.bold), url: $0.url) }
			: runs
		return RichText(
			runs: styled,
			width: max(columnWidth, 1),
			size: bodySize,
			lineHeight: lineHeight,
			typeface: typeface,
			codeTypeface: codeTypeface,
			color: textColor,
			linkColor: linkColor,
			codeColor: codeColor,
			breaksLongWords: true
		).lines()
	}

	/// column widths including padding: proportional to content, capped so one
	/// wide cell cannot starve its neighbours, then dilated to fill the column.
	private func columnWidths(inWidth width: Double) -> [Double] {
		let count = columnCount
		var natural = [Double](repeating: 0, count: count)
		var tokens = [Double](repeating: 0, count: count)
		for (column, cell) in header.enumerated() where column < count {
			natural[column] = max(natural[column], naturalWidth(cell, bold: true))
			tokens[column] = max(tokens[column], widestToken(cell, bold: true))
		}
		for row in rows {
			for (column, cell) in row.enumerated() where column < count {
				natural[column] = max(natural[column], naturalWidth(cell, bold: false))
				tokens[column] = max(tokens[column], widestToken(cell, bold: false))
			}
		}
		natural = natural.map { $0 + 2 * padding }

		let cap = width * 0.6
		var widths = natural.map { min($0, cap) }
		let total = widths.reduce(0, +)

		if total > width, total > 0 {
			// the capped naturals are wider than the column: shrink them all
			// proportionally so the table never runs past the page edge.
			let scale = width / total
			widths = widths.map { $0 * scale }
		} else {
			var remaining = width - total
			var rounds = 0
			while remaining > 0.5, rounds < 64 {
				rounds += 1
				let free = widths.indices.filter { widths[$0] < width - 0.01 }
				guard !free.isEmpty else { break }
				let share = remaining / Double(free.count)
				var progressed = false
				for index in free {
					let add = min(share, max(width - widths[index], 0))
					if add > 0.01 {
						widths[index] += add
						remaining -= add
						progressed = true
					}
				}
				if !progressed { break }
			}
		}
		return floored(widths, inWidth: width, tokens: tokens)
	}

	/// raise every column to a working minimum so a short cell (`C1`, `#`)
	/// cannot collapse and break mid-token; the difference comes off the
	/// wider columns, in proportion to their width.
	///
	/// the minimum is the column's own widest unbreakable token, so a column
	/// wide enough to set its token whole keeps it whole. it is capped at an
	/// equal share of the table, because a token wider than that must break
	/// somewhere and starving the neighbouring columns is the worse evil. if
	/// the raised floors no longer fit, the set is scaled back rather than let
	/// the table run past the page edge.
	private func floored(_ widths: [Double], inWidth width: Double, tokens: [Double]) -> [Double] {
		let count = max(widths.count, 1)
		let share = width / Double(count)
		let base = min(30, share)
		var minimums = [Double](repeating: base, count: count)
		for index in minimums.indices where index < tokens.count {
			// the half point is slack for the wrap's own comparison, so a
			// column exactly as wide as its token does not break it.
			minimums[index] = max(base, min(tokens[index] + 2 * padding + 0.5, share))
		}
		var result = widths
		var deficit = 0.0
		for index in result.indices where result[index] < minimums[index] {
			deficit += minimums[index] - result[index]
			result[index] = minimums[index]
		}
		if deficit > 0 {
			let donors = result.indices.filter { result[$0] > minimums[$0] + 0.01 }
			let donorTotal = donors.reduce(0.0) { $0 + result[$1] }
			if donorTotal > 0 {
				let snapshot = result
				for index in donors {
					result[index] = snapshot[index] - deficit * (snapshot[index] / donorTotal)
				}
			}
		}
		let total = result.reduce(0, +)
		guard total > width, total > 0 else { return result }
		return result.map { $0 * (width / total) }
	}

	private func layout(inWidth width: Double) -> TableLayout {
		let widths = laidColumns ?? columnWidths(inWidth: width)
		var columnX: [Double] = []
		var cursor = 0.0
		for columnWidth in widths {
			columnX.append(cursor)
			cursor += columnWidth
		}
		let contentWidths = widths.map { max($0 - 2 * padding, 1) }

		func row(_ cells: TableRow, bold: Bool) -> RowLayout {
			var lines: [[[RichText.Placed]]] = []
			var lineCount = 1
			for (column, contentWidth) in contentWidths.enumerated() {
				let runs = column < cells.count ? cells[column] : []
				let laid = laidOut(runs, columnWidth: contentWidth, bold: bold)
				lines.append(laid)
				lineCount = max(lineCount, laid.count)
			}
			let height = Double(lineCount) * bodySize * lineHeight + 2 * padding
			return RowLayout(lines: lines, height: height)
		}

		return TableLayout(
			columnX: columnX,
			columnWidths: widths,
			header: row(header, bold: true),
			rows: laidRows ?? rows.map { row($0, bold: false) }
		)
	}

	// MARK: Mark

	func write(to renderer: inout Renderer) {
		let model = layout(inWidth: width)
		Rect(x: 0, y: 0, width: width, height: model.header.height)
			.fill(headerBackground)
			.write(to: &renderer)

		var y = 0.0
		draw(model.header, at: y, model: model, renderer: &renderer)
		y += model.header.height
		// the header sits on an accent rule and the body rows are separated
		// by hairlines only — no vertical grid, so the table reads as text
		// rather than as a spreadsheet.
		Line(from: Point(x: 0, y: y), to: Point(x: width, y: y))
			.stroke(accentColor, width: 1.2)
			.write(to: &renderer)

		for row in model.rows {
			draw(row, at: y, model: model, renderer: &renderer)
			y += row.height
			Line(from: Point(x: 0, y: y), to: Point(x: width, y: y))
				.stroke(borderColor, width: 0.5)
				.write(to: &renderer)
		}
	}

	private func draw(_ row: RowLayout, at top: Double, model: TableLayout, renderer: inout Renderer) {
		for (column, lines) in row.lines.enumerated() {
			let contentWidth = max(model.columnWidths[column] - 2 * padding, 1)
			let originX = model.columnX[column] + padding
			let factor = factor(alignment(column))
			for (lineIndex, line) in lines.enumerated() {
				let lineWidth = line.map { $0.x + $0.font.width(of: $0.text, size: bodySize) }.max() ?? 0
				let offset = (contentWidth - lineWidth) * factor
				drawPlacedLine(
					line, originX: originX + offset,
					lineTop: top + padding + Double(lineIndex) * bodySize * lineHeight,
					size: bodySize, tracking: 0, renderer: &renderer)
			}
		}
	}

	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: width, height: layout(inWidth: width).height)
	}

	/// break the table so the fitting piece occupies at most `available` points
	/// at `width`, repeating the header on the runover.
	///
	/// the break lands between body rows when it can. when it cannot — a single
	/// row is taller than the space the page has left — that row is split at a
	/// cell line boundary instead: a row is only unbreakable until the
	/// alternative is losing it. `nil` only when nothing can be made to fit, so
	/// the paginator can still report what it places whole.
	func split(available: Double, width splitWidth: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)? {
		let model = layout(inWidth: splitWidth)
		guard !model.rows.isEmpty, model.header.height < available else { return nil }

		var used = model.header.height
		var take = 0
		for row in model.rows {
			if used + row.height <= available + 0.001 {
				used += row.height
				take += 1
			} else {
				break
			}
		}

		// whole rows fit below the header and rows remain: break between them.
		if take >= 1, take < model.rows.count {
			return piecePair(
				head: Array(model.rows[0 ..< take]),
				tail: Array(model.rows[take...]),
				columns: model.columnWidths,
				width: splitWidth)
		}
		// every row fits: there is nothing to break.
		guard take == 0 else { return nil }

		// not one whole row fits below the header, because the first row is
		// taller than the box. split that row and carry the rest of it into the
		// runover behind the repeated header, rather than clipping it.
		guard let pieces = splitRow(model.rows[0], into: available - model.header.height) else {
			return nil
		}
		var tail = [pieces.tail]
		tail.append(contentsOf: model.rows.dropFirst())
		return piecePair(head: [pieces.head], tail: tail, columns: model.columnWidths, width: splitWidth)
	}

	/// split one laid row so its head fits `room` points: the leading lines of
	/// every cell stay and the rest travel on. `nil` when the row cannot
	/// usefully break — not one line fits, or the break would leave nothing.
	private func splitRow(_ row: RowLayout, into room: Double) -> (head: RowLayout, tail: RowLayout)? {
		let lineStep = bodySize * lineHeight
		let capacity = Int((((room - 2 * padding) / lineStep) + 1e-9).rounded(.down))
		let total = row.lines.map(\.count).max() ?? 0
		let take = min(capacity, total - 1)
		guard take >= 1, take < total else { return nil }
		let extent = { (lines: Int) in Double(lines) * lineStep + 2 * self.padding }
		return (
			RowLayout(lines: row.lines.map { Array($0.prefix(take)) }, height: extent(take)),
			RowLayout(lines: row.lines.map { Array($0.dropFirst(take)) }, height: extent(total - take))
		)
	}

	/// the two halves of a split, each carrying the geometry the whole table
	/// was laid out with, so the columns line up across the break.
	private func piecePair(
		head: [RowLayout], tail: [RowLayout], columns: [Double], width: Double
	) -> (fits: AnyMark, runover: AnyMark) {
		(
			AnyMark(piece(laid: head, columns: columns, width: width)),
			AnyMark(piece(laid: tail, columns: columns, width: width))
		)
	}

	private func piece(laid rows: [RowLayout], columns: [Double], width: Double) -> TableMark {
		TableMark(
			header: header,
			alignments: alignments,
			rows: [],
			width: width,
			bodySize: bodySize,
			lineHeight: lineHeight,
			typeface: typeface,
			codeTypeface: codeTypeface,
			textColor: textColor,
			linkColor: linkColor,
			codeColor: codeColor,
			headerBackground: headerBackground,
			borderColor: borderColor,
			accentColor: accentColor,
			padding: padding,
			laidColumns: columns,
			laidRows: rows
		)
	}
}