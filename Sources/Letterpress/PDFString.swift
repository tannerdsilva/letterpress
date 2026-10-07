import Foundation

// MARK: - WinAnsi

/// the single source of truth for "which cp1252 byte does this scalar become".
///
/// the encoder (`pdfEscape`) and the measurer (`Font.width`) both read this
/// mapping, so a glyph can never be measured as one thing and drawn as
/// another. a scalar with no winansi byte degrades to `?` in the stream and is
/// measured as the face's `?` advance.
enum WinAnsi {
	/// the cp1252 byte `scalar` is written as, or `nil` when the scalar has no
	/// winansi glyph.
	static func byte(for scalar: Unicode.Scalar) -> UInt8? {
		switch scalar.value {
		// ascii printable, and the latin-1 / cp1252 visible range, are their
		// own byte.
		case 0x20 ... 0x7E, 0x80 ... 0xFF:
			return UInt8(scalar.value)
		// typographic punctuation → its cp1252 slot in 0x80-0x9F.
		case 0x20AC: return 0x80   // €
		case 0x201A: return 0x82   // ‚
		case 0x0192: return 0x83   // ƒ
		case 0x201E: return 0x84   // „
		case 0x2026: return 0x85   // …
		case 0x2020: return 0x86   // †
		case 0x2021: return 0x87   // ‡
		case 0x02C6: return 0x88   // ˆ
		case 0x2030: return 0x89   // ‰
		case 0x0160: return 0x8A   // Š
		case 0x2039: return 0x8B   // ‹
		case 0x0152: return 0x8C   // Œ
		case 0x017D: return 0x8E   // Ž
		case 0x2018: return 0x91   // ‘
		case 0x2019: return 0x92   // ’
		case 0x201C: return 0x93   // “
		case 0x201D: return 0x94   // ”
		case 0x2022: return 0x95   // •
		case 0x2013: return 0x96   // –
		case 0x2014: return 0x97   // —
		case 0x02DC: return 0x98   // ˜
		case 0x2122: return 0x99   // ™
		case 0x0161: return 0x9A   // š
		case 0x203A: return 0x9B   // ›
		case 0x0153: return 0x9C   // œ
		case 0x017E: return 0x9E   // ž
		case 0x0178: return 0x9F   // Ÿ
		default: return nil
		}
	}

	/// the byte an unrepresentable scalar degrades to: the question mark.
	static let fallback: UInt8 = 0x3F
}

// MARK: - PDF String Escaping

/// encode a swift string as a pdf literal string body.
///
/// pdf literal strings carry BYTES, and a page's content stream is assembled
/// as a swift `String` that is utf-8-encoded on the way to bytes — so this
/// function emits 7-bit ascii only: every byte above 0x7E travels as a
/// three-digit octal escape (`\267` for the cp1252 middle dot, `\227` for an
/// em dash).
///
/// covers the characters pdf's standard 14 fonts understand: ascii verbatim,
/// the latin-1 / cp1252 visible range 0x80-0xFF as octal escapes, the common
/// typographic punctuation mapped to its cp1252 slot, everything else
/// degraded to '?'.
///
/// - note: a bare unicode scalar in the output would be utf-8-encoded
///   downstream, so `·` (U+00B7) would ship as `0xC2 0xB7` and rasterize as
///   `Â·` — the stream must stay 7-bit. glyphs outside WinAnsi (cyrillic, cjk,
///   emoji, ...) have no place in a base-14 font stream and become '?'.
///   `WinAnsi` is the shared mapping this and `Font.width` both read, so a
///   glyph is measured as exactly the advance it renders with.
public func pdfEscape(_ string: String) -> String {
	var out = String()
	out.reserveCapacity(string.count)
	for scalar in string.unicodeScalars {
		switch scalar.value {
		case 0x28: out += "\\("
		case 0x29: out += "\\)"
		case 0x5C: out += "\\\\"
		case 0x0A: out += "\\n"
		case 0x0D: out += "\\r"
		case 0x09: out += "\\t"
		default:
			let byte = WinAnsi.byte(for: scalar) ?? WinAnsi.fallback
			switch byte {
			// ascii printable goes verbatim …
			case 0x20 ... 0x7E:
				out.unicodeScalars.append(Unicode.Scalar(byte))
			// … and everything above it travels as an octal escape.
			default:
				out += octalEscape(UInt32(byte))
			}
		}
	}
	return out
}

/// a three-digit octal escape for one byte value (`0xB7` -> `\267`).
private func octalEscape(_ value: UInt32) -> String {
	var digits: [UInt8] = []
	var remaining = value
	for _ in 0 ..< 3 {
		digits.append(UInt8(48 + remaining % 8))
		remaining /= 8
	}
	return "\\" + String(decoding: digits.reversed(), as: UTF8.self)
}