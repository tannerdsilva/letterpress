import Letterpress

// MARK: - the document → pages bridge

extension MarkdownDocument {
	/// typeset this document into a paginated pdf under `style`.
	///
	/// the whole document is one `Galley`: it measures each top-level block at
	/// the text-column width and breaks between blocks, so a long document
	/// spills onto as many physical pages as it needs with no manual paging.
	public func pdfDocument(style: MarkdownStyle = .standard) -> PDFDocument {
		let composer = BlockComposer(style: style, columnWidth: style.contentWidth)
		let marks: [any Mark] = blocks.map { composer.mark(for: $0) }
		return PDFDocument {
			Galley(style.pageSize, margins: style.margins, spacing: 0) {
				marks
			}
		}
	}

	/// render this document straight to pdf bytes under `style`.
	public func render(style: MarkdownStyle = .standard) -> [UInt8] {
		pdfDocument(style: style).render()
	}
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

	func mark(for block: Block) -> any Mark {
		switch block {
		case .heading(let level, let runs):
			return heading(level: level, runs: runs)
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
		case .rule:
			return rule()
		}
	}

	// MARK: leaves

	private func heading(level: Int, runs: [InlineRun]) -> any Mark {
		// headings are bold regardless of the source's own emphasis bits.
		let emphasised = runs.map { InlineRun($0.text, traits: $0.traits.union(.bold), url: $0.url) }
		return VStack(alignment: .leading, spacing: 0) {
			Gap(height: style.blockSpacing * (level == 1 ? 2.0 : 1.5))
			text(emphasised, size: style.headingSize(level), lineHeight: 1.25, color: style.headingColor)
			Gap(height: style.blockSpacing * 0.6)
		}
	}

	private func paragraph(_ runs: [InlineRun]) -> any Mark {
		VStack(alignment: .leading, spacing: 0) {
			text(runs, size: style.bodySize, lineHeight: style.lineHeight, color: style.textColor)
			Gap(height: style.blockSpacing)
		}
	}

	private func rule() -> any Mark {
		VStack(alignment: .leading, spacing: 0) {
			Gap(height: style.blockSpacing * 0.6)
			Rect(x: 0, y: 0, width: columnWidth, height: 0.8).fill(style.barColor)
			Gap(height: style.blockSpacing * 0.6)
		}
	}

	private func code(_ text: String) -> any Mark {
		VStack(alignment: .leading, spacing: 0) {
			CodeBlock(
				text: text,
				width: columnWidth,
				codeTypeface: style.codeTypeface,
				size: style.codeSize,
				color: style.codeColor,
				background: style.codeBackground
			)
			Gap(height: style.blockSpacing)
		}
	}

	private func text(_ runs: [InlineRun], size: Double, lineHeight: Double, color: Color) -> RichText {
		RichText(
			runs: runs,
			width: columnWidth,
			size: size,
			lineHeight: lineHeight,
			typeface: style.typeface,
			codeTypeface: style.codeTypeface,
			color: color,
			linkColor: style.linkColor,
			codeColor: style.codeColor
		)
	}

	// MARK: containers

	private func list(items: [ListItem], ordered: Bool, start: Int) -> any Mark {
		let markers = items.enumerated().map { index, _ in
			ordered ? "\(start + index)." : "•"
		}
		let markerFont = style.typeface.font(bold: false, italic: false)
		let widest = markers.map { markerFont.width(of: $0, size: style.bodySize) }.max() ?? 0
		// the bullet glyph is non-ascii and measures at the fallback advance,
		// so reserve at least a digit's width plus a small gutter.
		let markerColumn = (max(widest, markerFont.width(of: "0", size: style.bodySize)) + 6).rounded(.up)
		let itemWidth = max(columnWidth - markerColumn, 1)
		let inner = BlockComposer(style: style, columnWidth: itemWidth)

		let itemMarks: [any Mark] = items.enumerated().map { index, item in
			HStack(alignment: .top, spacing: 0) {
				Text(markers[index])
					.font(markerFont, size: style.bodySize)
					.foregroundColor(style.textColor)
					.frame(minWidth: markerColumn, alignment: .leading)
				VStack(alignment: .leading, spacing: 0) {
					item.blocks.map { inner.mark(for: $0) }
				}
			}
		}

		return VStack(alignment: .leading, spacing: style.itemSpacing) {
			itemMarks
			Gap(height: style.blockSpacing)
		}
	}

	private func quote(_ blocks: [Block]) -> any Mark {
		let indent: Double = 12
		let barWidth: Double = 2.5
		let inner = BlockComposer(style: style, columnWidth: max(columnWidth - indent, 1))
		let content = VStack(alignment: .leading, spacing: 0) {
			blocks.map { inner.mark(for: $0) }
		}
		// the bar must span the quoted content, so measure it first.
		var context = MeasureContext()
		let height = content.sizeThatFits(ProposedSize(width: nil, height: nil), in: &context).height

		return VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .top, spacing: 0) {
				Rect(x: 0, y: 0, width: barWidth, height: height).fill(style.barColor)
				Gap(width: indent - barWidth)
				content
			}
			Gap(height: style.blockSpacing)
		}
	}
}