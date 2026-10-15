import Letterpress

// MARK: - the document → pages bridge

extension MarkdownDocument {
	/// typeset this document into a paginated pdf under `style`.
	///
	/// the whole document is one `Galley`: it measures each top-level block at
	/// the text-column width and breaks between blocks, so a long document
	/// spills onto as many physical pages as it needs with no manual paging.
	/// paragraphs, headings, lists, code blocks, and quotes continue across
	/// page boundaries rather than being clipped. every page carries a
	/// hairline folio — the document title at the leading edge, the page
	/// number at the trailing edge.
	public func pdfDocument(style: MarkdownStyle = .standard) -> PDFDocument {
		PDFDocument { galley(style: style) }
	}

	/// typeset this document and report whatever the page box could not hold.
	///
	/// the same expansion `pdfDocument` performs, with the overflow report
	/// kept: `warnings` is empty for a document whose content fits. it is
	/// non-empty only for material no break policy can help — content nested
	/// where a break is meaningless, such as a single list item taller than
	/// the whole text column.
	public func pagination(style: MarkdownStyle = .standard) -> (pages: [PDFPage], warnings: [PaginationWarning]) {
		galley(style: style).pagination()
	}

	/// render this document straight to pdf bytes under `style`.
	public func render(style: MarkdownStyle = .standard) -> [UInt8] {
		pdfDocument(style: style).render()
	}

	private func galley(style: MarkdownStyle) -> Galley {
		let composer = BlockComposer(style: style, columnWidth: style.contentWidth)
		let marks: [any Mark] = blocks.enumerated().map { index, block in
			composer.mark(for: block, leading: index > 0)
		}
		let title = self.title
		return Galley(style.pageSize, margins: style.margins, spacing: 0) {
			marks
		}
		.furniture { page, total in
			folio(page: page, total: total, title: title, style: style)
		}
	}

	/// the running folio: a hairline across the measure, the document title
	/// (uppercase, tracked, truncated to fit) at the leading edge, and the
	/// page number at the trailing edge. furniture draws at the page origin,
	/// so every position here is absolute.
	private func folio(page: Int, total: Int, title: String?, style: MarkdownStyle) -> [any Mark] {
		let pageWidth = style.pageSize.width
		let pageHeight = style.pageSize.height
		let left = style.margins.leading
		let right = pageWidth - style.margins.trailing
		let ruleY = pageHeight - style.margins.bottom + 13
		let textY = ruleY + 5.5

		let font = style.typeface.font(bold: false, italic: false)
		let size = style.folioSize
		let tracking = 0.5

		var marks: [any Mark] = [
			Rect(x: left, y: ruleY, width: right - left, height: 0.5).fill(style.hairlineColor),
		]

		let number = "\(page) / \(total)"
		let numberWidth = measured(number, font: font, size: size, tracking: tracking)
		marks.append(
			ModifiedMark(
				content: Text(number).font(font, size: size).foregroundColor(style.mutedColor),
				modifier: TrackingModifier(amount: tracking, characters: number.count)
			)
			.at(x: right - numberWidth, y: textY)
		)

		if let title, !title.isEmpty {
			let label = truncated(
				title.uppercased(),
				width: max(right - left - numberWidth - 24, 40),
				font: font, size: size, tracking: tracking)
			marks.append(
				ModifiedMark(
					content: Text(label).font(font, size: size).foregroundColor(style.mutedColor),
					modifier: TrackingModifier(amount: tracking, characters: label.count)
				)
				.at(x: left, y: textY)
			)
		}
		return marks
	}
}

// MARK: - measurement helpers

/// the width `text` draws at: the face's advance plus the tracking `Tc` adds
/// after every character but the last.
private func measured(_ text: String, font: Font, size: Double, tracking: Double) -> Double {
	font.width(of: text, size: size) + tracking * Double(max(text.count - 1, 0))
}

/// `text` shortened with an ellipsis until it measures within `width`.
private func truncated(_ text: String, width: Double, font: Font, size: Double, tracking: Double) -> String {
	guard measured(text, font: font, size: size, tracking: tracking) > width else { return text }
	var result = text
	while !result.isEmpty,
	      measured(result + "…", font: font, size: size, tracking: tracking) > width {
		result.removeLast()
	}
	return result + "…"
}

