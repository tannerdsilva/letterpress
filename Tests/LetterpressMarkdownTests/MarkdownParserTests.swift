import Testing
import LetterpressMarkdown

// parser coverage: block structure, inline emphasis, and the degradation of
// malformed markup to literal text.

@Suite struct MarkdownParserTests {
	// MARK: headings

	@Test("atx headings carry their level and strip closing hashes")
	func atxHeadings() {
		let document = MarkdownDocument(parsing: """
		# one
		## two
		###### six
		####### seven is a paragraph
		## closed ##
		""")
		#expect(document.blocks.count == 5)
		guard case .heading(let l1, let t1) = document.blocks[0] else { Issue.record("not a heading"); return }
		#expect(l1 == 1)
		#expect(t1.map(\.text) == ["one"])
		guard case .heading(let l2, let t2) = document.blocks[1] else { Issue.record("not a heading"); return }
		#expect(l2 == 2)
		#expect(t2.map(\.text) == ["two"])
		guard case .heading(let l6, _) = document.blocks[2] else { Issue.record("not a heading"); return }
		#expect(l6 == 6)
		guard case .paragraph = document.blocks[3] else { Issue.record("seven hashes is not a heading"); return }
		guard case .heading(_, let closed) = document.blocks[4] else { Issue.record("not a heading"); return }
		#expect(closed.map(\.text) == ["closed"])
	}

	@Test("setext underlines promote a paragraph to a heading")
	func setextHeadings() {
		let document = MarkdownDocument(parsing: """
		Title
		=====

		Subtitle
		--------

		body text
		""")
		#expect(document.blocks.count == 3)
		guard case .heading(let l1, _) = document.blocks[0] else { Issue.record("not a heading"); return }
		#expect(l1 == 1)
		guard case .heading(let l2, _) = document.blocks[1] else { Issue.record("not a heading"); return }
		#expect(l2 == 2)
		guard case .paragraph = document.blocks[2] else { Issue.record("not a paragraph"); return }
	}

	// MARK: paragraphs

	@Test("soft-wrapped lines join into one paragraph")
	func softWrap() {
		let document = MarkdownDocument(parsing: "one line\ntwo line\nthree line")
		#expect(document.blocks.count == 1)
		guard case .paragraph(let runs) = document.blocks[0] else { Issue.record("not a paragraph"); return }
		#expect(runs.map(\.text).joined() == "one line two line three line")
	}

	// MARK: rules

	@Test("thematic breaks are recognised in every marker")
	func thematicBreaks() {
		for source in ["---", "***", "___", "- - -", "*  *  *"] {
			let document = MarkdownDocument(parsing: source)
			#expect(document.blocks.count == 1, "\(source)")
			if case .rule = document.blocks.first {} else { Issue.record("\(source) is not a rule") }
		}
		// and a bullet list is not a rule.
		let list = MarkdownDocument(parsing: "- item")
		if case .bullets = list.blocks.first {} else { Issue.record("'- item' should be a list") }
	}

	// MARK: lists

	@Test("bullet lists split into items")
	func bullets() {
		let document = MarkdownDocument(parsing: """
		- alpha
		- beta
		- gamma
		""")
		guard case .bullets(let items) = document.blocks.first else { Issue.record("not a list"); return }
		#expect(items.count == 3)
				guard case .paragraph(let first) = items[0].blocks.first else { Issue.record("item is not a paragraph"); return }
				#expect(first.map(\.text) == ["alpha"])
	}

	@Test("ordered lists keep their start number")
	func ordered() {
		let document = MarkdownDocument(parsing: """
		3) three
		4) four
		""")
		guard case .ordered(let start, let items) = document.blocks.first else { Issue.record("not an ordered list"); return }
		#expect(start == 3)
		#expect(items.count == 2)
	}

	@Test("a nested list becomes a block inside its item")
	func nested() {
		let document = MarkdownDocument(parsing: """
		- outer
		  - inner one
		  - inner two
		- second
		""")
		guard case .bullets(let items) = document.blocks.first else { Issue.record("not a list"); return }
		#expect(items.count == 2)
		let nested = items[0].blocks.contains { block in
			if case .bullets = block { return true }
			return false
		}
		#expect(nested)
	}

	// MARK: blockquote

