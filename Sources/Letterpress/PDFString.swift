import Foundation

// MARK: - PDF String Escaping

/// encode a swift string as a pdf literal string body.
///
/// pdf literal strings escape `(`, `)`, `\` and non-ASCII bytes via octal
/// escapes. this emits WinAnsi (cp1252) bytes for the characters pdf's
/// standard 14 fonts understand: ASCII verbatim, latin-1 letters in
/// 0xA1-0xFF verbatim, the common typographic punctuation mapped to its
/// cp1252 slot, everything else degraded to '?'.
///
/// - note: pdf strings carry bytes, not unicode — glyphs outside WinAnsi
///   (cyrillic, cjk, emoji, ...) have no place in a base-14 font stream and
///   become '?'. the width tables measure the same way, so `width(of:)`
///   stays consistent with what renders.
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
		case 0x20 ... 0x7E: out.unicodeScalars.append(scalar)
		case 0xA0 ... 0xFF: out.unicodeScalars.append(scalar)
		// typographic punctuation → cp1252 slots below 0xA0
		case 0x20AC: out += "\\200"   // €
		case 0x201A: out += "\\202"   // ‚
		case 0x0192: out += "\\203"   // ƒ
		case 0x201E: out += "\\204"   // „
		case 0x2026: out += "\\205"   // …
		case 0x2020: out += "\\206"   // †
		case 0x2021: out += "\\207"   // ‡
		case 0x02C6: out += "\\210"   // ˆ
		case 0x2030: out += "\\211"   // ‰
		case 0x0160: out += "\\212"   // Š
		case 0x2039: out += "\\213"   // ‹
		case 0x0152: out += "\\214"   // Œ
		case 0x017D: out += "\\215"   // Ž
		case 0x2018: out += "\\221"   // '
		case 0x2019: out += "\\222"   // '
		case 0x201C: out += "\\223"   // "
		case 0x201D: out += "\\224"   // "
		case 0x2022: out += "\\225"   // •
		case 0x2013: out += "\\226"   // –
		case 0x2014: out += "\\227"   // —
		case 0x02DC: out += "\\230"   // ˜
		case 0x2122: out += "\\231"   // ™
		case 0x0161: out += "\\232"   // š
		case 0x203A: out += "\\233"   // ›
		case 0x0153: out += "\\234"   // œ
		case 0x017E: out += "\\235"   // ž
		case 0x0178: out += "\\236"   // Ÿ
		default: out += "?"
		}
	}
	return out
}
