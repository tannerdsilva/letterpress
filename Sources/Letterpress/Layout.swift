// MARK: - FlexibleMark

/// a mark that absorbs leftover main-axis space inside a `HStack` or
/// `VStack`. `Spacer` is the only v1 conformer.
public protocol FlexibleMark: Mark {
	/// the minimum extent the mark keeps along the container's main axis.
	var minimumLength: Double { get }
}

// MARK: - Spacer

/// draws nothing; expands to fill leftover space in a stack.
///
///     HStack { Spacer(); Text("centered").font(.helvetica, size: 12); Spacer() }
///         .frame(maxWidth: 400)
///
/// flexible space only exists under a finite main-axis proposal — see
/// `.frame(maxWidth:)`, the sole proposal producer. outside a stack a
/// spacer measures `minimumLength` by 0 and paints nothing.
public struct Spacer: FlexibleMark {
	/// the extent kept when no leftover space is distributed.
	public let minimumLength: Double

	/// create a spacer; `minimumLength` is the extent it keeps.
	public init(minimumLength: Double = 0) {
		self.minimumLength = minimumLength
	}

	public func write(to renderer: inout Renderer) {}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: minimumLength, height: 0)
	}
}

// MARK: - layout engine

/// one child after layout: the mark to emit and where it sits relative to
/// the container's origin.
internal struct PlacedMark {
	var mark: any Mark
	var origin: Point
}

/// pure flex layout shared by `HStack` and `VStack` — the single place
/// measure and placement are computed, so `write` and `sizeThatFits` can
/// never disagree.
///
/// children are measured once at their ideal size; a finite incoming
/// cross-axis proposal re-wraps text children. flexible children collapse
/// to `minimumLength` and split any leftover main-axis space equally when a
/// finite proposal exceeds the content. without flexible children, or with
/// no finite proposal, the container hugs its content and overflow is legal.
internal func layoutFlex(
	children: [any Mark],
	horizontal: Bool,
	spacing: Double,
	crossOffset: (_ containerExtent: Double, _ childExtent: Double) -> Double,
	proposal: ProposedSize,
	context: inout MeasureContext
) -> (size: Size, placed: [PlacedMark]) {
	let crossProposal = horizontal
		? ProposedSize(width: nil, height: proposal.height)
		: ProposedSize(width: proposal.width, height: nil)

	var sizes: [Size] = []
	var flexible: [Bool] = []
	var minimums: [Double] = []
	for child in children {
		let size = child.sizeThatFits(crossProposal, in: &context)
		let flex = child as? any FlexibleMark
		sizes.append(size)
		flexible.append(flex != nil)
		minimums.append(flex?.minimumLength ?? 0)
	}

	// fixed content extent: inflexible children at their measured size,
	// flexible ones at their minimum, plus one gap per adjacency. flexible
	// children carry no cross presence.
	let gapTotal = spacing * Double(max(children.count - 1, 0))
	var mainExtents: [Double] = []
	var fixedMain = gapTotal
	var crossExtent = 0.0
	for (index, size) in sizes.enumerated() {
		let main = horizontal ? size.width : size.height
		let cross = horizontal ? size.height : size.width
		if flexible[index] {
			mainExtents.append(minimums[index])
			fixedMain += minimums[index]
		} else {
			mainExtents.append(main)
			fixedMain += main
			crossExtent = max(crossExtent, cross)
		}
	}

	// leftover distribution to flexible children.
	let proposedMain = horizontal ? proposal.width : proposal.height
	let flexCount = flexible.filter { $0 }.count
	var mainTotal = fixedMain
	if let proposedMain, flexCount > 0, proposedMain > fixedMain {
		let leftover = proposedMain - fixedMain
		let share = leftover / Double(flexCount)
		for index in mainExtents.indices where flexible[index] {
			mainExtents[index] = minimums[index] + share
		}
		mainTotal = proposedMain
	}

	var origins: [Double] = []
	var cursor = 0.0
	for extent in mainExtents {
		origins.append(cursor)
		cursor += extent + spacing
	}

	var placed: [PlacedMark] = []
	for (index, size) in sizes.enumerated() {
		let crossChild = flexible[index] ? 0 : (horizontal ? size.height : size.width)
		let origin = horizontal
			? Point(x: origins[index], y: crossOffset(crossExtent, crossChild))
			: Point(x: crossOffset(crossExtent, crossChild), y: origins[index])
		placed.append(PlacedMark(mark: children[index], origin: origin))
	}

	let size = horizontal
		? Size(width: mainTotal, height: crossExtent)
		: Size(width: crossExtent, height: mainTotal)
	return (size, placed)
}

