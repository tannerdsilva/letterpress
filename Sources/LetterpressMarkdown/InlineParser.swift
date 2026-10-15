// inline scanning: emphasis, strikethrough, code spans, links, escapes,
// entities.
//
// the scanner is a single left-to-right pass with recursion for nested
// emphasis. every delimiter that has no matching closer degrades to literal
// text, so malformed markup renders as written rather than vanishing.

enum InlineParser {
	// MARK: entry

	/// parse `text` into a flat run list, resolving nesting into trait bits.
	static func parse(_ text: String) -> [InlineRun] {
		var out: [InlineRun] = []
		scan(Array(text), traits: [], url: nil, into: &out)
		return merged(out)
	}

	// MARK: scanning

	private static func scan(
		_ chars: [Character], traits: InlineTraits, url: String?, into out: inout [InlineRun]
	) {
		var buffer = ""
		var i = 0

		func flush() {
			if !buffer.isEmpty {
				out.append(InlineRun(buffer, traits: traits, url: url))
				buffer = ""
			}
		}

		while i < chars.count {
			let c = chars[i]

			// backslash escape: the next character is literal.
			if c == "\\", i + 1 < chars.count, chars[i + 1] != "\n" {
				buffer.append(chars[i + 1])
				i += 2
				continue
			}

			// `code span`
			if c == "`", let span = codeSpan(chars, at: i) {
				flush()
				out.append(InlineRun(span.text, traits: traits.union(.code), url: url))
				i = span.end
				continue
			}

			// [text](url)
			if c == "[", let found = link(chars, at: i) {
				flush()
				var nested: [InlineRun] = []
				scan(Array(found.label), traits: traits, url: found.destination, into: &nested)
				out.append(contentsOf: nested)
				i = found.end
				continue
			}

			// ![alt](url) — no image pipeline in the pdf, so the caption stands.
			if c == "!", i + 1 < chars.count, chars[i + 1] == "[", let found = link(chars, at: i + 1) {
				flush()
				let alt = found.label.isEmpty ? "[image]" : found.label
				out.append(InlineRun(alt, traits: traits, url: found.destination))
				i = found.end
				continue
			}

			// *emphasis* / **strong** / ***both***
			if c == "*" || c == "_", let found = emphasis(chars, at: i, char: c) {
				flush()
				let inner = String(chars[found.contentStart ..< found.contentEnd])
				var nested = traits
				if found.length >= 2 { nested.insert(.bold) }
				if found.length == 1 || found.length == 3 { nested.insert(.italic) }
				scan(Array(inner), traits: nested, url: url, into: &out)
				i = found.contentEnd + found.length
				continue
			}

			// ~~strikethrough~~
			if c == "~", let found = strike(chars, at: i) {
				flush()
				scan(
					Array(found.content), traits: traits.union(.strikethrough),
					url: url, into: &out)
				i = found.end
				continue
			}

			// &amp; and friends
			if c == "&", let decoded = entity(chars, at: i) {
				buffer.append(decoded.text)
				i = decoded.end
				continue
			}

			// a raw html tag is dropped; the text it wraps stands.
			if c == "<", let end = tagEnd(chars, at: i) {
				i = end
				continue
			}

			// breaks: two trailing spaces or a trailing backslash is a hard
			// break (a forced new run); anything else is a soft break (a space).
			if c == "\n" {
				if buffer.hasSuffix("  ") {
					while buffer.hasSuffix(" ") { buffer.removeLast() }
					flush()
					out.append(.lineBreak)
				} else if buffer.hasSuffix("\\") {
					buffer.removeLast()
					flush()
					out.append(.lineBreak)
				} else {
					buffer.append(" ")
				}
				i += 1
				continue
			}

			buffer.append(c)
			i += 1
		}

		flush()
	}

	// MARK: delimiters

	/// a `` ` `` run of `n` backticks closed by an equal run; the span text is
	/// space-trimmed when it starts and ends with a space and is not all spaces.
	private static func codeSpan(_ chars: [Character], at i: Int) -> (text: String, end: Int)? {
		let n = runLength(chars, at: i, of: "`")
		var j = i + n
		while j < chars.count {
			if chars[j] == "`" {
				let close = runLength(chars, at: j, of: "`")
				if close == n {
					var content = String(chars[(i + n) ..< j])
					if content.count >= 2, content.hasPrefix(" "), content.hasSuffix(" "),
					   !content.dropFirst().dropLast().isEmpty {
						content = String(content.dropFirst().dropLast())
					}
					return (content, j + n)
				}
				j += close
			} else {
				j += 1
			}
		}
		return nil
	}

	/// `[label](dest)`; returns `nil` when there is no `(destination)`, so a
	/// bare `[label]` stays literal text rather than silently losing brackets.
	private static func link(
		_ chars: [Character], at open: Int
	) -> (label: String, destination: String?, end: Int)? {
		guard open < chars.count, chars[open] == "[" else { return nil }
		var depth = 0
		var j = open
		while j < chars.count {
			if chars[j] == "[" {
				depth += 1
			} else if chars[j] == "]" {
				depth -= 1
				if depth == 0 { break }
			}
			j += 1
		}
		guard j < chars.count, depth == 0 else { return nil }
		let label = String(chars[(open + 1) ..< j])

		let openParen = j + 1
		guard openParen < chars.count, chars[openParen] == "(" else { return nil }
		var paren = 1
		var k = openParen + 1
		while k < chars.count {
			if chars[k] == "(" {
				paren += 1
			} else if chars[k] == ")" {
				paren -= 1
				if paren == 0 { break }
			}
			k += 1
		}
		guard k < chars.count else { return nil }
		let inside = String(chars[(openParen + 1) ..< k])
		return (label, destination(from: inside), k + 1)
	}

