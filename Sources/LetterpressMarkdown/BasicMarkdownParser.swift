import Letterpress

// block parsing: fenced code, headings, rules, blockquotes, lists, tables,
// paragraphs.

// MARK: - BasicMarkdownParser

/// the shipped parser: a focused, dependency-free subset of markdown.
///
/// supported blocks — atx (`#`) and setext (`===`/`---`) headings, paragraphs,
/// fenced code (``` / ~~~, with an info word), blockquotes, ordered and
/// unordered lists with one level of nesting per indent step, pipe tables
/// (GFM-style: a header row, a `| --- |` delimiter row with optional `:` alignment
/// markers, then body rows), thematic breaks.
/// supported inlines — `code spans`, `**strong**`, `*emphasis*`, `_inner_`,
/// `***both***`, `~~struck through~~`, `[links](url)`, !\[alt\](url), backslash
/// escapes, a handful of html entities, and hard breaks (two trailing spaces or
/// a trailing `\`).
///
/// deliberately out of scope: footnotes, reference links, task lists,
/// autolinks, raw html passthrough, and lazy blockquote continuation.
public struct BasicMarkdownParser: MarkdownParser {
	/// create the parser.
	public init() {}

	/// parse `source` using the supported subset.
	public func parse(_ source: String) -> MarkdownDocument {
		let normalized = normalizeNewlines(source)
		let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		var parser = BlockParser(lines: lines)
		return MarkdownDocument(blocks: parser.parseBlocks())
	}
}

// MARK: - LineSyntax

/// the compiled line-classification patterns.
///
/// `Regex` is not `Sendable`, so the patterns live in an instance value built
/// once per parse rather than in a shared global: the public parser stays
/// `Sendable` and no pattern is recompiled per line.
private struct LineSyntax {
	/// `## Heading ##` — up to three leading spaces, 1-6 hashes, optional text.
	let atxHeading = #/^ {0,3}(#{1,6})(?:[ \t]+(.*))?[ \t]*$/#
	/// `---`, `***`, `_ _ _` — three or more of one marker, spaces allowed.
	let thematicBreak = #/^ {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$/#
	/// `===` or `---` underlining a preceding paragraph line.
	let setextUnderline = #/^ {0,3}(=+|-+)[ \t]*$/#
	/// ```` ```lang ```` / `~~~` with an info string.
	let codeFence = #/^ {0,3}(`{3,}|~{3,})(.*)$/#
	/// `- item`, `* item`, `1. item`, `3) item`.
	let listItem = #/^ {0,3}([-*+]|\d{1,9}[.)])([ \t]+(.*))?$/#
	/// `> quoted`.
	let blockquote = #/^ {0,3}>.*$/#

	// MARK: classification

	/// the level and text of an atx heading line, or `nil`.
	func heading(_ line: String) -> (level: Int, text: String)? {
		guard let match = line.wholeMatch(of: atxHeading) else { return nil }
		var text = trim(match.2.map(String.init) ?? "")
		// a trailing run of `#` is the optional closing sequence.
		while text.hasSuffix("#") { text.removeLast() }
		return (match.1.count, trim(text))
	}

	func isRule(_ line: String) -> Bool {
		line.wholeMatch(of: thematicBreak) != nil
	}

	/// the heading level a setext underline denotes (1 for `=`, 2 for `-`).
	func setextLevel(_ line: String) -> Int? {
		guard let match = line.wholeMatch(of: setextUnderline) else { return nil }
		return match.1.first == "=" ? 1 : 2
	}

	/// a code fence's marker character, run length, and trimmed info string.
	func fence(_ line: String) -> (char: Character, count: Int, info: String)? {
		guard let match = line.wholeMatch(of: codeFence), let char = match.1.first else { return nil }
		return (char, match.1.count, trim(match.2))
	}

	/// a parsed list marker, or `nil`.
	func listMarker(_ line: String) -> ListMarker? {
		guard let match = line.wholeMatch(of: listItem), let first = match.1.first else { return nil }
		let marker = match.1
		let content = match.3.map(String.init) ?? ""
		let indent = leadingColumns(line)
		if first == "-" || first == "*" || first == "+" {
			return ListMarker(ordered: false, start: 1, contentIndent: indent + marker.count + 1, content: content)
		}
		return ListMarker(
			ordered: true,
			start: Int(marker.dropLast()) ?? 1,
			contentIndent: indent + marker.count + 1,
			content: content
		)
	}

	func isQuote(_ line: String) -> Bool {
		line.wholeMatch(of: blockquote) != nil
	}
}

// MARK: - BlockParser

private struct BlockParser {
	let lines: [String]
	let syntax: LineSyntax
	var index = 0

	init(lines: [String], syntax: LineSyntax = LineSyntax()) {
		self.lines = lines
		self.syntax = syntax
	}

