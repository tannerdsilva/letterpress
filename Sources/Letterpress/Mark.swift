import Foundation

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
}

extension MarkModifier {
	public func sizeThatFits<Content: Mark>(
		content: Content, proposal: ProposedSize, in context: inout MeasureContext
	) -> Size {
		content.sizeThatFits(proposal, in: &context)
	}
}

// MARK: - ModifiedMark

/// a mark wrapped in one modifier — preserves both types through the chain,
/// so modifier composition needs no type erasure.
public struct ModifiedMark<Content: Mark, M: MarkModifier>: Mark {
	public let content: Content
	public let modifier: M

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

	public init<M: Mark>(_ mark: M) {
		self._write = { renderer in mark.write(to: &renderer) }
		self._size = { proposal, context in mark.sizeThatFits(proposal, in: &context) }
	}

	public func write(to renderer: inout Renderer) {
		_write(&renderer)
	}

	public func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		_size(proposal, &context)
	}
}

// MARK: - MarkBuilder

@resultBuilder
public enum MarkBuilder {
	public static func buildBlock(_ components: [any Mark]...) -> [any Mark] {
		components.flatMap { $0 }
	}
	public static func buildExpression(_ expression: any Mark) -> [any Mark] {
		[expression]
	}
	public static func buildExpression(_ expression: [any Mark]) -> [any Mark] {
		expression
	}
	public static func buildOptional(_ component: [any Mark]?) -> [any Mark] {
		component ?? []
	}
	public static func buildEither(first: [any Mark]) -> [any Mark] {
		first
	}
	public static func buildEither(second: [any Mark]) -> [any Mark] {
		second
	}
	public static func buildArray(_ components: [[any Mark]]) -> [any Mark] {
		components.flatMap { $0 }
	}
	public static func buildLimitedAvailability(_ component: [any Mark]) -> [any Mark] {
		component
	}
}
