import Foundation

// MARK: - Font

/// a base-14 pdf font, referenced by name — never embedded.
///
/// the standard 14 fonts are guaranteed present in every pdf reader, so no
/// font data is shipped. width metrics for the three families (helvetica,
/// times, courier) are compiled in as static data so text measurement,
/// alignment, and wrapping are exact.
public struct Font: Sendable, Hashable {
	/// the pdf `/BaseFont` name (e.g. "Helvetica-Bold").
	public let baseName: String
	private let family: Family
	private let fallbackWidth: Double = 556

	private init(_ baseName: String, family: Family) {
		self.baseName = baseName
		self.family = family
	}

	// MARK: the standard 14

	public static let helvetica = Font("Helvetica", family: .helvetica)
	public static let helveticaBold = Font("Helvetica-Bold", family: .helvetica)
	public static let helveticaOblique = Font("Helvetica-Oblique", family: .helvetica)
	public static let helveticaBoldOblique = Font("Helvetica-BoldOblique", family: .helvetica)

	public static let times = Font("Times-Roman", family: .times)
	public static let timesBold = Font("Times-Bold", family: .times)
	public static let timesItalic = Font("Times-Italic", family: .times)
	public static let timesBoldItalic = Font("Times-BoldItalic", family: .times)

	public static let courier = Font("Courier", family: .courier)
	public static let courierBold = Font("Courier-Bold", family: .courier)
	public static let courierOblique = Font("Courier-Oblique", family: .courier)
	public static let courierBoldOblique = Font("Courier-BoldOblique", family: .courier)

	// MARK: measurement

	/// the width of `string` at `size` points, in points.
	///
	/// widths sum the per-glyph advance (1/1000 em units) over the ascii
	/// printable range 32-126 from the family's afm table. glyphs outside
	/// that range (non-latin, controls) fall back to a fixed advance, which
	/// keeps `width(of:)` consistent with the '?' those glyphs render as.
	public func width(of string: String, size: Double) -> Double {
		let table = Self.spacing[family]!
		var units = 0.0
		for scalar in string.unicodeScalars {
			if scalar.value >= 32 && scalar.value <= 126 {
				units += Double(table[Int(scalar.value - 32)])
			} else {
				units += fallbackWidth
			}
		}
		return units * size / 1000
	}
}

// MARK: - Family

extension Font {
	private enum Family: Sendable, Hashable {
		case helvetica
		case times
		case courier
	}

	/// advance widths in 1/1000 em for ascii 32-126, from the adobe afm
	/// files (metric-compatible urw counterparts of the base-14 fonts).
	private static let spacing: [Family: [Int]] = [
		.helvetica: [
			278, 278, 355, 556, 556, 889, 667, 222, 333, 333, 389, 584, 278, 333, 278, 278,
			556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
			1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
			667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
			222, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
			556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
		],
		.times: [
			250, 333, 408, 500, 500, 833, 778, 333, 333, 333, 500, 564, 250, 333, 250, 278,
			500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 278, 278, 564, 564, 564, 444,
			921, 722, 667, 667, 722, 611, 556, 722, 722, 333, 389, 722, 611, 889, 722, 722,
			556, 722, 667, 556, 611, 722, 722, 944, 722, 722, 611, 333, 278, 333, 469, 500,
			333, 444, 500, 444, 500, 444, 333, 500, 500, 278, 278, 500, 278, 778, 500, 500,
			500, 500, 333, 389, 278, 500, 500, 722, 500, 500, 444, 480, 200, 480, 541,
		],
		.courier: [
			600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
			600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
			600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
			600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
			600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
			600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
		],
	]
}
