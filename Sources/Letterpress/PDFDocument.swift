import Foundation

// MARK: - PageSize

/// a page's dimensions in points (1/72 inch).
public enum PageSize: Sendable, Hashable {
	case a4
	case letter
	case a5
	case custom(width: Double, height: Double)

	public var size: (width: Double, height: Double) {
		switch self {
		case .a4: return (595.28, 841.89)
		case .letter: return (612, 792)
		case .a5: return (419.53, 595.28)
		case .custom(let width, let height): return (width, height)
		}
	}

	public var width: Double { size.width }
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
	public let size: PageSize
	public let marks: [any Mark]
	public var background: Color?

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

@resultBuilder
public enum PageBuilder {
	public static func buildBlock(_ components: [PDFPage]...) -> [PDFPage] {
		components.flatMap { $0 }
	}
	public static func buildExpression(_ expression: PDFPage) -> [PDFPage] {
		[expression]
	}
	public static func buildExpression(_ expression: Galley) -> [PDFPage] {
		expression.paginate()
	}
	public static func buildExpression(_ expression: [PDFPage]) -> [PDFPage] {
		expression
	}
	public static func buildOptional(_ component: [PDFPage]?) -> [PDFPage] {
		component ?? []
	}
	public static func buildEither(first: [PDFPage]) -> [PDFPage] {
		first
	}
	public static func buildEither(second: [PDFPage]) -> [PDFPage] {
		second
	}
	public static func buildArray(_ components: [[PDFPage]]) -> [PDFPage] {
		components.flatMap { $0 }
	}
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
	public let pages: [PDFPage]

	public init(@PageBuilder content: () -> [PDFPage]) {
		self.pages = content()
	}

	/// assemble the document into pdf bytes.
	public func render() -> [UInt8] {
		PDFWriter(pages: pages).render()
	}

	/// assemble the document and write it to `url`.
	public func write(to url: URL) throws {
		let data = Data(render())
		try data.write(to: url)
	}
}
