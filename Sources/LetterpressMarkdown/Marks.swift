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

	/// one word placed on a line at `x` points from the column's left edge.
	struct Placed {
		let text: String
		let font: Font
		let color: Color
		let x: Double
	}

	// MARK: layout

	/// greedy word wrap over the run list; a `\n` run forces a fresh line.
	func lines() -> [[Placed]] {
		var result: [[Placed]] = []
		var current: [Placed] = []
		var x = 0.0
		var pendingSpace = false
		let spaceWidth = typeface.font(bold: false, italic: false).width(of: " ", size: size)

		func flushLine() {
			result.append(current)
			current = []
			x = 0
			pendingSpace = false
		}

		for run in runs {
			if run.text == "\n" {
				flushLine()
				continue
			}
			let font = font(for: run)
			let paint = paint(for: run)
			var word = ""

			func place() {
				guard !word.isEmpty else { return }
				let wordWidth = font.width(of: word, size: size)
				var gap = 0.0
				if !current.isEmpty, pendingSpace { gap = spaceWidth }
				if !current.isEmpty, x + gap + wordWidth > width {
					flushLine()
					gap = 0
				}
				let px = x + gap
				current.append(Placed(text: word, font: font, color: paint, x: px))
				x = px + wordWidth
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

		if !current.isEmpty { result.append(current) }
		return result
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
		for (index, line) in lines().enumerated() {
			let top = Double(index) * size * lineHeight
			for placed in line {
				Text(placed.text)
					.font(placed.font, size: size)
					.foregroundColor(placed.color)
					.at(x: placed.x, y: top)
					.write(to: &renderer)
			}
		}
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
			AnyMark(PlacedLines(lines: Array(laid[0..<take]), size: size, lineHeight: lineHeight)),
			AnyMark(PlacedLines(lines: Array(laid[take...]), size: size, lineHeight: lineHeight))
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

	func write(to renderer: inout Renderer) {
		for (index, line) in lines.enumerated() {
			let top = Double(index) * size * lineHeight
			for placed in line {
				Text(placed.text)
					.font(placed.font, size: size)
					.foregroundColor(placed.color)
					.at(x: placed.x, y: top)
					.write(to: &renderer)
			}
		}
	}

	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		let extent = lines.flatMap { $0 }
			.map { $0.x + $0.font.width(of: $0.text, size: size) }
			.max() ?? 0
		return Size(width: extent, height: Double(lines.count) * size * lineHeight)
	}

	func split(available: Double, width: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)? {
		guard let take = linesFitting(
			count: lines.count, available: available, lineHeight: size * lineHeight,
			orphans: 2, widows: 2) else { return nil }
		return (
			AnyMark(PlacedLines(lines: Array(lines[0..<take]), size: size, lineHeight: lineHeight)),
			AnyMark(PlacedLines(lines: Array(lines[take...]), size: size, lineHeight: lineHeight))
		)
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

	private let padding: Double = 8
	private var lineHeight: Double { size * 1.4 }
	private var charWidth: Double { codeTypeface.font(bold: false, italic: false).width(of: "0", size: size) }
	private var charactersPerLine: Int { max(Int(max(width - padding * 2, 1) / max(charWidth, 0.001)), 1) }

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
		padding * 2 + Double(wrapped().count) * lineHeight
	}

	func write(to renderer: inout Renderer) {
		let lines = wrapped()
		let boxHeight = padding * 2 + Double(lines.count) * lineHeight
		Rect(x: 0, y: 0, width: width, height: boxHeight).fill(background).write(to: &renderer)
		let font = codeTypeface.font(bold: false, italic: false)
		for (index, line) in lines.enumerated() {
			Text(line)
				.font(font, size: size)
				.foregroundColor(color)
				.at(x: padding, y: padding + Double(index) * lineHeight)
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
		let usable = available - padding * 2
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
			background: background
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