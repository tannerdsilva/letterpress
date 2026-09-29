import Foundation

// MARK: - PDFNumber

/// a locale-independent fixed-point pdf number.
///
/// pdf grammar requires '.' as the decimal separator. `String(format:)`
/// honors the process locale (a German locale emits ','), so pdf numbers are
/// formatted with integer arithmetic instead — deterministic on every host.
public struct PDFNumber: Sendable, Hashable, CustomStringConvertible {
	public let value: Double
	public let decimals: Int

	public init(_ value: Double, decimals: Int = 2) {
		self.value = value
		self.decimals = decimals
	}

	public var description: String {
		Self.fixed(value, decimals)
	}

	/// format `value` with at most `decimals` fractional digits, rounded
	/// half-away-from-zero, '.' decimal separator, no exponent, and trailing
	/// zeros trimmed so whole numbers print as integers (`612`, not `612.00`).
	private static func fixed(_ value: Double, _ decimals: Int) -> String {
		precondition(decimals >= 0 && decimals <= 6, "decimals out of range: \(decimals)")
		let factor = Int(pow(10.0, Double(decimals)))
		let rounded = (value * Double(factor)).rounded()
		let negative = rounded < 0
		let magnitude = negative ? -rounded : rounded
		let whole = Int(magnitude) / factor
		let fraction = Int(magnitude) % factor
		var result = (negative ? "-" : "") + String(whole)
		if decimals > 0 {
			var digits = String(fraction)
			while digits.count < decimals {
				digits = "0" + digits
			}
			result += "." + digits
			while result.hasSuffix("0") {
				result.removeLast()
			}
			if result.hasSuffix(".") {
				result.removeLast()
			}
		}
		return result
	}
}
