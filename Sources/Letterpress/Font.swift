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
///
/// - important: the cp1252 range is measured per glyph too. a flat fallback for
///   every non-ascii scalar mis-measures the glyphs the encoder really emits:
///   an ellipsis and an em dash are 1000/1000 em (4.66pt wider than a 556
///   fallback at 10.5pt) while a bullet is 350 and a right single quote is 222.
///   `WinAnsi.byte(for:)` is the shared mapping the encoder and this
///   measurement both read, so a glyph is measured as what it renders as.
public struct Font: Sendable, Hashable {
	/// the pdf `/BaseFont` name (e.g. "Helvetica-Bold").
	public let baseName: String

	/// advance widths in 1/1000 em for ascii 32-126, for this face.
	private let advances: [Int]

	/// advance widths in 1/1000 em for cp1252 0x80-0xFF, for this face.
	private let highAdvances: [Int]

	private init(_ baseName: String, advances: [Int], highAdvances: [Int]) {
		self.baseName = baseName
		self.advances = advances
		self.highAdvances = highAdvances
	}

	// MARK: the standard 14

	public static let helvetica = Font("Helvetica", advances: FontMetrics.helvetica, highAdvances: FontMetrics.helveticaHigh)
	public static let helveticaBold = Font("Helvetica-Bold", advances: FontMetrics.helveticaBold, highAdvances: FontMetrics.helveticaBoldHigh)
	public static let helveticaOblique = Font("Helvetica-Oblique", advances: FontMetrics.helvetica, highAdvances: FontMetrics.helveticaHigh)
	public static let helveticaBoldOblique = Font("Helvetica-BoldOblique", advances: FontMetrics.helveticaBold, highAdvances: FontMetrics.helveticaBoldHigh)
	public static let times = Font("Times-Roman", advances: FontMetrics.timesRoman, highAdvances: FontMetrics.timesRomanHigh)
	public static let timesBold = Font("Times-Bold", advances: FontMetrics.timesBold, highAdvances: FontMetrics.timesBoldHigh)
	public static let timesItalic = Font("Times-Italic", advances: FontMetrics.timesItalic, highAdvances: FontMetrics.timesItalicHigh)
	public static let timesBoldItalic = Font("Times-BoldItalic", advances: FontMetrics.timesBoldItalic, highAdvances: FontMetrics.timesBoldItalicHigh)
	public static let courier = Font("Courier", advances: FontMetrics.courier, highAdvances: FontMetrics.courierHigh)
	public static let courierBold = Font("Courier-Bold", advances: FontMetrics.courier, highAdvances: FontMetrics.courierHigh)
	public static let courierOblique = Font("Courier-Oblique", advances: FontMetrics.courier, highAdvances: FontMetrics.courierHigh)
	public static let courierBoldOblique = Font("Courier-BoldOblique", advances: FontMetrics.courier, highAdvances: FontMetrics.courierHigh)

	// MARK: measurement

	/// the advance in 1/1000 em for one cp1252 byte of this face.
	private func advance(forByte byte: UInt8) -> Int {
		switch byte {
		case 0x20 ... 0x7E: return advances[Int(byte) - 0x20]
		case 0x80 ... 0xFF: return highAdvances[Int(byte) - 0x80]
		default: return advances[Int(WinAnsi.fallback) - 0x20]
		}
	}

	/// the width of `string` at `size` points, in points.
	///
	/// widths sum the advance of the byte each scalar is actually written as,
	/// read from this face's own afm tables. a scalar with no winansi glyph
	/// degrades to `?` in the stream and is measured as this face's `?`.
	public func width(of string: String, size: Double) -> Double {
		var units = 0
		for scalar in string.unicodeScalars {
			units += advance(forByte: WinAnsi.byte(for: scalar) ?? WinAnsi.fallback)
		}
		return Double(units) * size / 1000
	}
}

// MARK: - FontMetrics

