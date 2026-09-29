import Foundation

// MARK: - Color

/// an rgba color in the pdf device-rgb color space.
public struct Color: Sendable, Hashable {
	public let r: Double
	public let g: Double
	public let b: Double
	public let alpha: Double

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

	public static let clear = Color(r: 0, g: 0, b: 0, alpha: 0)
	public static let black = Color(r: 0, g: 0, b: 0)
	public static let white = Color(r: 1, g: 1, b: 1)

	public static let gray = Color(hex: 0x6B7280)
	public static let lightGray = Color(hex: 0xD1D5DB)
	public static let darkGray = Color(hex: 0x374151)

	public static let red = Color(hex: 0xDC2626)
	public static let orange = Color(hex: 0xEA580C)
	public static let amber = Color(hex: 0xD97706)
	public static let yellow = Color(hex: 0xCA8A04)
	public static let green = Color(hex: 0x16A34A)
	public static let teal = Color(hex: 0x0D9488)
	public static let sky = Color(hex: 0x0284C7)
	public static let blue = Color(hex: 0x2563EB)
	public static let indigo = Color(hex: 0x4F46E5)
	public static let purple = Color(hex: 0x9333EA)
	public static let pink = Color(hex: 0xDB2777)

	public static let ink = Color(hex: 0x111827)
	public static let slate = Color(hex: 0x475569)
}
