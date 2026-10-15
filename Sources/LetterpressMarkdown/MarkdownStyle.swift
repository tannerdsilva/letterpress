import Letterpress

// MARK: - MarkdownStyle

/// the typographic theme a markdown document renders under.
///
/// one value type carries every knob — page geometry, typefaces, sizes,
/// colours, spacing — so a caller configures the whole look in one place and
/// the block composer reads it. sizes are in points; `lineHeight` is a
/// multiple of the font size.
///
/// the shipped default is a letterpress scheme: prose sets in a serif on a
/// measured column that holds a comfortable line on a page it actually
/// fills, structure sets in a sans
/// that never competes with it, and one accent ink is spent only where it
/// carries meaning — section rules, list markers, quote bars, table rules.
/// body prose sets flush (justified) with a stretch limit, so the column
/// reads as an even block without tearing into rivers; every separator is a
/// hairline, and a running folio rides the foot of every page.
public struct MarkdownStyle: Sendable {
	// page
	/// the physical page size.
	public var pageSize: PageSize
	/// the page margins.
	public var margins: Margins

	// type
	/// the body typeface.
	public var typeface: MarkdownTypeface
	/// the typeface headings set in. kept separate from `typeface` so prose
	/// and structure can carry different voices — a serif column under sans
	/// heads is the editorial pairing the default theme ships.
	public var headingTypeface: MarkdownTypeface
	/// the typeface for code spans and blocks.
	public var codeTypeface: MarkdownTypeface
	/// the body point size.
	public var bodySize: Double
	/// the body line-height multiple.
	public var lineHeight: Double
	/// whether body prose sets flush (justified) or ragged-right.
	public var justified: Bool
	/// the widest a justified word space may open, as a multiple of the
	/// natural advance. a line that would need more is left ragged: a short
	/// line stretched without limit tears the column into rivers, which
	/// reads far worse than a ragged edge.
	public var justificationLimit: Double

	// colour
	/// the body text color.
	public var textColor: Color
	/// the color headings below the accent level draw in.
	public var headingColor: Color
	/// secondary ink: the running folio, small labels.
	public var mutedColor: Color
	/// the single accent: section rules, list markers, quote bars, table rules.
	public var accentColor: Color
	/// the color of every hairline separator.
	public var hairlineColor: Color
	/// the color links paint in.
	public var linkColor: Color
	/// the inline and block code text color.
	public var codeColor: Color
	/// the code-block panel fill.
	public var codeBackground: Color
	/// the color quoted text draws in.
	public var quoteTextColor: Color

	// table
	/// the tint painted behind a table's header row.
	public var tableHeaderBackground: Color
	/// the padding inside every table cell, on all four sides.
	public var tableCellPadding: Double

	// rhythm
	/// the vertical gap before each block.
	public var blockSpacing: Double
	/// the vertical gap between list items.
	public var itemSpacing: Double
	/// the code point size.
	public var codeSize: Double
	/// the smallest a code panel may shrink to in order to fit its longest
	/// line. a block whose longest line cannot be held even here sets at
	/// `codeSize` and wraps.
	public var codeSizeFloor: Double
	/// the running-folio point size.
	public var folioSize: Double

	/// create the default theme; `.standard` is one of these.
	public init() {
		self.pageSize = .a4
		// the sheet is used rather than decorated with white: the margins are
		// a working gutter, not a frame, and leave a column that fills nearly
		// two thirds of the page. the measure they set holds a line near
		// eighty-five characters — the upper edge of what still reads without
		// the eye losing its place — taken deliberately, because this document
		// is table-heavy and a wider measure is what lets a table set without
		// wrapping every cell.
		self.margins = Margins(top: 62, leading: 78, bottom: 58, trailing: 78)

		self.typeface = .serif
		self.headingTypeface = .sans
		self.codeTypeface = .mono
		self.bodySize = 12.5
		self.lineHeight = 1.42
		self.justified = true
		self.justificationLimit = 1.7

		self.textColor = .ink
		self.headingColor = Color(hex: 0x0A0D12)
		self.mutedColor = Color(hex: 0x6B7280)
		self.accentColor = Color(hex: 0x1F4E79)
		self.hairlineColor = Color(hex: 0xD9DEE6)
		self.linkColor = Color(hex: 0x15549A)
		self.codeColor = Color(hex: 0x2B3440)
		self.codeBackground = Color(hex: 0xF4F6F9)
		self.quoteTextColor = Color(hex: 0x4B5563)

		self.tableHeaderBackground = Color(hex: 0xEEF2F7)
		self.tableCellPadding = 7

		self.blockSpacing = 12
		self.itemSpacing = 5.5
		self.codeSize = 11
		self.codeSizeFloor = 10
		self.folioSize = 8.5
	}

	/// the default theme.
	public static let standard = MarkdownStyle()

	/// the width of the text column: page width less the horizontal margins.
	public var contentWidth: Double {
		max(pageSize.width - margins.leading - margins.trailing, 1)
	}

	/// the display size for an `h1`...`h6`, scaled from the body size.
	public func headingSize(_ level: Int) -> Double {
		let scales: [Double] = [2.0, 1.32, 1.14, 1.0, 0.86, 0.86]
		return bodySize * scales[clamp(level) - 1]
	}

	/// the face a heading of `level` sets in — always the heading typeface,
	/// always bold: the source's own emphasis bits never lighten a head.
	public func headingFont(_ level: Int) -> Font {
		headingTypeface.font(bold: true, italic: false)
	}

	/// the ink a heading of `level` draws in: the accent for `h3` (the one
	/// head that carries the colour), the muted grey for the small uppercase
	/// `h5`/`h6` labels, heading ink otherwise.
	public func headingInk(_ level: Int) -> Color {
		switch clamp(level) {
		case 3: return accentColor
		case 5, 6: return mutedColor
		default: return headingColor
		}
	}

	/// whether a heading of `level` sets as a small uppercase label.
	public func headingUppercased(_ level: Int) -> Bool {
		clamp(level) >= 5
	}

	/// the character tracking a heading of `level` draws with — the display
	/// level is tightened, the uppercase labels are opened up.
	public func headingTracking(_ level: Int) -> Double {
		switch clamp(level) {
		case 1: return -0.35
		case 5, 6: return 0.6
		default: return 0
		}
	}

	/// the space above a heading of `level`, as a multiple of `blockSpacing`.
	public func headingSpaceAbove(_ level: Int) -> Double {
		let multiples: [Double] = [2.6, 2.2, 1.8, 1.5, 1.35, 1.35]
		return blockSpacing * multiples[clamp(level) - 1]
	}

	/// the space below a heading of `level`, as a multiple of `blockSpacing`.
	public func headingSpaceBelow(_ level: Int) -> Double {
		let multiples: [Double] = [1.6, 1.0, 0.8, 0.6, 0.55, 0.55]
		return blockSpacing * multiples[clamp(level) - 1]
	}

	private func clamp(_ level: Int) -> Int {
		min(max(level, 1), 6)
	}
}