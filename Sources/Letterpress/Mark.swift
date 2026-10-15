// MARK: - Mark Protocol

/// a declarative drawing instruction — the pdf analogue of a `View`.
///
/// a `Mark` emits content-stream operators into a `Renderer`, and answers
/// how much space it occupies for a given proposal. marks are value types:
/// every mark is a pure description of what to draw, and the renderer is
/// the only thing that mutates while the document assembles.
///
/// the protocol is implementable outside this module. a conformer either
/// composes the built-in marks (`Text`, `Rect`, `VStack`, ...), or emits
/// operators itself through `renderer.append`, and it reads
/// `renderer.proposedSize` — the same proposal `sizeThatFits` was handed — so
/// measurement and drawing cannot disagree. `Renderer.text` and
/// `Renderer.proposedSize` are writable for a container or a modifier that
/// needs to push state in, but such a mark must restore them.
public protocol Mark: Sendable {
	/// emit this mark's operators into the renderer.
	func write(to renderer: inout Renderer)

	/// the size this mark occupies given `proposal` under `context`'s style.
	///
	/// a mark renders at exactly this size (the measure/write agreement
	/// invariant — containers place children by it). `nil` on an axis means
	/// unconstrained; fixed-geometry marks report their authored size and
	/// ignore the proposal.
	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size

	/// break this mark so the fitting piece occupies at most `available`
	/// points of height at `width`, and report the piece carried onward.
	///
	/// `nil` means the mark does not break — the paginator then places it
	/// whole or moves it to the next page. a conformer must return a runover
	/// strictly smaller than the receiver, so repeated splitting terminates.
	/// the default implementation returns `nil`: a mark is atomic unless it
	/// says otherwise.
	func split(available: Double, width: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)?
}

extension Mark {
	/// the default: this mark does not break.
	public func split(available: Double, width: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)? {
		nil
	}
}

// MARK: - BreakControlling Protocol

/// a mark that asks the paginator for a page-break policy.
///
/// `.pageBreak()` and `.keepWithNext()` are modifiers that conform; the
/// paginator interrogates a flow child through this protocol, so the policy
/// is data on the mark rather than state the container has to be told about.
public protocol BreakControlling {
	/// start this mark at the top of a fresh page.
	var breaksBefore: Bool { get }
	/// keep this mark on the same page as the mark that follows it.
	var keepsWithNext: Bool { get }
}

// MARK: - PathMark Protocol

/// a `Mark` that draws a path and can state that path on demand.
///
/// a paint modifier ends its emission with a path-consuming operator (`f` or
/// `S`), and pdf has no paint that leaves the current path intact — so a
/// second paint in the same chain would find nothing to paint. a `PathMark`
/// answers `writePath` so the outer paint can state the geometry again, which
/// is what makes `.fill(...).stroke(...)` draw both paints.
public protocol PathMark: Mark {
	/// emit this mark's path only — no colour, no paint operator.
	func writePath(to renderer: inout Renderer)
}

// MARK: - MarkModifier Protocol

/// transforms the emission of a wrapped mark — the pdf analogue of a
/// `ViewModifier`.
///
/// a modifier runs setup, delegates to the wrapped mark, then runs teardown.
/// setup/teardown pairs must be balanced (`q`/`Q`), and any renderer state a
/// modifier changes must be restored so sibling marks stay independent.
public protocol MarkModifier: Sendable {
	/// apply this modifier around the wrapped content's emission.
	func apply<Content: Mark>(content: Content, to renderer: inout Renderer)

	/// measure the wrapped content under this modifier's style.
	///
	/// the default passes the measurement through unchanged, which suits
	/// every size-neutral modifier (paint, position, alignment). modifiers
	/// that change style or size override this mirror of `apply`.
	func sizeThatFits<Content: Mark>(
		content: Content, proposal: ProposedSize, in context: inout MeasureContext
	) -> Size

	/// split the wrapped content under this modifier's style, re-applying the
	/// modifier to both pieces.
	///
	/// the default splits the bare content and rewraps the pieces, which
	/// suits every size-neutral modifier — a split keeps its colour, its
	/// alignment, and its frame. a modifier that changes style or size
	/// overrides this mirror of `sizeThatFits` so the split measures and
	/// draws under the same style the whole mark would have.
	func split<Content: Mark>(
		content: Content, available: Double, width: Double, in context: inout MeasureContext
	) -> (fits: AnyMark, runover: AnyMark)?
}

extension MarkModifier {
	public func sizeThatFits<Content: Mark>(
		content: Content, proposal: ProposedSize, in context: inout MeasureContext
	) -> Size {
		content.sizeThatFits(proposal, in: &context)
	}