// MARK: - VStack

/// a vertical flex container — children stack top to bottom.
///
///     VStack(spacing: 12) {
///         Text("hello").font(.helveticaBold, size: 32)
///         Paragraph("wrapped column text ...").font(.times, size: 12).frame(maxWidth: 280)
///         Rect(x: 0, y: 0, width: 280, height: 40).fill(.sky.opacity(0.35))
///     }
///     .at(x: 72, y: 72)
///
/// children are placed by the container and measure at their ideal size
/// (or re-wrap when the stack's own width proposal is finite — see
/// `.frame(maxWidth:)`). a child must not carry its own `.at` inside a
/// container; page-level `.at` on the stack positions the whole column.
/// `alignment` lines children up along the cross axis; `spacing` may be
/// negative to overlap (positive gaps between every pair).
public struct VStack: Mark {
	/// cross-axis (horizontal) alignment of the children.
	public let alignment: TextAlignment
	/// vertical points between adjacent children; may be negative to overlap.
	public let spacing: Double
	/// the children, in declaration order.
	public let children: [any Mark]

	/// create a vertical stack; `content` is the child list.
	public init(alignment: TextAlignment = .leading, spacing: Double = 0,
				@MarkBuilder content: () -> [any Mark]) {
		self.alignment = alignment
		self.spacing = spacing
		self.children = content()
	}

	/// adopt an existing child list — used where a container builds its own
	/// children (measurement helpers, split pieces).
	internal init(alignment: TextAlignment, spacing: Double, children: [any Mark]) {
		self.alignment = alignment
		self.spacing = spacing
		self.children = children
	}

	public func write(to renderer: inout Renderer) {
		var context = MeasureContext(text: renderer.text)
		let result = layoutFlex(
			children: children, horizontal: false, spacing: spacing,
			crossOffset: crossOffset, proposal: renderer.proposedSize, context: &context)
		let containerOrigin = renderer.text.position
		for child in result.placed {
			let origin = Point(
				x: containerOrigin.x + child.origin.x,
				y: containerOrigin.y + child.origin.y)
			renderer.append("q\n")
			renderer.append("1 0 0 1 \(PDFNumber(origin.x)) \(PDFNumber(-origin.y)) cm\n")
			let saved = renderer.text
			renderer.text.position = .zero
			child.mark.write(to: &renderer)
			renderer.text = saved
			renderer.append("Q\n")
		}
	}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		layoutFlex(
			children: children, horizontal: false, spacing: spacing,
			crossOffset: crossOffset, proposal: proposal, context: &context).size
	}

	/// break between children, and — when one child alone still overflows —
	/// inside that child. both pieces are stacks, so a broken column keeps its
	/// alignment and its spacing on either side of the break.
	public func split(available: Double, width: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)? {
		guard !children.isEmpty, available > 0 else { return nil }
		let proposal = ProposedSize(width: width, height: nil)

		var head: [any Mark] = []
		var used = 0.0
		var splitPiece: (fits: AnyMark, runover: AnyMark)?
		var cut = 0

		for (index, child) in children.enumerated() {
			let gap = head.isEmpty ? 0 : spacing
			let height = child.sizeThatFits(proposal, in: &context).height
			if used + gap + height <= available {
				head.append(child)
				used += gap + height
				cut = index + 1
				continue
			}
			// this child does not fit whole — can it break?
			let room = available - used - gap
			if room > 0, let pieces = child.split(available: room, width: width, in: &context) {
				let fitsHeight = pieces.fits.sizeThatFits(proposal, in: &context).height
				if fitsHeight > 0, fitsHeight <= room + 0.001 {
					splitPiece = pieces
					cut = index
				}
			}
			break
		}

		var tail: [any Mark]
		if let splitPiece {
			head.append(splitPiece.fits)
			tail = [splitPiece.runover]
			tail.append(contentsOf: children[(cut + 1)...])
		} else {
			tail = Array(children[cut...])
		}
		guard !head.isEmpty, !tail.isEmpty else { return nil }
		return (
			AnyMark(VStack(alignment: alignment, spacing: spacing, children: head)),
			AnyMark(VStack(alignment: alignment, spacing: spacing, children: tail))
		)
	}

	private var crossOffset: (_ containerExtent: Double, _ childExtent: Double) -> Double {
		switch alignment {
		case .leading: return { _, _ in 0 }
		case .center: return { container, child in (container - child) / 2 }
		case .trailing: return { container, child in container - child }
		}
	}
}

