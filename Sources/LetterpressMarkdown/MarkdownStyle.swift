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
	public var pageSize: PageSize
	public var margins: Margins

	// type
	public var typeface: MarkdownTypeface
	public var codeTypeface: MarkdownTypeface
	public var bodySize: Double
	public var lineHeight: Double

	// colour
	public var textColor: Color
	public var headingColor: Color
	public var linkColor: Color
	public var codeColor: Color
	public var codeBackground: Color
	public var barColor: Color

	// rhythm
	public var blockSpacing: Double
	public var itemSpacing: Double
	public var codeSize: Double

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