// MARK: - paint modifiers (shapes)

/// a modifier that paints without moving the geometry it wraps.
///
/// a filled or stroked path is still a path — the paint consumed the current
/// path but did not change it — so a later paint in the same chain can state
/// the geometry again (`PaintedPathMark`). modifiers that reposition content
/// (`frame`, `at`) are not path-transparent.
public protocol PathTransparentModifier: MarkModifier {}

/// state the wrapped mark's path again when an inner paint already consumed it.
///
/// each paint ends with a path-consuming operator, and pdf has no paint that
/// leaves the path intact, so the outer paint of a chain has to restate the
/// geometry it is about to paint.
private func restatePath<Content: Mark>(content: Content, to renderer: inout Renderer) {
	if let painted = content as? any PaintedPathMark {
		painted.writePath(to: &renderer)
	}
}

/// fills the wrapped mark's path after it paints. use on closed shapes
/// (`Rect`, `Ellipse`, `Polygon`).
public struct FillModifier: MarkModifier, PathTransparentModifier {
	/// the fill color.
	public let color: Color

	/// create a fill modifier.
	public init(color: Color) {
		self.color = color
	}

	public func apply<Content: Mark>(content: Content, to renderer: inout Renderer) {
		renderer.append("q\n")
		if let gstate = renderer.useAlpha(color.alpha) {
			renderer.append("\(gstate) gs\n")
		}
		renderer.append("\(PDFNumber(color.r)) \(PDFNumber(color.g)) \(PDFNumber(color.b)) rg\n")
		content.write(to: &renderer)
		restatePath(content: content, to: &renderer)
		renderer.append("f\n")
		renderer.append("Q\n")
	}
}

/// strokes the wrapped mark's path after it paints. use on any open or
/// closed path (`Line`, `Rect`, `Ellipse`, `Polygon`).
///
/// the reported size includes the stroke bleed (half the width on every
/// side), so containers space for a stroked mark correctly.
public struct StrokeModifier: MarkModifier, PathTransparentModifier {
	/// the stroke color.
	public let color: Color
	/// the stroke width; the measured size grows by this on each axis.
	public let width: Double

	/// create a stroke modifier.
	public init(color: Color, width: Double) {
		self.color = color
		self.width = width
	}

	public func apply<Content: Mark>(content: Content, to renderer: inout Renderer) {
		renderer.append("q\n")
		if let gstate = renderer.useAlpha(color.alpha) {
			renderer.append("\(gstate) gs\n")
		}
		renderer.append("\(PDFNumber(width)) w\n")
		renderer.append("\(PDFNumber(color.r)) \(PDFNumber(color.g)) \(PDFNumber(color.b)) RG\n")
		content.write(to: &renderer)
		restatePath(content: content, to: &renderer)
		renderer.append("S\n")
		renderer.append("Q\n")
	}

	public func sizeThatFits<Content: Mark>(
		content: Content, proposal: ProposedSize, in context: inout MeasureContext
	) -> Size {
		let size = content.sizeThatFits(proposal, in: &context)
		return Size(width: size.width + width, height: size.height + width)
	}
}

// MARK: - text style modifiers

/// sets the fill (nonstroking) color without painting anything — the text
/// mark paints itself. use on `Text`/`Paragraph`.
public struct ForegroundColorModifier: MarkModifier {
	/// the text color.
	public let color: Color

	/// create a text-color modifier.
	public init(color: Color) {
		self.color = color
	}

	public func apply<Content: Mark>(content: Content, to renderer: inout Renderer) {
		let scoped = color.alpha < 1
		if scoped {
			renderer.append("q\n")
			if let gstate = renderer.useAlpha(color.alpha) {
				renderer.append("\(gstate) gs\n")
			}
		}
		renderer.append("\(PDFNumber(color.r)) \(PDFNumber(color.g)) \(PDFNumber(color.b)) rg\n")
		content.write(to: &renderer)
		if scoped { renderer.append("Q\n") }
	}
}

/// sets the font and size for text marks.
public struct FontModifier: MarkModifier {
	/// the face to set.
	public let font: Font
	/// the point size to set.
	public let size: Double

	/// create a font modifier.
	public init(font: Font, size: Double) {
		self.font = font
		self.size = size
	}

	public func apply<Content: Mark>(content: Content, to renderer: inout Renderer) {
		let saved = renderer.text
		renderer.text.font = font
		renderer.text.size = size
		content.write(to: &renderer)
		renderer.text = saved
	}

