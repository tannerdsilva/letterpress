import Letterpress

// MARK: - MarkdownTypeface

/// the three base-14 families a markdown document draws from, each with its
/// four faces selected from the bold/italic bits an inline run carries.
public enum MarkdownTypeface: String, Sendable, Hashable, CaseIterable {
	case sans
	case serif
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
}