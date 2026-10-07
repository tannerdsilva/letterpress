import Foundation

// MARK: - Font

/// a base-14 pdf font, referenced by name — never embedded.
///
/// the standard 14 fonts are guaranteed present in every pdf reader, so no
/// font data is shipped. the advance widths for every one of the twelve faces
/// are compiled in as static data so text measurement, alignment, and wrapping
/// are exact.
///
/// - important: a face carries its OWN advances — they are not a per-family
///   property. Helvetica-Bold differs from Helvetica in 43 of the 95 printable
///   ascii glyphs, and Times-Bold / Times-Italic / Times-BoldItalic likewise
///   differ from Times-Roman. measuring a bold face with the regular table
///   under-reports its width (bold `zero-dependency` by 5.23pt at 10.5pt against
///   a 2.92pt space), which places the following word inside it. only the
///   oblique faces are metric-identical to their upright sibling, and only
///   courier is uniform across all four of its faces.
public struct Font: Sendable, Hashable {
	/// the pdf `/BaseFont` name (e.g. "Helvetica-Bold").
	public let baseName: String

	/// advance widths in 1/1000 em for ascii 32-126, for this face.
	private let advances: [Int]

	private let fallbackWidth: Double = 556

	private init(_ baseName: String, advances: [Int]) {
		self.baseName = baseName
		self.advances = advances
	}

	// MARK: the standard 14

	public static let helvetica = Font("Helvetica", advances: FontMetrics.helvetica)
	public static let helveticaBold = Font("Helvetica-Bold", advances: FontMetrics.helveticaBold)
	public static let helveticaOblique = Font("Helvetica-Oblique", advances: FontMetrics.helvetica)
	public static let helveticaBoldOblique = Font("Helvetica-BoldOblique", advances: FontMetrics.helveticaBold)

	public static let times = Font("Times-Roman", advances: FontMetrics.timesRoman)
	public static let timesBold = Font("Times-Bold", advances: FontMetrics.timesBold)
	public static let timesItalic = Font("Times-Italic", advances: FontMetrics.timesItalic)
	public static let timesBoldItalic = Font("Times-BoldItalic", advances: FontMetrics.timesBoldItalic)

	public static let courier = Font("Courier", advances: FontMetrics.courier)
	public static let courierBold = Font("Courier-Bold", advances: FontMetrics.courier)
	public static let courierOblique = Font("Courier-Oblique", advances: FontMetrics.courier)
	public static let courierBoldOblique = Font("Courier-BoldOblique", advances: FontMetrics.courier)

	// MARK: measurement

	/// the width of `string` at `size` points, in points.
	///
	/// widths sum this face's per-glyph advance (1/1000 em units) over the ascii
	/// printable range 32-126 from its own afm table. glyphs outside that range
	/// (non-latin, controls) fall back to a fixed advance, which keeps
	/// `width(of:)` consistent with the '?' those glyphs render as.
	public func width(of string: String, size: Double) -> Double {
		var units = 0.0
		for scalar in string.unicodeScalars {
			if scalar.value >= 32 && scalar.value <= 126 {
				units += Double(advances[Int(scalar.value - 32)])
			} else {
				units += fallbackWidth
			}
		}
		return units * size / 1000
	}
}

// MARK: - FontMetrics

/// per-face advance widths in 1/1000 em for ascii 32-126, from the adobe afm
/// files (metric-compatible urw counterparts of the base-14 fonts).
private enum FontMetrics {
	/// Helvetica (regular) — also serves Helvetica-Oblique.
	static let helvetica: [Int] = [
		278, 278, 355, 556, 556, 889, 667, 222, 333, 333, 389, 584, 278, 333, 278, 278,
		556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
		1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
		667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
		222, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
		556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
	]

	/// Helvetica-Bold — also serves Helvetica-BoldOblique.
	static let helveticaBold: [Int] = [
		278, 333, 474, 556, 556, 889, 722, 278, 333, 333, 389, 584, 278, 333, 278, 278,
		556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,
		975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,
		667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,
		278, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
		611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584,
	]

	/// Times-Roman.
	static let timesRoman: [Int] = [
		250, 333, 408, 500, 500, 833, 778, 333, 333, 333, 500, 564, 250, 333, 250, 278,
		500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 278, 278, 564, 564, 564, 444,
		921, 722, 667, 667, 722, 611, 556, 722, 722, 333, 389, 722, 611, 889, 722, 722,
		556, 722, 667, 556, 611, 722, 722, 944, 722, 722, 611, 333, 278, 333, 469, 500,
		333, 444, 500, 444, 500, 444, 333, 500, 500, 278, 278, 500, 278, 778, 500, 500,
		500, 500, 333, 389, 278, 500, 500, 722, 500, 500, 444, 480, 200, 480, 541,
	]

	/// Times-Bold.
	static let timesBold: [Int] = [
		250, 333, 555, 500, 500, 1000, 833, 333, 333, 333, 500, 570, 250, 333, 250, 278,
		500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 570, 570, 570, 500,
		930, 722, 667, 722, 722, 667, 611, 778, 778, 389, 500, 778, 667, 944, 722, 778,
		611, 778, 722, 556, 667, 722, 722, 1000, 722, 722, 667, 333, 278, 333, 581, 500,
		333, 500, 556, 444, 556, 444, 333, 500, 556, 278, 333, 556, 278, 833, 556, 500,
		556, 556, 444, 389, 333, 556, 500, 722, 500, 500, 444, 394, 220, 394, 520,
	]

	/// Times-Italic.
	static let timesItalic: [Int] = [
		250, 333, 420, 500, 500, 833, 778, 333, 333, 333, 500, 675, 250, 333, 250, 278,
		500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 675, 675, 675, 500,
		920, 611, 611, 667, 722, 611, 611, 722, 722, 333, 444, 667, 556, 833, 667, 722,
		611, 722, 611, 500, 556, 722, 611, 833, 611, 556, 556, 389, 278, 389, 422, 500,
		333, 500, 500, 444, 500, 444, 278, 500, 500, 278, 278, 444, 278, 722, 500, 500,
		500, 500, 389, 389, 278, 500, 444, 667, 444, 444, 389, 400, 275, 400, 541,
	]

	/// Times-BoldItalic.
	static let timesBoldItalic: [Int] = [
		250, 389, 555, 500, 500, 833, 778, 333, 333, 333, 500, 570, 250, 333, 250, 278,
		500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 570, 570, 570, 500,
		832, 667, 667, 667, 722, 667, 667, 722, 778, 389, 500, 667, 611, 889, 722, 722,
		611, 722, 667, 556, 611, 722, 667, 889, 667, 611, 611, 333, 278, 333, 570, 500,
		333, 500, 500, 444, 500, 444, 333, 500, 556, 278, 278, 500, 278, 778, 556, 500,
		500, 500, 389, 389, 278, 556, 444, 667, 500, 444, 389, 348, 220, 348, 570,
	]

	/// Courier — monospaced, so all four faces share it.
	static let courier: [Int] = [
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
	]
}
