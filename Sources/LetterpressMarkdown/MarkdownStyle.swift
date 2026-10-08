import Letterpress

// MARK: - MarkdownStyle

/// the typographic theme a markdown document renders under.
///
/// one value type carries every knob — page geometry, typefaces, sizes,
/// colours, spacing — so a caller configures the whole look in one place and
/// the block composer reads it. sizes are in points; `lineHeight` is a
/// multiple of the font size.
public struct MarkdownStyle: Sendable {
	// page
	/// the physical page size.
	public var pageSize: PageSize
	/// the page margins.
	public var margins: Margins

	// type
	/// the body typeface.
	public var typeface: MarkdownTypeface
	/// the typeface for code spans and blocks.
	public var codeTypeface: MarkdownTypeface
	/// the body point size.
	public var bodySize: Double
	/// the body line-height multiple.
	public var lineHeight: Double

	// colour
	/// the body text color.
	public var textColor: Color
	/// the heading text color.
	public var headingColor: Color
	/// the color links paint in.
	public var linkColor: Color
	/// the inline and block code text color.
	public var codeColor: Color
	/// the code-block panel fill.
	public var codeBackground: Color
	/// the color of blockquote bars and thematic rules.
	public var barColor: Color

	// rhythm
	/// the vertical gap before each block.
	public var blockSpacing: Double
	/// the vertical gap between list items.
	public var itemSpacing: Double
	/// the code point size.
	public var codeSize: Double

	/// create the default theme; `.standard` is one of these.
	public init() {
		self.pageSize = .a4
		self.margins = Margins(top: 64, leading: 64, bottom: 64, trailing: 64)

		self.typeface = .sans
		self.codeTypeface = .mono
		self.bodySize = 10.5
		self.lineHeight = 1.45

		self.textColor = .ink
		self.headingColor = .ink
		self.linkColor = .blue
		self.codeColor = .darkGray
		self.codeBackground = Color(hex: 0xF3F4F6)
		self.barColor = .lightGray

		self.blockSpacing = 9
		self.itemSpacing = 3
		self.codeSize = 9
	}

	/// the default theme.
	public static let standard = MarkdownStyle()

	/// the width of the text column: page width less the horizontal margins.
	public var contentWidth: Double {
		max(pageSize.width - margins.leading - margins.trailing, 1)
	}

	/// the display size for an `h1`...`h6`, scaled from the body size.
	public func headingSize(_ level: Int) -> Double {
		let scales: [Double] = [1.9, 1.5, 1.25, 1.12, 1.0, 0.95]
		let index = min(max(level, 1), 6) - 1
		return bodySize * scales[index]
	}
}