import Foundation

// MARK: - Point

/// a point in user space (x right, y down — same orientation as a web page).
public struct Point: Sendable, Hashable {
	/// horizontal position; grows rightward.
	public var x: Double
	/// vertical position; grows downward (web-page orientation).
	public var y: Double

	/// create a point.
	public init(x: Double, y: Double) {
		self.x = x
		self.y = y
	}

	/// the origin.
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
	/// the horizontal extent.
	public var width: Double
	/// the vertical extent.
	public var height: Double

	/// create a size.
	public init(width: Double, height: Double) {
		self.width = width
		self.height = height
	}

	/// a zero size.
	public static let zero = Size(width: 0, height: 0)
}

// MARK: - ProposedSize

/// a size proposal for a mark or container: `nil` on an axis means
/// "unconstrained — use your ideal size."
public struct ProposedSize: Sendable, Hashable {
	/// the proposed width, or `nil` for unconstrained.
	public var width: Double?
	/// the proposed height, or `nil` for unconstrained.
	public var height: Double?

	/// create a proposal; `nil` on an axis means unconstrained.
	public init(width: Double? = nil, height: Double? = nil) {
		self.width = width
		self.height = height
	}

	/// a proposal with no constraint on either axis.
	public static let unconstrained = ProposedSize(width: nil, height: nil)
}

// MARK: - VerticalAlignment

/// vertical cross-axis alignment for horizontal containers.
public enum VerticalAlignment: Sendable, Hashable {
	/// align to the top edge.
	case top
	/// align to the vertical center.
	case center
	/// align to the bottom edge.
	case bottom
}