	public func split<Content: Mark>(
		content: Content, available: Double, width: Double, in context: inout MeasureContext
	) -> (fits: AnyMark, runover: AnyMark)? {
		guard let pieces = content.split(available: available, width: width, in: &context) else {
			return nil
		}
		return (
			AnyMark(ModifiedMark(content: pieces.fits, modifier: self)),
			AnyMark(ModifiedMark(content: pieces.runover, modifier: self))
		)
	}
}

// MARK: - ModifiedMark

/// a mark wrapped in one modifier — preserves both types through the chain,
/// so modifier composition needs no type erasure.
public struct ModifiedMark<Content: Mark, M: MarkModifier>: Mark {
	/// the wrapped mark.
	public let content: Content
	/// the modifier applied around `content`.
	public let modifier: M

	/// wrap `content` in `modifier`.
	public init(content: Content, modifier: M) {
		self.content = content
		self.modifier = modifier
	}

	public func write(to renderer: inout Renderer) {
		modifier.apply(content: content, to: &renderer)
	}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		modifier.sizeThatFits(content: content, proposal: proposal, in: &context)
	}

	public func split(available: Double, width: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)? {
		modifier.split(content: content, available: available, width: width, in: &context)
	}
}

// MARK: - PaintedPathMark

/// a path that a paint modifier has already painted: the wrapped geometry is
/// still available, but a paint operator consumed the current path — so a
/// paint wrapping this must state `writePath` again before its own operator.
public protocol PaintedPathMark: PathMark {}

/// a paint modifier does not move the geometry it paints, so a painted path is
/// still a path (and still knows the geometry to restate).
extension ModifiedMark: PathMark where Content: PathMark, M: PathTransparentModifier {
	public func writePath(to renderer: inout Renderer) {
		content.writePath(to: &renderer)
	}
}

/// the same shape, marked as already painted: a paint wrapping it must state
/// the path again (the conformance above supplies `writePath`).
extension ModifiedMark: PaintedPathMark where Content: PathMark, M: PathTransparentModifier {}

// MARK: - EmptyMark

/// draws nothing. used where a builder needs a no-op mark.
public struct EmptyMark: Mark {
	/// create the empty mark.
	public init() {}

	public func write(to renderer: inout Renderer) {}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		.zero
	}
}

// MARK: - AnyMark (type-erased wrapper)

/// type-erased mark for storing heterogeneous marks outside a builder.
public struct AnyMark: Mark {
	private let _write: @Sendable (inout Renderer) -> Void
	private let _size: @Sendable (ProposedSize, inout MeasureContext) -> Size
	private let _split: @Sendable (Double, Double, inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)?

	/// erase `mark`'s static type, keeping only `Mark`.
	public init<M: Mark>(_ mark: M) {
		self._write = { renderer in mark.write(to: &renderer) }
		self._size = { proposal, context in mark.sizeThatFits(proposal, in: &context) }
		self._split = { available, width, context in
			mark.split(available: available, width: width, in: &context)
		}
	}

	public func write(to renderer: inout Renderer) {
		_write(&renderer)
	}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		_size(proposal, &context)
	}

	public func split(available: Double, width: Double, in context: inout MeasureContext) -> (fits: AnyMark, runover: AnyMark)? {
		_split(available, width, &context)
	}
}

// MARK: - MarkBuilder

/// builds a mark list from a block: marks and mark lists both contribute.
@resultBuilder
public enum MarkBuilder {
	/// flatten the block's marks.
	public static func buildBlock(_ components: [any Mark]...) -> [any Mark] {
		components.flatMap { $0 }
	}
	/// wrap a single mark in a list.
	public static func buildExpression(_ expression: any Mark) -> [any Mark] {
		[expression]
	}
	/// pass a pre-built mark list through.
	public static func buildExpression(_ expression: [any Mark]) -> [any Mark] {
		expression
	}
	/// treat a missing `if` branch as empty.
	public static func buildOptional(_ component: [any Mark]?) -> [any Mark] {
		component ?? []
	}
	/// take the `if` branch.
	public static func buildEither(first: [any Mark]) -> [any Mark] {
		first
	}
	/// take the `else` branch.
	public static func buildEither(second: [any Mark]) -> [any Mark] {
		second
	}
	/// flatten a `for` loop's marks.
	public static func buildArray(_ components: [[any Mark]]) -> [any Mark] {
		components.flatMap { $0 }
	}
	/// pass an availability-gated block through.
	public static func buildLimitedAvailability(_ component: [any Mark]) -> [any Mark] {
		component
	}
}