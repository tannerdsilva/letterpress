// MARK: - PDFNumber

/// a locale-independent fixed-point pdf number.
///
/// pdf grammar requires '.' as the decimal separator, and the process locale
/// must never get a say: the digits are produced with integer arithmetic, so
/// the same value spells the same way on every host.
public struct PDFNumber: Sendable, Hashable, CustomStringConvertible {
	/// the value being formatted.
	public let value: Double
	/// the maximum number of fractional digits kept.
	public let decimals: Int

	/// wrap `value` to format with at most `decimals` fractional digits.
	public init(_ value: Double, decimals: Int = 2) {
		self.value = value
		self.decimals = decimals
	}

	/// the pdf-grammar spelling of `value` — `.` separator, trailing zeros trimmed.
	public var description: String {
		Self.fixed(value, decimals)
	}

	/// format `value` with at most `decimals` fractional digits, rounded
	/// half-away-from-zero, '.' decimal separator, no exponent, and trailing
	/// zeros trimmed so whole numbers print as integers (`612`, not `612.00`).
	private static func fixed(_ value: Double, _ decimals: Int) -> String {
		precondition(decimals >= 0 && decimals <= 6, "decimals out of range: \(decimals)")
		// 10^decimals by repeated multiplication. `pow` would reach for the C
		// math library, and the exponent is a small preconditioned integer, so
		// integer arithmetic keeps this file — and the module — import-free.
		var factor = 1
		for _ in 0 ..< decimals {
			factor *= 10
		}
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