	/// the destination of a link: a `<...>` form verbatim, otherwise the first
	/// whitespace-delimited token (a title in quotes is ignored).
	private static func destination(from raw: String) -> String? {
		let trimmed = trim(raw)
		guard !trimmed.isEmpty else { return nil }
		if trimmed.hasPrefix("<"), let close = trimmed.firstIndex(of: ">") {
			return String(trimmed[trimmed.index(after: trimmed.startIndex) ..< close])
		}
		let token = trimmed.prefix { $0 != " " && $0 != "\t" }
		return token.isEmpty ? nil : String(token)
	}

	/// find the closing delimiter run for the emphasis opening at `i`.
	///
	/// tries the longest run first so `***x***` reads as bold+italic rather
	/// than strong-then-literal. `_` never opens or closes inside a word.
	private static func emphasis(
		_ chars: [Character], at i: Int, char c: Character
	) -> (length: Int, contentStart: Int, contentEnd: Int)? {
		let available = min(runLength(chars, at: i, of: c), 3)
		guard available >= 1 else { return nil }

		for length in stride(from: available, through: 1, by: -1) {
			let contentStart = i + length
			guard contentStart < chars.count, !chars[contentStart].isWhitespace else { continue }
			if c == "_", i > 0, isWord(chars[i - 1]) { continue }

			var j = contentStart
			while j < chars.count {
				if chars[j] == c {
					let closeLength = runLength(chars, at: j, of: c)
					if closeLength >= length {
						let before = j > 0 ? chars[j - 1] : " "
						let after = j + length < chars.count ? chars[j + length] : " "
						if !before.isWhitespace, j > contentStart {
							if c == "_", isWord(after) {
								j += closeLength
								continue
							}
							return (length, contentStart, j)
						}
					}
					j += max(closeLength, 1)
				} else {
					j += 1
				}
			}
		}
		return nil
	}

	/// a `~~struck~~` span: two tildes opening, two or more closing. a lone
	/// `~` stays literal, and a strike with no closer degrades to its own
	/// tildes rather than swallowing the rest of the line.
	private static func strike(_ chars: [Character], at i: Int) -> (content: String, end: Int)? {
		guard runLength(chars, at: i, of: "~") >= 2 else { return nil }
		var j = i + 2
		while j < chars.count {
			guard chars[j] == "~" else { j += 1; continue }
			let close = runLength(chars, at: j, of: "~")
			guard close >= 2 else { j += close; continue }
			let content = String(chars[(i + 2) ..< j])
			guard !content.isEmpty, !content.hasPrefix(" "), !content.hasSuffix(" ") else { return nil }
			return (content, j + close)
		}
		return nil
	}

	/// `&name;` / `&#nn;` / `&#xhh;` within a short window.
	private static func entity(_ chars: [Character], at i: Int) -> (text: String, end: Int)? {
		var j = i + 1
		let limit = min(chars.count, i + 12)
		while j < limit, chars[j] != ";" {
			guard chars[j].isLetter || chars[j].isNumber || chars[j] == "#" else { return nil }
			j += 1
		}
		guard j < chars.count, chars[j] == ";" else { return nil }
		guard let text = decodeEntity(String(chars[(i + 1) ..< j])) else { return nil }
		return (text, j + 1)
	}

	private static func decodeEntity(_ body: String) -> String? {
		switch body {
		case "amp": return "&"
		case "lt": return "<"
		case "gt": return ">"
		case "quot": return "\""
		case "apos": return "'"
		case "nbsp": return " "
		case "mdash": return "\u{2014}"
		case "ndash": return "\u{2013}"
		case "hellip": return "\u{2026}"
		default: break
		}
		if body.hasPrefix("#x") || body.hasPrefix("#X") {
			guard let value = UInt32(body.dropFirst(2), radix: 16),
			      let scalar = Unicode.Scalar(value) else { return nil }
			return String(Character(scalar))
		}
		if body.hasPrefix("#") {
			guard let value = UInt32(body.dropFirst()),
			      let scalar = Unicode.Scalar(value) else { return nil }
			return String(Character(scalar))
		}
		return nil
	}

	/// the index just past a `<...>` tag, when the bracket opens a plausible
	/// tag (`<tag`, `</tag`, `<!--`); otherwise `nil` leaves `<` literal.
	private static func tagEnd(_ chars: [Character], at i: Int) -> Int? {
		guard i + 1 < chars.count else { return nil }
		let next = chars[i + 1]
		guard next.isLetter || next == "/" || next == "!" || next == "?" else { return nil }
		var j = i + 1
		while j < chars.count, chars[j] != ">", chars[j] != "\n" { j += 1 }
		guard j < chars.count, chars[j] == ">" else { return nil }
		return j + 1
	}

	// MARK: helpers

	private static func runLength(_ chars: [Character], at i: Int, of c: Character) -> Int {
		var n = 0
		while i + n < chars.count, chars[i + n] == c { n += 1 }
		return n
	}

	private static func isWord(_ c: Character) -> Bool {
		c.isLetter || c.isNumber
	}

	/// join neighbouring runs that carry identical traits and link targets.
	private static func merged(_ runs: [InlineRun]) -> [InlineRun] {
		var out: [InlineRun] = []
		for run in runs where !run.text.isEmpty {
			if var last = out.last, last.traits == run.traits, last.url == run.url,
			   last.text != "\n", run.text != "\n" {
				last.text += run.text
				out[out.count - 1] = last
			} else {
				out.append(run)
			}
		}
		return out
	}
}