	mutating func parseBlocks() -> [Block] {
		var blocks: [Block] = []
		while index < lines.count {
			let line = lines[index]
			if isBlank(line) {
				index += 1
				continue
			}
			if let block = parseFence() { blocks.append(block); continue }
			if let block = parseATXHeading() { blocks.append(block); continue }
			if syntax.isRule(line) { index += 1; blocks.append(.rule); continue }
			if let block = parseBlockquote() { blocks.append(block); continue }
			if let block = parseList() { blocks.append(block); continue }
			if let block = parseTable() { blocks.append(block); continue }
			if let block = parseParagraph() { blocks.append(block); continue }
			// unreachable in practice; advance so a surprise cannot spin.
			index += 1
		}
		return blocks
	}

	// MARK: fenced code

	private mutating func parseFence() -> Block? {
		guard let fence = syntax.fence(lines[index]) else { return nil }
		index += 1
		var body: [String] = []
		while index < lines.count {
			if let closing = syntax.fence(lines[index]), closing.char == fence.char,
			   closing.count >= fence.count, closing.info.isEmpty {
				index += 1
				break
			}
			body.append(lines[index])
			index += 1
		}
		let language = fence.info.isEmpty ? nil : String(fence.info.prefix { $0 != " " && $0 != "\t" })
		return .code(language: language, text: body.joined(separator: "\n"))
	}

	// MARK: headings

	private mutating func parseATXHeading() -> Block? {
		guard let parsed = syntax.heading(lines[index]) else { return nil }
		index += 1
		return .heading(level: parsed.level, InlineParser.parse(parsed.text))
	}

	// MARK: blockquote

	private mutating func parseBlockquote() -> Block? {
		guard syntax.isQuote(lines[index]) else { return nil }
		var inner: [String] = []
		while index < lines.count, syntax.isQuote(lines[index]) {
			inner.append(stripQuoteMarker(lines[index]))
			index += 1
		}
		var parser = BlockParser(lines: inner, syntax: syntax)
		return .quote(parser.parseBlocks())
	}

	// MARK: lists

	private mutating func parseList() -> Block? {
		guard let first = syntax.listMarker(lines[index]) else { return nil }
		let ordered = first.ordered
		var items: [ListItem] = []

		while index < lines.count {
			guard let marker = syntax.listMarker(lines[index]), marker.ordered == ordered else { break }
			let indent = marker.contentIndent
			var itemLines: [String] = [marker.content]
			index += 1

			while index < lines.count {
				let line = lines[index]
				if isBlank(line) {
					// a blank line continues the item only when the next real
					// line is indented into it (a loose item), never when it
					// opens a sibling or a following top-level block.
					guard let next = nextNonBlank(from: index + 1), leadingColumns(lines[next]) >= indent
					else { break }
					itemLines.append("")
					index += 1
				} else if leadingColumns(line) >= indent {
					itemLines.append(dropColumns(line, indent))
					index += 1
				} else {
					break
				}
			}

			var parser = BlockParser(lines: itemLines, syntax: syntax)
			items.append(ListItem(blocks: parser.parseBlocks()))
			while index < lines.count, isBlank(lines[index]) { index += 1 }
		}

		return ordered ? .ordered(start: first.start, items) : .bullets(items)
	}

	// MARK: tables

	/// a GFM pipe table: a header line containing a `|`, a delimiter row
	/// (`| --- | :--: |`), then body rows. the delimiter row's cell count and
	/// each cell's `:` placement fix the column count and alignment.
	private mutating func parseTable() -> Block? {
		guard index + 1 < lines.count, lines[index].contains("|") else { return nil }
		guard let alignments = delimiterAlignments(lines[index + 1]) else { return nil }
		let headerCells = splitTableRow(lines[index])
		guard !headerCells.isEmpty, headerCells.count == alignments.count else { return nil }

		index += 2
		var rows: [TableRow] = []
		while index < lines.count, !isBlank(lines[index]), lines[index].contains("|") {
			var cells = splitTableRow(lines[index])
			// a ragged row is padded or trimmed to the header's column count.
			if cells.count < headerCells.count {
				cells.append(contentsOf: Array(repeating: "", count: headerCells.count - cells.count))
			} else if cells.count > headerCells.count {
				cells = Array(cells.prefix(headerCells.count))
			}
			rows.append(cells.map(InlineParser.parse))
			index += 1
		}

		return .table(Table(
			header: headerCells.map(InlineParser.parse),
			alignments: alignments,
			rows: rows
		))
	}

	// MARK: paragraphs

	private mutating func parseParagraph() -> Block? {
		var raw: [String] = []
		var setext: Int?

		while index < lines.count {
			let line = lines[index]
			if isBlank(line) { break }

			if !raw.isEmpty {
				if syntax.isRule(line) { break }
				if syntax.heading(line) != nil { break }
				if syntax.fence(line) != nil { break }
				if syntax.isQuote(line) { break }
				if let marker = syntax.listMarker(line), !marker.ordered || marker.start == 1 { break }
			}

			// a setext underline turns the whole paragraph into a heading.
			if index + 1 < lines.count, let level = syntax.setextLevel(lines[index + 1]) {
				raw.append(line)
				setext = level
				index += 2
				break
			}

			raw.append(line)
			index += 1
		}

		guard !raw.isEmpty else { return nil }
		let runs = InlineParser.parse(raw.joined(separator: "\n"))
		if let setext { return .heading(level: setext, runs) }
		return .paragraph(runs)
	}

