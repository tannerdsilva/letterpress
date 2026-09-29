import Foundation

// MARK: - Point

/// a point in user space (x right, y down — same orientation as a web page).
public struct Point: Sendable, Hashable {
	public var x: Double
	public var y: Double

	public init(x: Double, y: Double) {
		self.x = x
		self.y = y
	}

	public static let zero = Point(x: 0, y: 0)
}

// MARK: - TextAlignment

/// horizontal text alignment relative to the position's anchor.
public enum TextAlignment: Sendable, Hashable {
	/// the position is the left edge of the text.
	case leading
	/// the position is the horizontal center of the text.
	case center
	/// the position is the right edge of the text.
	case trailing
}

// MARK: - Size

/// a magnitude in user space (points). width extends right, height extends
/// down — the same orientation as a web page.
public struct Size: Sendable, Hashable {
	public var width: Double
	public var height: Double

	public init(width: Double, height: Double) {
		self.width = width
		self.height = height
	}

	public static let zero = Size(width: 0, height: 0)
}

// MARK: - ProposedSize

/// a size proposal for a mark or container: `nil` on an axis means
/// "unconstrained — use your ideal size."
public struct ProposedSize: Sendable, Hashable {
	public var width: Double?
	public var height: Double?

	public init(width: Double? = nil, height: Double? = nil) {
		self.width = width
		self.height = height
	}

	public static let unconstrained = ProposedSize(width: nil, height: nil)
}

// MARK: - VerticalAlignment

/// vertical cross-axis alignment for horizontal containers.
public enum VerticalAlignment: Sendable, Hashable {
	case top
	case center
	case bottom
}