	public func sizeThatFits<Content: Mark>(
		content: Content, proposal: ProposedSize, in context: inout MeasureContext
	) -> Size {
		let saved = context.text
		context.text.font = font
		context.text.size = size
		let result = content.sizeThatFits(proposal, in: &context)
		context.text = saved
		return result
	}

	/// split under this modifier's font, and re-apply the font to both pieces —
	/// the split measures and draws as the whole mark would.
	public func split<Content: Mark>(content: Content, available: Double, width: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)? {
		let saved = context.text
		context.text.font = font
		context.text.size = size
		let pieces = content.split(available: available, width: width, in: &context)
		context.text = saved
		guard let pieces else { return nil }
		return (
			AnyMark(ModifiedMark(content: pieces.fits, modifier: self)),
			AnyMark(ModifiedMark(content: pieces.runover, modifier: self))
		)
	}
}

/// sets the anchor point (top-left) for text marks.
public struct PositionModifier: MarkModifier {
	/// the anchor point (the top-left of the first line).
	public let point: Point

	/// create a position modifier.
	public init(point: Point) {
		self.point = point
	}

	public func apply<Content: Mark>(content: Content, to renderer: inout Renderer) {
		let saved = renderer.text
		renderer.text.position = point
		content.write(to: &renderer)
		renderer.text = saved
	}
}

/// sets the horizontal text alignment.
public struct AlignmentModifier: MarkModifier {
	/// the alignment to set.
	public let alignment: TextAlignment

	/// create an alignment modifier.
	public init(alignment: TextAlignment) {
		self.alignment = alignment
	}

	public func apply<Content: Mark>(content: Content, to renderer: inout Renderer) {
		let saved = renderer.text
		renderer.text.alignment = alignment
		content.write(to: &renderer)
		renderer.text = saved
	}
}

/// sets the line-height multiple for multi-line text.
public struct LineHeightModifier: MarkModifier {
	/// the line advance as a multiple of the font size.
	public let factor: Double

	/// create a line-height modifier.
	public init(factor: Double) {
		self.factor = factor
	}

	public func apply<Content: Mark>(content: Content, to renderer: inout Renderer) {
		let saved = renderer.text
		renderer.text.lineHeight = factor
		content.write(to: &renderer)
		renderer.text = saved
	}

	public func sizeThatFits<Content: Mark>(
		content: Content, proposal: ProposedSize, in context: inout MeasureContext
	) -> Size {
		let saved = context.text
		context.text.lineHeight = factor
		let result = content.sizeThatFits(proposal, in: &context)
		context.text = saved
		return result
	}

	/// split under this modifier's line height, and re-apply it to both pieces.
	public func split<Content: Mark>(content: Content, available: Double, width: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)? {
		let saved = context.text
		context.text.lineHeight = factor
		let pieces = content.split(available: available, width: width, in: &context)
		context.text = saved
		guard let pieces else { return nil }
		return (
			AnyMark(ModifiedMark(content: pieces.fits, modifier: self)),
			AnyMark(ModifiedMark(content: pieces.runover, modifier: self))
		)
	}
}

// MARK: - frame modifier

/// constrains a mark into a box by min/ideal/max bounds and aligns the
/// content inside it.
///
/// the frame resolves a proposal to its content (ideal when an axis is
/// unconstrained, then clamped into the bounds) and reports a box clamped
/// from the content's size. a finite `maxWidth` is also the wrap width for
/// `Paragraph`; a `min` bound forces the box larger, and `alignment` /
/// `vertical` position the content inside it. when the box is smaller than
/// the content, the content overflows visibly.
public struct FrameModifier: MarkModifier {
	/// the minimum width; the box never shrinks below it.
	public let minWidth: Double?
	/// the width used when the incoming width proposal is unconstrained.
	public let idealWidth: Double?
	/// the maximum width; the box never grows past it. the wrap width for `Paragraph`.
	public let maxWidth: Double?
	/// the minimum height; the box never shrinks below it.
	public let minHeight: Double?
	/// the height used when the incoming height proposal is unconstrained.
	public let idealHeight: Double?
	/// the maximum height; the box never grows past it.
	public let maxHeight: Double?
	/// horizontal placement of content inside the box.
	public let alignment: TextAlignment
	/// vertical placement of content inside the box.
	public let vertical: VerticalAlignment