	// MARK: lookahead

	private func nextNonBlank(from start: Int) -> Int? {
		var i = start
		while i < lines.count {
			if !isBlank(lines[i]) { return i }
			i += 1
		}
		return nil
	}
}

// MARK: - list markers

/// a parsed list marker: kind, start number, the column its content begins at,
/// and the content text on the marker's own line.
private struct ListMarker {
	let ordered: Bool
	let start: Int
	let contentIndent: Int
	let content: String
}

// MARK: - lexing helpers

/// collapse CRLF and lone CR line endings to LF, foundation-free.
func normalizeNewlines(_ source: String) -> String {
	var out = ""
	out.reserveCapacity(source.count)
	var previous: Character?
	for character in source {
		if character == "\r" {
			out.append("\n")
		} else if character == "\n" {
			if previous != "\r" { out.append("\n") }
		} else {
			out.append(character)
		}
		previous = character
	}
	return out
}

/// the leading-space column count, counting a tab as four columns.
func leadingColumns(_ line: String) -> Int {
	var columns = 0
	for character in line {
		if character == " " {
			columns += 1
		} else if character == "\t" {
			columns += 4
		} else {
			break
		}
	}
	return columns
}

/// drop `columns` columns of leading whitespace (a tab counts as four).
func dropColumns(_ line: String, _ columns: Int) -> String {
	var remaining = columns
	var rest = Substring(line)
	while remaining > 0, let first = rest.first {
		if first == " " {
			remaining -= 1
		} else if first == "\t" {
			remaining -= 4
		} else {
			break
		}
		rest = rest.dropFirst()
	}
	return String(rest)
}

func isBlank(_ line: String) -> Bool {
	line.allSatisfy { $0 == " " || $0 == "\t" }
}

// MARK: - table lexing

/// the column alignments a delimiter row declares, or `nil` when the line is
/// not a delimiter row (so the caller falls through to paragraph handling).
///
/// a delimiter cell is `-`, `:-`, `-:`, or `:-:` (spaces around it trimmed);
/// `:` at both ends centres, a trailing `:` right-aligns, and no `:` is the
/// default left alignment.
func delimiterAlignments(_ line: String) -> [TextAlignment]? {
	let cells = splitTableRow(line)
	guard !cells.isEmpty else { return nil }
	var alignments: [TextAlignment] = []
	for cell in cells {
		let text = trim(cell)
		guard !text.isEmpty else { return nil }
		var body = Substring(text)
		var leading = false
		var trailing = false
		if body.first == ":" { leading = true; body = body.dropFirst() }
		if body.last == ":" { trailing = true; body = body.dropLast() }
		guard !body.isEmpty, body.allSatisfy({ $0 == "-" }) else { return nil }
		alignments.append(leading && trailing ? .center : trailing ? .trailing : .leading)
	}
	return alignments
}

/// split a table line into trimmed cell strings.
///
/// a leading and a trailing `|` are optional; a `\|` is an escaped literal pipe
/// (kept for the inline parser to unescape); a `|` inside a `` code span `` does
/// not split the row.
func splitTableRow(_ line: String) -> [String] {
	let characters = Array(line)
	var cells: [String] = []
	var current = ""
	var inCode = false
	var codeRun = 0
	var i = 0

	while i < characters.count {
		let character = characters[i]

		// an escaped pipe is a literal, not a separator.
		if character == "\\", i + 1 < characters.count, characters[i + 1] == "|" {
			current.append(character)
			current.append(characters[i + 1])
			i += 2
			continue
		}

		// a backtick run toggles code-span state so `a|b` never splits.
		if character == "`" {
			var run = 0
			while i + run < characters.count, characters[i + run] == "`" { run += 1 }
			if inCode, run == codeRun { inCode = false } else if !inCode { inCode = true; codeRun = run }
			current.append(contentsOf: String(repeating: "`", count: run))
			i += run
			continue
		}

		if character == "|", !inCode {
			cells.append(current)
			current = ""
			i += 1
			continue
		}

		current.append(character)
		i += 1
	}
	cells.append(current)

	// drop the empty cell a leading or trailing `|` produces.
	if let first = cells.first, trim(first).isEmpty { cells.removeFirst() }
	if let last = cells.last, trim(last).isEmpty { cells.removeLast() }
	return cells.map(trim)
}

/// drop a leading `>` and one following space from a blockquote line.
func stripQuoteMarker(_ line: String) -> String {
	var rest = line.drop { $0 == " " }.dropFirst()
	if rest.first == " " { rest = rest.dropFirst() }
	return String(rest)
}

func trim(_ text: some StringProtocol) -> String {
	var slice = Substring(text)
	while let first = slice.first, first == " " || first == "\t" { slice = slice.dropFirst() }
	while let last = slice.last, last == " " || last == "\t" { slice = slice.dropLast() }
	return String(slice)
}