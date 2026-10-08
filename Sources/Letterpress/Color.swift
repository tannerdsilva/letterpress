import Foundation

// MARK: - Color

/// an rgba color in the pdf device-rgb color space.
public struct Color: Sendable, Hashable {
	/// the red component, clamped to `0...1`.
	public let r: Double
	/// the green component, clamped to `0...1`.
	public let g: Double
	/// the blue component, clamped to `0...1`.
	public let b: Double
	/// the opacity, clamped to `0...1` (`0` transparent, `1` opaque).
	public let alpha: Double

	/// create a color from components; each is clamped to `0...1`.
	public init(r: Double, g: Double, b: Double, alpha: Double = 1) {
		self.r = min(max(r, 0), 1)
		self.g = min(max(g, 0), 1)
		self.b = min(max(b, 0), 1)
		self.alpha = min(max(alpha, 0), 1)
	}

	/// `0xRRGGBB` hexadecimal color.
	public init(hex: UInt32, alpha: Double = 1) {
		self.init(
			r: Double((hex >> 16) & 0xFF) / 255,
			g: Double((hex >> 8) & 0xFF) / 255,
			b: Double(hex & 0xFF) / 255,
			alpha: alpha
		)
	}

	/// this color with `alpha` transparency.
	public func opacity(_ alpha: Double) -> Color {
		Color(r: r, g: g, b: b, alpha: alpha)
	}

	// MARK: palette

	/// fully transparent.
	public static let clear = Color(r: 0, g: 0, b: 0, alpha: 0)
	/// opaque black.
	public static let black = Color(r: 0, g: 0, b: 0)
	/// opaque white.
	public static let white = Color(r: 1, g: 1, b: 1)

	/// gray-500.
	public static let gray = Color(hex: 0x6B7280)
	/// gray-300.
	public static let lightGray = Color(hex: 0xD1D5DB)
	/// gray-700.
	public static let darkGray = Color(hex: 0x374151)

	/// red-600.
	public static let red = Color(hex: 0xDC2626)
	/// orange-600.
	public static let orange = Color(hex: 0xEA580C)
	/// amber-600.
	public static let amber = Color(hex: 0xD97706)
	/// yellow-600.
	public static let yellow = Color(hex: 0xCA8A04)
	/// green-600.
	public static let green = Color(hex: 0x16A34A)
	/// teal-600.
	public static let teal = Color(hex: 0x0D9488)
	/// sky-600.
	public static let sky = Color(hex: 0x0284C7)
	/// blue-600.
	public static let blue = Color(hex: 0x2563EB)
	/// indigo-600.
	public static let indigo = Color(hex: 0x4F46E5)
	/// purple-600.
	public static let purple = Color(hex: 0x9333EA)
	/// pink-600.
	public static let pink = Color(hex: 0xDB2777)

	/// gray-900; near-black for body text.
	public static let ink = Color(hex: 0x111827)
	/// slate-600; a muted blue-gray.
	public static let slate = Color(hex: 0x475569)
}
