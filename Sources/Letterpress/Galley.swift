import Foundation

// MARK: - Margins

/// page margins in points — the print-standard 72pt (1 inch) by default.
public struct Margins: Sendable, Hashable {
	/// the top margin in points.
	public var top: Double
	/// the leading (left/inner) margin in points.
	public var leading: Double
	/// the bottom margin in points.
	public var bottom: Double
	/// the trailing (right/outer) margin in points.
	public var trailing: Double

	/// create margins; every edge defaults to 72pt (one inch).
	public init(top: Double = 72, leading: Double = 72, bottom: Double = 72, trailing: Double = 72) {
		self.top = top
		self.leading = leading
		self.bottom = bottom
		self.trailing = trailing
	}

	/// the print-standard one-inch margins.
	public static let standard = Margins()
}

// MARK: - PaginationWarning

/// a mark the paginator could not fit inside a content box.
///
/// a warning means content was laid out past the box's bottom edge: it is
/// drawn — never silently dropped — but it runs into the margin or off the
/// page. the usual cause is a single unbreakable mark taller than the box (an
/// image-sized `Rect`, a lone `Text` line, a table row); a *breakable* mark
/// (`Paragraph`, `Text`, `RichText`, `CodeBlock`, a `VStack`) never warns,
/// because it splits and continues on the next page. `pagination()` returns
/// these so a caller can fail loudly instead of shipping a clipped page.
public struct PaginationWarning: Sendable, Hashable, CustomStringConvertible {
	/// the 1-based page the overfull mark landed on.
	public let page: Int
	/// the mark's index in the galley's flow.
	public let markIndex: Int
	/// how many points the mark extends past the content box.
	public let overflow: Double

	/// create a warning.
	public init(page: Int, markIndex: Int, overflow: Double) {
		self.page = page
		self.markIndex = markIndex
		self.overflow = overflow
	}

	/// a one-line human summary.
	public var description: String {
		"page \(page): flow child \(markIndex) overflows the content box by \(PDFNumber(overflow, decimals: 2))pt"
	}
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
/// break between siblings at the box's bottom edge. a *breakable* child —
/// `Paragraph`, `Text`, `RichText`, `CodeBlock`, a `VStack` — continues on the
/// next page when it does not fit, and `.keepWithNext()` / `.pageBreak()` add
/// explicit break policy. a child that cannot break moves whole; a mark that
/// still exceeds an otherwise empty content box is drawn anyway and *reported*
/// through `pagination()`, never silently dropped. a `Galley` is a page-level
/// expression: build it in a `PDFDocument`, and it expands into as many
/// physical pages as the content needs.
public struct Galley: Sendable {
	/// the page dimensions this galley paginates onto.
	public let size: PageSize
	/// the margins that bound every page's content box.
	public let margins: Margins
	/// vertical points between adjacent children, clamped to zero so flow
	/// content never stacks in on itself.
	public let spacing: Double
	/// an optional full-bleed color painted on every physical page.
	public var background: Color?
	/// the flow content, in declaration order.
	public let children: [any Mark]
	/// builds the marks a page carries beyond its flow bucket: the first
	/// argument is the page's 1-based number, the second the page count.
	public var furniture: (@Sendable (Int, Int) -> [any Mark])?

	/// create a galley; `content` is the paginated flow.
	public init(
		_ size: PageSize = .a4,
		margins: Margins = .standard,
		spacing: Double = 0,
		@MarkBuilder content: () -> [any Mark]
	) {
		self.size = size
		self.margins = margins
		self.spacing = max(spacing, 0)
		self.background = nil
		self.children = content()
		self.furniture = nil
	}

	/// set a uniform background that every physical page paints.
	public func background(_ color: Color) -> Galley {
		var galley = self
		galley.background = color
		return galley
	}

