// MARK: - PageSize

/// a page's dimensions in points (1/72 inch).
public enum PageSize: Sendable, Hashable {
	/// ISO A4 (595.28 × 841.89 pt).
	case a4
	/// US Letter (612 × 792 pt).
	case letter
	/// ISO A5 (419.53 × 595.28 pt).
	case a5
	/// an arbitrary size in points.
	case custom(width: Double, height: Double)

	/// the dimensions in points as `(width, height)`.
	public var size: (width: Double, height: Double) {
		switch self {
		case .a4: return (595.28, 841.89)
		case .letter: return (612, 792)
		case .a5: return (419.53, 595.28)
		case .custom(let width, let height): return (width, height)
		}
	}

	/// the page width in points.
	public var width: Double { size.width }
	/// the page height in points.
	public var height: Double { size.height }
}

// MARK: - PDFPage

/// one page of a document: a size plus a list of marks.
///
///     PDFPage(.a4) {
///         Text("hello").font(.helveticaBold, size: 24).at(x: 72, y: 72)
///         Rect(x: 72, y: 120, width: 120, height: 60).fill(.sky)
///     }
///
/// a page can carry a full-bleed background color via `.background(_:)`.
public struct PDFPage: Mark, Sendable {
	/// the page dimensions.
	public let size: PageSize
	/// the marks painted on the page, in order.
	public let marks: [any Mark]
	/// an optional full-bleed color painted before the marks.
	public var background: Color?

	/// create a page; `content` is the page's marks.
	public init(_ size: PageSize = .a4, @MarkBuilder content: () -> [any Mark]) {
		self.size = size
		self.marks = content()
		self.background = nil
	}

	/// fill the whole page with `color` before the marks paint.
	public func background(_ color: Color) -> PDFPage {
		var page = self
		page.background = color
		return page
	}

	public func write(to renderer: inout Renderer) {
		if let background {
			if let gstate = renderer.useAlpha(background.alpha) {
				renderer.append("\(gstate) gs\n")
			}
			renderer.append("\(PDFNumber(background.r, decimals: 6)) \(PDFNumber(background.g, decimals: 6)) \(PDFNumber(background.b, decimals: 6)) rg\n")
			renderer.append("0 0 \(PDFNumber(size.width)) \(PDFNumber(size.height)) re f\n")
		}
		for mark in marks {
			mark.write(to: &renderer)
		}
	}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: size.width, height: size.height)
	}
}

// MARK: - PageBuilder

/// builds a page list from a block: pages pass through, galleys paginate.
@resultBuilder
public enum PageBuilder {
	/// flatten the block's pages.
	public static func buildBlock(_ components: [PDFPage]...) -> [PDFPage] {
		components.flatMap { $0 }
	}
	/// take a single page.
	public static func buildExpression(_ expression: PDFPage) -> [PDFPage] {
		[expression]
	}
	/// expand a galley into the physical pages its content needs.
	public static func buildExpression(_ expression: Galley) -> [PDFPage] {
		expression.paginate()
	}
	/// pass a pre-built page list through.
	public static func buildExpression(_ expression: [PDFPage]) -> [PDFPage] {
		expression
	}
	/// treat a missing `if` branch as empty.
	public static func buildOptional(_ component: [PDFPage]?) -> [PDFPage] {
		component ?? []
	}
	/// take the `if` branch.
	public static func buildEither(first: [PDFPage]) -> [PDFPage] {
		first
	}
	/// take the `else` branch.
	public static func buildEither(second: [PDFPage]) -> [PDFPage] {
		second
	}
	/// flatten a `for` loop's pages.
	public static func buildArray(_ components: [[PDFPage]]) -> [PDFPage] {
		components.flatMap { $0 }
	}
	/// pass an availability-gated block through.
	public static func buildLimitedAvailability(_ component: [PDFPage]) -> [PDFPage] {
		component
	}
}

// MARK: - PDFDocument

/// a declarative pdf document.
///
///     let document = PDFDocument {
///         PDFPage(.a4) {
///             Text("hello, letterpress")
///                 .font(.helveticaBold, size: 32)
///                 .at(x: 72, y: 72)
///         }
///         PDFPage(.letter) {
///             Rect(x: 72, y: 72, width: 200, height: 80)
///                 .fill(.blue)
///         }
///     }
///     let bytes = document.render()
public struct PDFDocument: Sendable {
	/// the document's pages, in order.
	public let pages: [PDFPage]

	/// create a document; `content` is the page list.
	///
	/// a document always has at least one page: an empty page list — a galley
	/// with no content, or margins that leave no content box — yields one
	/// blank `.a4` page rather than a structurally invalid pdf.
	public init(@PageBuilder content: () -> [PDFPage]) {
		let pages = content()
		self.pages = pages.isEmpty ? [PDFPage(.a4) { }] : pages
	}

	/// assemble the document into pdf bytes.
	///
	/// the bytes are the whole product: the exporter never touches the
	/// filesystem, so a caller decides what to do with them — write them with
	/// whatever file layer it already has, or hand them straight to a socket.
	public func render() -> [UInt8] {
		PDFWriter(pages: pages).render()
	}
}
