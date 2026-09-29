import Foundation

// MARK: - Mark Protocol

/// a declarative drawing instruction — the pdf analogue of a `View`.
///
/// a `Mark` emits content-stream operators into a `Renderer`, and answers
/// how much space it occupies for a given proposal. marks are value types:
/// every mark is a pure description of what to draw, and the renderer is
/// the only thing that mutates while the document assembles.
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