// MARK: - BlockComposer

/// turns one block into one `Mark`, with its vertical rhythm baked into the
/// mark's own height so the galley can space blocks with a plain stack.
///
/// `columnWidth` is threaded explicitly: every child knows the width it wraps
/// against, so measurement and drawing never disagree about where a line ends.
struct BlockComposer {
	let style: MarkdownStyle
	let columnWidth: Double

	func mark(for block: Block, leading: Bool = true) -> any Mark {
		switch block {
		case .heading(let level, let runs):
			return heading(level: level, runs: runs, leading: leading)
		case .paragraph(let runs):
			return paragraph(runs)
		case .bullets(let items):
			return list(items: items, ordered: false, start: 1)
		case .ordered(let start, let items):
			return list(items: items, ordered: true, start: start)
		case .quote(let blocks):
			return quote(blocks)
		case .code(_, let text):
			return code(text)
		case .table(let table):
			return self.table(table)
		case .rule:
			return rule()
		}
	}

	// MARK: leaves

	/// one heading, treated by level: `h1` carries the document rule beneath it,
	/// `h2` a hairline above, `h3` sets in the accent ink, and `h5`/`h6` set as
	/// small tracked uppercase labels. headings set in the heading face and are
	/// bold by construction — the source's own emphasis bits never lighten a
	/// head, and the tracking is folded into the run so a label keeps its word
	/// spaces.
	private func heading(level: Int, runs: [InlineRun], leading: Bool) -> any Mark {
		let emphasised = runs.map { InlineRun($0.text, traits: $0.traits.union(.bold), url: $0.url) }
		let prepared = style.headingUppercased(level)
			? emphasised.map { InlineRun($0.text.uppercased(), traits: $0.traits, url: $0.url) }
			: emphasised

		let title = text(
			prepared,
			size: style.headingSize(level),
			lineHeight: 1.22,
			color: style.headingInk(level),
			typeface: style.headingTypeface,
			tracking: style.headingTracking(level))

		var children: [any Mark] = []
		// the gap above a head separates it from the block before it; the
		// document's first head has nothing above it to be separated from.
		if leading {
			children.append(Gap(height: style.headingSpaceAbove(level)))
		}
		if level == 2 {
			// the section rule: a hairline above the head, spanning the measure.
			children.append(Rect(x: 0, y: 0, width: columnWidth, height: 0.6).fill(style.hairlineColor))
			children.append(Gap(height: style.blockSpacing * 0.8))
		}
		children.append(title)
		if level == 1 {
			// the document rule: full measure, accent at its leading end.
			children.append(Gap(height: style.blockSpacing * 0.8))
			children.append(TitleRule(
				width: columnWidth,
				accentLength: 46,
				accent: style.accentColor,
				hairline: style.hairlineColor))
		}
		children.append(Gap(height: style.headingSpaceBelow(level)))
		return VStack(alignment: .leading, spacing: 0) { children }.keepWithNext()
	}

	private func paragraph(_ runs: [InlineRun]) -> any Mark {
		VStack(alignment: .leading, spacing: 0) {
			text(runs, size: style.bodySize, lineHeight: style.lineHeight, color: style.textColor, justify: style.justified)
			Gap(height: style.blockSpacing)
		}
	}

	/// a thematic break: a set ornament, more a breath than a wall.
	private func rule() -> any Mark {
		VStack(alignment: .leading, spacing: 0) {
			Gap(height: style.blockSpacing * 1.1)
			Ornament(
				span: min(150, columnWidth),
				columnWidth: columnWidth,
				ruleColor: style.hairlineColor,
				accent: style.accentColor,
				diamond: 2.0)
			Gap(height: style.blockSpacing * 1.1)
		}
	}

	private func code(_ text: String) -> any Mark {
		VStack(alignment: .leading, spacing: 0) {
			CodeBlock(
				text: text,
				width: columnWidth,
				codeTypeface: style.codeTypeface,
				size: CodeBlock.fittingSize(
					text: text,
					width: columnWidth,
					preferred: style.codeSize,
					minimum: style.codeSizeFloor,
					codeTypeface: style.codeTypeface),
				color: style.codeColor,
				background: style.codeBackground,
				accent: style.accentColor
			)
			Gap(height: style.blockSpacing)
		}
	}