	/// create a frame; every bound defaults to `nil` (unconstrained).
	public init(
		minWidth: Double? = nil, idealWidth: Double? = nil, maxWidth: Double? = nil,
		minHeight: Double? = nil, idealHeight: Double? = nil, maxHeight: Double? = nil,
		alignment: TextAlignment = .leading, vertical: VerticalAlignment = .top
	) {
		self.minWidth = minWidth
		self.idealWidth = idealWidth
		self.maxWidth = maxWidth
		self.minHeight = minHeight
		self.idealHeight = idealHeight
		self.maxHeight = maxHeight
		self.alignment = alignment
		self.vertical = vertical
	}

	/// the proposal handed to the content: ideal when an axis is
	/// unconstrained (and offered), then narrowed into the bounds.
	private func resolvedProposal(for incoming: ProposedSize) -> ProposedSize {
		var width = incoming.width
		if width == nil, let idealWidth { width = idealWidth }
		if let minWidth { width = max(minWidth, width ?? minWidth) }
		if let maxWidth { width = min(maxWidth, width ?? maxWidth) }

		var height = incoming.height
		if height == nil, let idealHeight { height = idealHeight }
		if let minHeight { height = max(minHeight, height ?? minHeight) }
		if let maxHeight { height = min(maxHeight, height ?? maxHeight) }

		return ProposedSize(width: width, height: height)
	}

	/// the frame's box for a content size: content clamped into the bounds.
	private func box(for content: Size) -> Size {
		var width = content.width
		if let minWidth { width = max(minWidth, width) }
		if let maxWidth { width = min(maxWidth, width) }
		var height = content.height
		if let minHeight { height = max(minHeight, height) }
		if let maxHeight { height = min(maxHeight, height) }
		return Size(width: width, height: height)
	}

	/// how far to shift content when the box is larger on an axis.
	private func alignmentOffset(content: Size, box: Size) -> Point {
		let dx = box.width > content.width ? (box.width - content.width) * alignment.frameFactor : 0
		let dy = box.height > content.height ? (box.height - content.height) * vertical.frameFactor : 0
		return Point(x: dx, y: dy)
	}

	public func apply<Content: Mark>(content: Content, to renderer: inout Renderer) {
		let saved = renderer.proposedSize
		renderer.proposedSize = resolvedProposal(for: saved)
		var measure = MeasureContext(text: renderer.text)
		let contentSize = content.sizeThatFits(renderer.proposedSize, in: &measure)
		let frame = box(for: contentSize)
		let offset = alignmentOffset(content: contentSize, box: frame)
		if offset.x != 0 || offset.y != 0 {
			renderer.append("q\n")
			renderer.append("1 0 0 1 \(PDFNumber(offset.x)) \(PDFNumber(-offset.y)) cm\n")
			content.write(to: &renderer)
			renderer.append("Q\n")
		} else {
			content.write(to: &renderer)
		}
		renderer.proposedSize = saved
	}

	public func sizeThatFits<Content: Mark>(
		content: Content, proposal: ProposedSize, in context: inout MeasureContext
	) -> Size {
		box(for: content.sizeThatFits(resolvedProposal(for: proposal), in: &context))
	}

	/// split the content at the width this frame resolves, so a piece wraps
	/// exactly where the unframed mark wrapped.
	public func split<Content: Mark>(content: Content, available: Double, width: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)? {
		let resolved = resolvedProposal(for: ProposedSize(width: width, height: nil)).width ?? width
		guard let pieces = content.split(available: available, width: resolved, in: &context) else {
			return nil
		}
		return (
			AnyMark(ModifiedMark(content: pieces.fits, modifier: self)),
			AnyMark(ModifiedMark(content: pieces.runover, modifier: self))
		)
	}
}

extension TextAlignment {
	/// alignment factor: 0 = leading, 0.5 = center, 1 = trailing.
	internal var frameFactor: Double {
		switch self {
		case .leading: return 0
		case .center: return 0.5
		case .trailing: return 1
		}
	}
}

extension VerticalAlignment {
	/// alignment factor: 0 = top, 0.5 = center, 1 = bottom.
	internal var frameFactor: Double {
		switch self {
		case .top: return 0
		case .center: return 0.5
		case .bottom: return 1
		}
	}
}

// MARK: - path paint chaining

