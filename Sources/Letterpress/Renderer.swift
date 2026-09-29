import Foundation

// MARK: - Renderer

/// accumulates one page's content stream and tracks the resources the page
/// uses (fonts, ext-gstate alpha values).
///
/// a fresh renderer is created per page, so resource names (`/F1`, `/GS1`)
/// restart at 1 on every page and the page's `/Resources` dict is built from
/// exactly what that page registered.
public struct Renderer: Sendable {
	internal var bytes: [UInt8] = []
	internal var fontNames: [String] = []
	internal var alphaValues: [Double] = []

	/// page height in points, used to flip user-space y-down coordinates to
	/// pdf's y-up space.
	public let pageHeight: Double

	public init(pageHeight: Double) {
		self.pageHeight = pageHeight
	}

	/// convert a user-space y (origin top-left, growing downward) to pdf
	/// y-up coordinates.
	public func flippedY(_ y: Double) -> Double {
		pageHeight - y
	}

	// MARK: resource registration

	/// register a font for this page; returns its resource tag (`/F1`, ...).
	@discardableResult
	public mutating func useFont(_ font: Font) -> String {
		let name = font.baseName
		if let index = fontNames.firstIndex(of: name) {
			return "/F\(index + 1)"
		}
		fontNames.append(name)
		return "/F\(fontNames.count)"
	}

	/// register a fill/stroke alpha for this page; returns its ext-gstate
	/// resource tag (`/GS1`, ...), or `nil` for fully-opaque alpha (no
	/// ext-gstate needed).
	@discardableResult
	public mutating func useAlpha(_ alpha: Double) -> String? {
		guard alpha < 1 else { return nil }
		if let index = alphaValues.firstIndex(of: alpha) {
			return "/GS\(index + 1)"
		}
		alphaValues.append(alpha)
		return "/GS\(alphaValues.count)"
	}

	// MARK: text style state

	/// the text style active while a text mark writes. modifiers push this
	/// state in and restore it after, keeping sibling marks independent.
	internal var text = TextState()

	// MARK: layout state

	/// the size proposal active while a mark writes. `FrameModifier` pushes
	/// this in and restores it after; containers lay out against it and
	/// paragraphs wrap to it.
	internal var proposedSize = ProposedSize.unconstrained

	// MARK: low-level emission

	internal mutating func append(_ string: String) {
		bytes.append(contentsOf: string.utf8)
	}

	internal mutating func append(_ number: PDFNumber) {
		append(number.description)
	}
}

// MARK: - TextState

/// the current text attributes a `Text`/`Paragraph` reads while writing.
public struct TextState: Sendable {
	public var font: Font = .helvetica
	public var size: Double = 12
	public var position: Point = Point(x: 0, y: 0)
	public var alignment: TextAlignment = .leading
	public var lineHeight: Double = 1.25

	public init() {}
}

// MARK: - MeasureContext

/// style state for the measurement pass.
///
/// mirrors the write-side `Renderer.text` so a mark measures under the same
/// font/size/line-height/wrap settings it renders with. `position` and
/// `alignment` are write-side concerns and are ignored here — measurement
/// is position-independent by design.
public struct MeasureContext: Sendable {
	public var text: TextState = TextState()

	public init(text: TextState = TextState()) {
		self.text = text
	}
}