// MARK: - HStack

/// a horizontal flex container — children stack left to right.
///
///     HStack(spacing: 8, alignment: .center) {
///         Text("left").font(.helvetica, size: 12)
///         Rect(x: 0, y: 0, width: 40, height: 40).fill(.indigo.opacity(0.5))
///     }
///     .at(x: 72, y: 300)
///
/// the same flex contract as `VStack`, laid out along the x axis.
/// `alignment` lines children up vertically (top/center/bottom); `spacing`
/// may be negative to overlap.
public struct HStack: Mark {
	/// cross-axis (vertical) alignment of the children.
	public let alignment: VerticalAlignment
	/// horizontal points between adjacent children; may be negative to overlap.
	public let spacing: Double
	/// the children, in declaration order.
	public let children: [any Mark]

	/// create a horizontal stack; `content` is the child list.
	public init(alignment: VerticalAlignment = .top, spacing: Double = 0,
				@MarkBuilder content: () -> [any Mark]) {
		self.alignment = alignment
		self.spacing = spacing
		self.children = content()
	}

	public func write(to renderer: inout Renderer) {
		var context = MeasureContext(text: renderer.text)
		let result = layoutFlex(
			children: children, horizontal: true, spacing: spacing,
			crossOffset: crossOffset, proposal: renderer.proposedSize, context: &context)
		let containerOrigin = renderer.text.position
		for child in result.placed {
			let origin = Point(
				x: containerOrigin.x + child.origin.x,
				y: containerOrigin.y + child.origin.y)
			renderer.append("q\n")
			renderer.append("1 0 0 1 \(PDFNumber(origin.x)) \(PDFNumber(-origin.y)) cm\n")
			let saved = renderer.text
			renderer.text.position = .zero
			child.mark.write(to: &renderer)
			renderer.text = saved
			renderer.append("Q\n")
		}
	}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		layoutFlex(
			children: children, horizontal: true, spacing: spacing,
			crossOffset: crossOffset, proposal: proposal, context: &context).size
	}

	private var crossOffset: (_ containerExtent: Double, _ childExtent: Double) -> Double {
		switch alignment {
		case .top: return { _, _ in 0 }
		case .center: return { container, child in (container - child) / 2 }
		case .bottom: return { container, child in container - child }
		}
	}
}

// MARK: - ZStack

/// a back-to-front container: children paint in declaration order at the
/// container's origin — the pdf analogue of layering.
///
///     ZStack {
///         Rect(x: 0, y: 0, width: 200, height: 80).fill(.sky)
///         Text("on top").font(.helveticaBold, size: 16).at(x: 20, y: 30)
///     }
///
/// children keep their own positions (shapes carry geometry, text anchors
/// at the ambient position); unlike `HStack`/`VStack`, `ZStack` places
/// nothing. its size is the extent of the largest child, and every child is
/// measured under the same proposal it is written with — so a width-dependent
/// child (a `Paragraph`) reports the height it actually draws.
public struct ZStack: Mark {
	/// the stacked children, painted in declaration order.
	public let children: [any Mark]

	/// create a back-to-front stack; `content` is the child list.
	public init(@MarkBuilder content: () -> [any Mark]) {
		self.children = content()
	}

	public func write(to renderer: inout Renderer) {
		for child in children {
			child.write(to: &renderer)
		}
	}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		var width = 0.0
		var height = 0.0
		for child in children {
			// measure under the SAME proposal `write` hands the child, or a
			// width-dependent child (a Paragraph) is measured unwrapped and
			// drawn wrapped, reporting a height it does not honour.
			let size = child.sizeThatFits(proposal, in: &context)
			width = max(width, size.width)
			height = max(height, size.height)
		}
		return Size(width: width, height: height)
	}
}