extension PathMark {
	/// fill the mark's path with `color`.
	///
	/// declared on `PathMark`, not `Mark`: a paint consumes the current path, so
	/// a mark with no path has nothing to fill. putting these on the base
	/// protocol would let `Text("x").fill(.red)` compile with nothing to paint.
	public func fill(_ color: Color) -> ModifiedMark<Self, FillModifier> {
		ModifiedMark(content: self, modifier: FillModifier(color: color))
	}

	/// stroke the mark's path with `color` at `width` points.
	public func stroke(_ color: Color, width: Double) -> ModifiedMark<Self, StrokeModifier> {
		ModifiedMark(content: self, modifier: StrokeModifier(color: color, width: width))
	}
}

// MARK: - Mark modifier chaining

extension Mark {
	/// set the text color (no paint — the text marks itself).
	public func foregroundColor(_ color: Color) -> ModifiedMark<Self, ForegroundColorModifier> {
		ModifiedMark(content: self, modifier: ForegroundColorModifier(color: color))
	}

	/// set the font family and size for text marks.
	public func font(_ font: Font, size: Double) -> ModifiedMark<Self, FontModifier> {
		ModifiedMark(content: self, modifier: FontModifier(font: font, size: size))
	}

	/// anchor text at user point `(x, y)` — the top-left of the first line
	/// (or the horizontal anchor for non-leading alignment).
	public func at(x: Double, y: Double) -> ModifiedMark<Self, PositionModifier> {
		ModifiedMark(content: self, modifier: PositionModifier(point: Point(x: x, y: y)))
	}

	/// anchor text at user point `point`.
	public func at(_ point: Point) -> ModifiedMark<Self, PositionModifier> {
		ModifiedMark(content: self, modifier: PositionModifier(point: point))
	}

	/// set the horizontal text alignment.
	public func alignment(_ alignment: TextAlignment) -> ModifiedMark<Self, AlignmentModifier> {
		ModifiedMark(content: self, modifier: AlignmentModifier(alignment: alignment))
	}

	/// set the line-height as a multiple of the font size.
	public func lineHeight(_ factor: Double) -> ModifiedMark<Self, LineHeightModifier> {
		ModifiedMark(content: self, modifier: LineHeightModifier(factor: factor))
	}

	/// constrain the mark into a box and align content inside it; see
	/// `FrameModifier`. a finite `maxWidth` is the wrap width for
	/// `Paragraph`.
	public func frame(
		minWidth: Double? = nil, idealWidth: Double? = nil, maxWidth: Double? = nil,
		minHeight: Double? = nil, idealHeight: Double? = nil, maxHeight: Double? = nil,
		alignment: TextAlignment = .leading, vertical: VerticalAlignment = .top
	) -> ModifiedMark<Self, FrameModifier> {
		ModifiedMark(content: self, modifier: FrameModifier(
			minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
			minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight,
			alignment: alignment, vertical: vertical))
	}
}

// MARK: - break control

/// sets a page-break policy on the wrapped mark: it draws and measures
/// exactly like the mark it wraps, and the paginator reads it through
/// `BreakControlling`.
public struct BreakModifier: MarkModifier {
	/// start the wrapped mark at the top of a fresh page.
	public let breaksBefore: Bool
	/// keep the wrapped mark on the same page as the mark that follows it.
	public let keepsWithNext: Bool

	/// create a break modifier; every policy is off by default.
	public init(breaksBefore: Bool = false, keepsWithNext: Bool = false) {
		self.breaksBefore = breaksBefore
		self.keepsWithNext = keepsWithNext
	}

	public func apply<Content: Mark>(content: Content, to renderer: inout Renderer) {
		content.write(to: &renderer)
	}
}

extension ModifiedMark: BreakControlling where M == BreakModifier {
	public var breaksBefore: Bool { modifier.breaksBefore }
	public var keepsWithNext: Bool { modifier.keepsWithNext }
}

extension Mark {
	/// start this mark at the top of a fresh page.
	///
	/// a break on the flow's first child is a no-op: the page is already
	/// empty.
	public func pageBreak() -> ModifiedMark<Self, BreakModifier> {
		ModifiedMark(content: self, modifier: BreakModifier(breaksBefore: true))
	}

	/// keep this mark on the same page as the mark that follows it, so a
	/// heading cannot be stranded at the foot of a page.
	public func keepWithNext() -> ModifiedMark<Self, BreakModifier> {
		ModifiedMark(content: self, modifier: BreakModifier(keepsWithNext: true))
	}
}