	private func table(_ table: Table) -> any Mark {
		VStack(alignment: .leading, spacing: 0) {
			TableMark(
				header: table.header,
				alignments: table.alignments,
				rows: table.rows,
				width: columnWidth,
				bodySize: style.bodySize,
				lineHeight: style.lineHeight,
				typeface: style.typeface,
				codeTypeface: style.codeTypeface,
				textColor: style.textColor,
				linkColor: style.linkColor,
				codeColor: style.codeColor,
				headerBackground: style.tableHeaderBackground,
				borderColor: style.hairlineColor,
				accentColor: style.accentColor,
				padding: style.tableCellPadding
			)
			Gap(height: style.blockSpacing)
		}
	}

	private func text(
		_ runs: [InlineRun],
		size: Double,
		lineHeight: Double,
		color: Color,
		typeface: MarkdownTypeface? = nil,
		tracking: Double = 0,
		justify: Bool = false
	) -> RichText {
		RichText(
			runs: runs,
			width: columnWidth,
			size: size,
			lineHeight: lineHeight,
			typeface: typeface ?? style.typeface,
			codeTypeface: style.codeTypeface,
			color: color,
			linkColor: style.linkColor,
			codeColor: style.codeColor,
			tracking: tracking,
			justify: justify
		)
	}

	// MARK: containers

	private func list(items: [ListItem], ordered: Bool, start: Int) -> any Mark {
		let markers = items.enumerated().map { index, _ in
			ordered ? "\(start + index)." : "•"
		}
		let markerFont = style.typeface.font(bold: true, italic: false)
		// the bullet glyph is small in every base-14 face, so it is set a
		// touch larger than the text; the ordered numerals keep the body size.
		let markerSize = ordered ? style.bodySize : style.bodySize * 1.15
		// a larger size draws its baseline lower on the line, so lift the
		// bullet back onto the text baseline.
		let markerLift = (markerSize - style.bodySize) * 0.8
		let widest = markers.map { markerFont.width(of: $0, size: markerSize) }.max() ?? 0
		// the bullet measures at the fallback advance, so reserve at least a
		// digit's width plus a small gutter.
		let markerColumn = (max(widest, markerFont.width(of: "0", size: markerSize)) + 5).rounded(.up)
		let itemWidth = max(columnWidth - markerColumn, 1)
		let inner = BlockComposer(style: style, columnWidth: itemWidth)

		let itemMarks: [any Mark] = items.enumerated().map { index, item in
			HStack(alignment: .top, spacing: 0) {
				Text(markers[index])
					.font(markerFont, size: markerSize)
					.foregroundColor(style.accentColor)
					.at(x: 0, y: -markerLift)
					.frame(minWidth: markerColumn, alignment: .leading)
				VStack(alignment: .leading, spacing: 0) {
					itemContent(item.blocks, composer: inner)
				}
			}
		}

		return VStack(alignment: .leading, spacing: style.itemSpacing) {
			itemMarks
			Gap(height: style.blockSpacing)
		}
	}

	/// an item's blocks. the common single-paragraph item is composed without
	/// the paragraph's trailing rhythm, so `itemSpacing` is the whole gap
	/// between items instead of stacking on top of a block gap.
	private func itemContent(_ blocks: [Block], composer: BlockComposer) -> [any Mark] {
		if blocks.count == 1, case .paragraph(let runs) = blocks[0] {
			return [composer.text(
				runs,
				size: composer.style.bodySize,
				lineHeight: composer.style.lineHeight,
				color: composer.style.textColor,
				justify: composer.style.justified)]
		}
		return blocks.map { composer.mark(for: $0) }
	}

	/// a block quote: an accent bar beside the quoted blocks, which set a
	/// touch smaller in the muted quote ink.
	private func quote(_ blocks: [Block]) -> any Mark {
		let indent: Double = 16
		let barWidth: Double = 3
		var quoted = style
		quoted.bodySize = style.bodySize * 0.97
		quoted.textColor = style.quoteTextColor
		let inner = BlockComposer(style: quoted, columnWidth: max(columnWidth - indent, 1))
		return Quote(
			children: blocks.map { inner.mark(for: $0) },
			barWidth: barWidth,
			indent: indent,
			color: style.accentColor,
			trailing: style.blockSpacing
		)
	}
}