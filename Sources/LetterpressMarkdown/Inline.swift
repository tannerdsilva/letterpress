// the inline layer: the smallest unit of marked-up text a run can carry.

// MARK: - InlineTraits

/// the character emphasis a run carries.
///
/// an option set rather than three booleans so a run's styling is one value
/// that composes (bold+italic) and compares cleanly.
public struct InlineTraits: OptionSet, Sendable, Hashable {
	public let rawValue: Int

	public init(rawValue: Int) {
		self.rawValue = rawValue
	}

	public static let bold = InlineTraits(rawValue: 1 << 0)
	public static let italic = InlineTraits(rawValue: 1 << 1)
	/// a `code span` — rendered in the monospace typeface.
	public static let code = InlineTraits(rawValue: 1 << 2)
}

// MARK: - InlineRun

/// one horizontally-flowing run of text with the emphasis it renders under.
///
/// the inline model is deliberately flat: nesting (bold inside a link, a code
/// span inside a heading) is resolved into the trait bits at parse time, so
/// the renderer never has to walk a tree to decide a font.
public struct InlineRun: Sendable, Hashable {
	/// the literal text of the run.
	public var text: String
	/// the emphasis this run renders under.
	public var traits: InlineTraits
	/// the target of a `[text](url)` link, when the run came from one.
	public var url: String?

	public init(_ text: String, traits: InlineTraits = [], url: String? = nil) {
		self.text = text
		self.traits = traits
		self.url = url
	}

	/// a run that forces a line break in the flow (a hard break: two trailing
	/// spaces or a trailing backslash).
	public static let lineBreak = InlineRun("\n")
}