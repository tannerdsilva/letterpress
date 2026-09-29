import Foundation

// MARK: - Margins

/// page margins in points — the print-standard 72pt (1 inch) by default.
public struct Margins: Sendable, Hashable {
	public var top: Double
	public var leading: Double
	public var bottom: Double
	public var trailing: Double

	public init(top: Double = 72, leading: Double = 72, bottom: Double = 72, trailing: Double = 72) {
		self.top = top
		self.leading = leading
		self.bottom = bottom
		self.trailing = trailing
	}

	public static let standard = Margins()
}

// MARK: - Galley

/// unpaginated typeset material — a paginated vertical stack.
///
///     Galley(.a4, margins: .standard, spacing: 14) {
///         Paragraph("flows across pages ...")
///         Paragraph("...")
///     }
///     .background(Color(hex: 0xF8FAFC))
///
/// children stack down from the content box's top (inside the margins) and
/// break between siblings at the box's bottom edge. a child is atomic — it
/// never splits mid-mark — and a child taller than one content box overflows
/// visibly on its page. a `Galley` is a page-level expression: build it in a
/// `PDFDocument`, and it expands into as many physical pages as the content
/// needs.
public struct Galley: Sendable {
	public let size: PageSize
	public let margins: Margins
	public let spacing: Double
	public var background: Color?
	public let children: [any Mark]

	public init(
		_ size: PageSize = .a4,
		margins: Margins = .standard,
		spacing: Double = 0,
		@MarkBuilder content: () -> [any Mark]
	) {
		self.size = size
		self.margins = margins
		self.spacing = spacing
		self.background = nil
		self.children = content()
	}

	/// set a uniform background that every physical page paints.
	public func background(_ color: Color) -> Galley {
		var galley = self
		galley.background = color
		return galley
	}

	/// the area inside the margins where flow content sits.
	internal var contentBox: (x: Double, y: Double, width: Double, height: Double) {
		let width = size.size.width
		let height = size.size.height
		return (
			x: margins.leading,
			y: margins.top,
			width: max(width - margins.leading - margins.trailing, 0),
			height: max(height - margins.top - margins.bottom, 0)
		)
	}

	/// expand into physical pages: measure once, bucket, materialize.
	///
	/// every physical page is a plain `PDFPage` whose bucket is a
	/// `VStack` at the content-box origin under `.frame(maxWidth:)`, so the
	/// break-time measurements and the write-time layout share the same
	/// proposal, spacing, and single-measurement discipline — the
	/// measure/write agreement extends across page boundaries.
	internal func paginate() -> [PDFPage] {
		let box = contentBox
		guard !children.isEmpty, box.height > 0 else { return [] }

		var context = MeasureContext()
		let proposal = ProposedSize(width: box.width, height: nil)
		let heights = children.map { $0.sizeThatFits(proposal, in: &context).height }

		// bucket children into pages, breaking only between siblings.
		var buckets: [[Int]] = []
		var current: [Int] = []
		var remaining = box.height
		for (index, height) in heights.enumerated() {
			let gap = current.isEmpty ? 0 : spacing
			if current.isEmpty || height + gap <= remaining {
				current.append(index)
				remaining -= height + gap
			} else if height <= box.height {
				buckets.append(current)
				current = [index]
				remaining = box.height - height
			} else {
				// a child taller than the box stays on its page and overflows.
				current.append(index)
				remaining -= height + gap
			}
		}
		if !current.isEmpty {
			buckets.append(current)
		}

		return buckets.map { bucket in
			var page = PDFPage(size) {
				VStack(alignment: .leading, spacing: spacing) {
					bucket.map { children[$0] }
				}
				.frame(maxWidth: box.width)
				.at(x: box.x, y: box.y)
			}
			page.background = background
			return page
		}
	}
}