/// per-face advance widths in 1/1000 em, from the adobe afm files
/// (metric-compatible urw counterparts of the base-14 fonts), indexed by the
/// winansi byte each glyph is encoded as.
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

	/// the same face over cp1252 0x80-0xFF — the high half the encoder can
	/// emit. `Euro` (0x80) is absent from the urw afms, so that one slot
	/// falls back to this face's `?` advance.
	static let helveticaHigh: [Int] = [
		556, 350, 222, 556, 333, 1000, 556, 556, 333, 1000, 667, 333, 1000, 350, 611, 350,
		350, 222, 222, 333, 333, 350, 556, 1000, 333, 1000, 500, 333, 944, 350, 500, 667,
		278, 333, 556, 556, 556, 556, 260, 556, 333, 737, 370, 556, 584, 333, 737, 333,
		400, 584, 333, 333, 333, 556, 537, 278, 333, 333, 365, 556, 834, 834, 834, 611,
		667, 667, 667, 667, 667, 667, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278,
		722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611,
		556, 556, 556, 556, 556, 556, 889, 500, 556, 556, 556, 556, 278, 278, 278, 278,
		556, 556, 556, 556, 556, 556, 556, 584, 611, 556, 556, 556, 556, 500, 556, 500,
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

	/// the same face over cp1252 0x80-0xFF — the high half the encoder can
	/// emit. `Euro` (0x80) is absent from the urw afms, so that one slot
	/// falls back to this face's `?` advance.
	static let helveticaBoldHigh: [Int] = [
		611, 350, 278, 556, 500, 1000, 556, 556, 333, 1000, 667, 333, 1000, 350, 611, 350,
		350, 278, 278, 500, 500, 350, 556, 1000, 333, 1000, 556, 333, 944, 350, 500, 667,
		278, 333, 556, 556, 556, 556, 280, 556, 333, 737, 370, 556, 584, 333, 737, 333,
		400, 584, 333, 333, 333, 611, 556, 278, 333, 333, 365, 556, 834, 834, 834, 611,
		722, 722, 722, 722, 722, 722, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278,
		722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611,
		556, 556, 556, 556, 556, 556, 889, 556, 556, 556, 556, 556, 278, 278, 278, 278,
		611, 611, 611, 611, 611, 611, 611, 584, 611, 611, 611, 611, 611, 556, 611, 556,
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

	/// the same face over cp1252 0x80-0xFF — the high half the encoder can
	/// emit. `Euro` (0x80) is absent from the urw afms, so that one slot
	/// falls back to this face's `?` advance.
	static let timesRomanHigh: [Int] = [
		444, 350, 333, 500, 444, 1000, 500, 500, 333, 1000, 556, 333, 889, 350, 611, 350,
		350, 333, 333, 444, 444, 350, 500, 1000, 333, 980, 389, 333, 722, 350, 444, 722,
		250, 333, 500, 500, 500, 500, 200, 500, 333, 760, 276, 500, 564, 333, 760, 333,
		400, 564, 300, 300, 333, 500, 453, 250, 333, 300, 310, 500, 750, 750, 750, 444,
		722, 722, 722, 722, 722, 722, 889, 667, 611, 611, 611, 611, 333, 333, 333, 333,
		722, 722, 722, 722, 722, 722, 722, 564, 722, 722, 722, 722, 722, 722, 556, 500,
		444, 444, 444, 444, 444, 444, 667, 444, 444, 444, 444, 444, 278, 278, 278, 278,
		500, 500, 500, 500, 500, 500, 500, 564, 500, 500, 500, 500, 500, 500, 500, 500,
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

	/// the same face over cp1252 0x80-0xFF — the high half the encoder can
	/// emit. `Euro` (0x80) is absent from the urw afms, so that one slot
	/// falls back to this face's `?` advance.
	static let timesBoldHigh: [Int] = [
		500, 350, 333, 500, 500, 1000, 500, 500, 333, 1000, 556, 333, 1000, 350, 667, 350,
		350, 333, 333, 500, 500, 350, 500, 1000, 333, 1000, 389, 333, 722, 350, 444, 722,
		250, 333, 500, 500, 500, 500, 220, 500, 333, 747, 300, 500, 570, 333, 747, 333,
		400, 570, 300, 300, 333, 556, 540, 250, 333, 300, 330, 500, 750, 750, 750, 500,
		722, 722, 722, 722, 722, 722, 1000, 722, 667, 667, 667, 667, 389, 389, 389, 389,
		722, 722, 778, 778, 778, 778, 778, 570, 778, 722, 722, 722, 722, 722, 611, 556,
		500, 500, 500, 500, 500, 500, 722, 444, 444, 444, 444, 444, 278, 278, 278, 278,
		500, 556, 500, 500, 500, 500, 500, 570, 500, 556, 556, 556, 556, 500, 556, 500,
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

	/// the same face over cp1252 0x80-0xFF — the high half the encoder can
	/// emit. `Euro` (0x80) is absent from the urw afms, so that one slot
	/// falls back to this face's `?` advance.
	static let timesItalicHigh: [Int] = [
		500, 350, 333, 500, 556, 889, 500, 500, 333, 1000, 500, 333, 944, 350, 556, 350,
		350, 333, 333, 556, 556, 350, 500, 889, 333, 980, 389, 333, 667, 350, 389, 556,
		250, 389, 500, 500, 500, 500, 275, 500, 333, 760, 276, 500, 675, 333, 760, 333,
		400, 675, 300, 300, 333, 500, 523, 250, 333, 300, 310, 500, 750, 750, 750, 500,
		611, 611, 611, 611, 611, 611, 889, 667, 611, 611, 611, 611, 333, 333, 333, 333,
		722, 667, 722, 722, 722, 722, 722, 675, 722, 722, 722, 722, 722, 556, 611, 500,
		500, 500, 500, 500, 500, 500, 667, 444, 444, 444, 444, 444, 278, 278, 278, 278,
		500, 500, 500, 500, 500, 500, 500, 675, 500, 500, 500, 500, 500, 444, 500, 444,
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

	/// the same face over cp1252 0x80-0xFF — the high half the encoder can
	/// emit. `Euro` (0x80) is absent from the urw afms, so that one slot
	/// falls back to this face's `?` advance.
	static let timesBoldItalicHigh: [Int] = [
		500, 350, 333, 500, 500, 1000, 500, 500, 333, 1000, 556, 333, 944, 350, 611, 350,
		350, 333, 333, 500, 500, 350, 500, 1000, 333, 1000, 389, 333, 722, 350, 389, 611,
		250, 389, 500, 500, 500, 500, 220, 500, 333, 747, 266, 500, 606, 333, 747, 333,
		400, 570, 300, 300, 333, 576, 500, 250, 333, 300, 300, 500, 750, 750, 750, 500,
		667, 667, 667, 667, 667, 667, 944, 667, 667, 667, 667, 667, 389, 389, 389, 389,
		722, 722, 722, 722, 722, 722, 722, 570, 722, 722, 722, 722, 722, 611, 611, 500,
		500, 500, 500, 500, 500, 500, 722, 444, 444, 444, 444, 444, 278, 278, 278, 278,
		500, 556, 500, 500, 500, 500, 500, 570, 500, 556, 556, 556, 556, 444, 500, 444,
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

	/// the same face over cp1252 0x80-0xFF — the high half the encoder can
	/// emit. `Euro` (0x80) is absent from the urw afms, so that one slot
	/// falls back to this face's `?` advance.
	static let courierHigh: [Int] = [
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
		600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600,
	]

}