	@Test("a blockquote wraps its quoted blocks")
	func blockquote() {
		let document = MarkdownDocument(parsing: """
		> quoted line
		> second line

		after
		""")
		#expect(document.blocks.count == 2)
		guard case .quote(let inner) = document.blocks[0] else { Issue.record("not a quote"); return }
		#expect(inner.count == 1)
		guard case .paragraph(let runs) = inner[0] else { Issue.record("quote holds no paragraph"); return }
		#expect(runs.map(\.text).joined() == "quoted line second line")
	}

	// MARK: code

	@Test("a fenced block keeps its language and body verbatim")
	func fencedCode() {
		let document = MarkdownDocument(parsing: """
		```swift
		let x = 1
		let y = 2
		```
		""")
		guard case .code(let language, let text) = document.blocks.first else { Issue.record("not code"); return }
		#expect(language == "swift")
		#expect(text == "let x = 1\nlet y = 2")
	}

	@Test("a tilde fence closes on tildes, not backticks")
	func tildeFence() {
		let document = MarkdownDocument(parsing: "~~~\n```\n~~~")
		guard case .code(_, let text) = document.blocks.first else { Issue.record("not code"); return }
		#expect(text == "```")
	}

	// MARK: inline

	@Test("inline emphasis resolves into trait bits")
	func inlineEmphasis() {
		let document = MarkdownDocument(parsing: "a **bold** b *ital* c ***both*** d `code`")
		guard case .paragraph(let runs) = document.blocks[0] else { Issue.record("not a paragraph"); return }
		let bold = runs.first { $0.text == "bold" }
		#expect(bold?.traits.contains(.bold) == true)
		let italic = runs.first { $0.text == "ital" }
		#expect(italic?.traits.contains(.italic) == true)
		let both = runs.first { $0.text == "both" }
		#expect(both?.traits.contains(.bold) == true)
		#expect(both?.traits.contains(.italic) == true)
		let code = runs.first { $0.text == "code" }
		#expect(code?.traits.contains(.code) == true)
	}

	@Test("underscores inside a word stay literal")
	func intrawordUnderscore() {
		let document = MarkdownDocument(parsing: "snake_case_name and _emph_")
		guard case .paragraph(let runs) = document.blocks[0] else { Issue.record("not a paragraph"); return }
		#expect(runs.contains { $0.text.contains("snake_case_name") })
		#expect(runs.contains { $0.text == "emph" && $0.traits.contains(.italic) })
	}

	@Test("links keep their label and destination, images keep alt text")
	func linksAndImages() {
		let document = MarkdownDocument(parsing: "[docs](https://example.com) and ![alt](pic.png)")
		guard case .paragraph(let runs) = document.blocks[0] else { Issue.record("not a paragraph"); return }
		let link = runs.first { $0.text == "docs" }
		#expect(link?.url == "https://example.com")
		let image = runs.first { $0.text == "alt" }
		#expect(image?.url == "pic.png")
	}

	@Test("escapes, entities, and hard breaks are handled")
	func escapesAndEntities() {
		let document = MarkdownDocument(parsing: "a \\* b &amp; c  \nd")
		guard case .paragraph(let runs) = document.blocks[0] else { Issue.record("not a paragraph"); return }
		#expect(runs.contains { $0.text.contains("*") })
		#expect(runs.contains { $0.text.contains("&") })
		#expect(runs.contains { $0.text == "\n" })
	}

	@Test("unmatched delimiters degrade to literal text")
	func malformed() {
		let document = MarkdownDocument(parsing: "an * unmatched star and a `tick")
		guard case .paragraph(let runs) = document.blocks[0] else { Issue.record("not a paragraph"); return }
		let joined = runs.map(\.text).joined()
		#expect(joined.contains("*"))
		#expect(joined.contains("`"))
	}

	// MARK: document

	@Test("the title is the first level-1 heading")
	func title() {
		#expect(MarkdownDocument(parsing: "# Report\n\nbody").title == "Report")
		#expect(MarkdownDocument(parsing: "## Not level one").title == nil)
	}

	@Test("an empty source yields an empty document")
	func empty() {
		#expect(MarkdownDocument(parsing: "").blocks.isEmpty)
		#expect(MarkdownDocument(parsing: "\n\n   \n").blocks.isEmpty)
	}
}