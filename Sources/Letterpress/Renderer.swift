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

	/// create a renderer for a page `pageHeight` points tall.
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

	/// the text style active while a text mark writes.
	///
	/// `public` because a `MarkModifier` styles content by mutating this, and a
	/// modifier written outside this module has to be able to do the same. such
	/// a modifier saves this, sets what it needs, delegates, then restores it —
	/// the shape every style modifier in this module already follows.
	public var text = TextState()

	// MARK: layout state

	/// the size proposal active while a mark writes.
	///
	/// `public` so a conforming mark measures itself against the same proposal
	/// it renders under (the measure/write agreement invariant), and so a custom
	/// container can propose to its children the way `FrameModifier` does.
	/// whichever mark changes it must restore it before returning.
	public var proposedSize = ProposedSize.unconstrained

	// MARK: low-level emission

	/// append a fragment of pdf content-stream syntax.
	///
	/// the escape hatch for a mark that draws something the built-in marks do
	/// not express. keep numbers going through `PDFNumber` (locale-independent)
	/// and string bodies through `pdfEscape` (7-bit).
	public mutating func append(_ string: String) {
		bytes.append(contentsOf: string.utf8)
	}

	/// append a pdf number to the content stream.
	public mutating func append(_ number: PDFNumber) {
		append(number.description)
	}
}

// MARK: - TextState

/// the current text attributes a `Text`/`Paragraph` reads while writing.
public struct TextState: Sendable {
	/// the active font face.
	public var font: Font = .helvetica
	/// the active point size.
	public var size: Double = 12
	/// the current text anchor (the top-left of the first line).
	public var position: Point = Point(x: 0, y: 0)
	/// the horizontal alignment about `position`.
	public var alignment: TextAlignment = .leading
	/// the line advance as a multiple of `size`.
	public var lineHeight: Double = 1.25

	/// create default text state: Helvetica at 12pt.
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
	/// the text style the measured marks resolve against.
	public var text: TextState = TextState()

	/// create a measure context under a given text style.
	public init(text: TextState = TextState()) {
		self.text = text
	}
}