	/// add page furniture — marks drawn on every page after its flow.
	///
	/// `build` receives the page's 1-based number and the total page count, so
	/// page numbers, running heads, and footers are expressible without the
	/// galley knowing what they say. position them explicitly with `.at(x:y:)`
	/// (or a full-page `.frame`), because furniture draws over the flow.
	public func furniture(_ build: @escaping @Sendable (Int, Int) -> [any Mark]) -> Galley {
		var galley = self
		galley.furniture = build
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

	/// expand into physical pages, discarding the overflow report.
	///
	/// this is what `PageBuilder` calls; use `pagination()` when the report
	/// matters.
	internal func paginate() -> [PDFPage] {
		pagination().pages
	}

	/// expand into physical pages and report whatever the content box could
	/// not hold.
	///
	/// every physical page is a plain `PDFPage` whose bucket is a `VStack` at
	/// the content-box origin under `.frame(maxWidth:)`, so the break-time
	/// measurements and the write-time layout share one proposal, one spacing,
	/// and the single-measurement discipline — the measure/write agreement
	/// extends across page boundaries.
	///
	/// a child that does not fit is offered to `Mark.split`; the piece that
	/// fits stays and the runover opens the next page, which is how one
	/// paragraph spans many pages. `warnings` is empty for content that fits.
	public func pagination() -> (pages: [PDFPage], warnings: [PaginationWarning]) {
		let box = contentBox
		guard !children.isEmpty, box.height > 0 else { return ([], []) }

		let proposal = ProposedSize(width: box.width, height: nil)
		var measure = MeasureContext()

		struct FlowItem {
			let origin: Int
			let mark: any Mark
		}

		var queue = children.enumerated().map { FlowItem(origin: $0.offset, mark: $0.element) }
		var buckets: [[FlowItem]] = []
		var warnings: [PaginationWarning] = []
		var current: [FlowItem] = []
		var remaining = box.height
		var cursor = 0

		// every accepted split shrinks the runover, so the walk terminates;
		// the counter is a backstop against a custom `split` that ignores the
		// contract (it places the rest rather than dropping it).
		var steps = 0
		let stepLimit = queue.count * 64 + 256

		while cursor < queue.count {
			steps += 1
			if steps > stepLimit { break }

			let item = queue[cursor]
			let control = item.mark as? any BreakControlling

			// an explicit break ends the page without consuming the mark.
			if control?.breaksBefore == true, !current.isEmpty {
				buckets.append(current)
				current = []
				remaining = box.height
			}

			let height = item.mark.sizeThatFits(proposal, in: &measure).height
			let gap = current.isEmpty ? 0 : spacing

			// keep-with-next: never strand this mark at the foot of a page.
			if !current.isEmpty, control?.keepsWithNext == true, cursor + 1 < queue.count {
				let after = remaining - gap - height - spacing
				let next = queue[cursor + 1].mark
				let nextFits = next.sizeThatFits(proposal, in: &measure).height <= after
				let nextStarts = nextFits || (after > 0 && (next.split(available: after, width: box.width, in: &measure)?
					.fits.sizeThatFits(proposal, in: &measure).height ?? 0) > 0)
				if !nextStarts {
					buckets.append(current)
					current = []
					remaining = box.height
					continue
				}
			}

			if height + gap <= remaining {
				current.append(item)
				remaining -= height + gap
				cursor += 1
				continue
			}

			// it does not fit here — can it break? this is also the path that
			// rescues a breakable mark taller than a whole content box.
			let available = remaining - gap
			if available > 0,
			   let pieces = item.mark.split(available: available, width: box.width, in: &measure) {
				let fitsHeight = pieces.fits.sizeThatFits(proposal, in: &measure).height
				if fitsHeight > 0, fitsHeight <= available + 0.001 {
					current.append(FlowItem(origin: item.origin, mark: pieces.fits))
					buckets.append(current)
					current = []
					remaining = box.height
					queue[cursor] = FlowItem(origin: item.origin, mark: pieces.runover)
					continue
				}
			}

			// it cannot break, and this page already holds content: start a
			// fresh page so it is not split across the seam.
			if !current.isEmpty {
				buckets.append(current)
				current = []
				remaining = box.height
				continue
			}

			// the page is empty and it still does not fit: it takes its own
			// page and overflows — drawn and reported, never dropped.
			if height > box.height {
				warnings.append(PaginationWarning(
					page: buckets.count + 1, markIndex: item.origin, overflow: height - box.height))
			}
			current.append(item)
			remaining = box.height - height
			cursor += 1
		}

		// the backstop tripped: place the rest so nothing is ever lost.
		if cursor < queue.count {
			current.append(contentsOf: queue[cursor...])
		}
		if !current.isEmpty {
			buckets.append(current)
		}

		// a block bakes its trailing rhythm into its own height, so the last
		// block's gap can spill past its content and open a page that holds
		// nothing visible. drop such a trailing page — a blank final page is
		// never wanted — keeping the first page so the tree stays valid.
		if buckets.count > 1, let last = buckets.last {
			var onlySpacing = true
			for item in last where item.mark.sizeThatFits(proposal, in: &measure).width > 0.001 {
				onlySpacing = false
				break
			}
			if onlySpacing { buckets.removeLast() }
		}

		let total = buckets.count
		let pages = buckets.enumerated().map { index, bucket -> PDFPage in
			var page = PDFPage(size) {
				VStack(alignment: .leading, spacing: spacing) {
					bucket.map { $0.mark }
				}
				.frame(maxWidth: box.width)
				.at(x: box.x, y: box.y)
				if let furniture {
					furniture(index + 1, total)
				}
			}
			page.background = background
			return page
		}
		return (pages, warnings)
	}
}