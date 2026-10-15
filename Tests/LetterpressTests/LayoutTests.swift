import Testing
@testable import Letterpress

/// measure `mark` at the given proposal.
private func sizeOf(_ mark: any Mark, proposal: ProposedSize = .unconstrained) -> Size {
	var context = MeasureContext()
	return mark.sizeThatFits(proposal, in: &context)
}

/// a custom flexible mark: draws nothing but claims and absorbs leftover.
private struct MinPad: FlexibleMark {
	let minimumLength: Double
	func write(to renderer: inout Renderer) {}
	func sizeThatFits(_ proposal: ProposedSize, in context: inout MeasureContext) -> Size {
		Size(width: minimumLength, height: 0)
	}
}

/// compare doubles within a tiny tolerance (float layout math is not
/// guaranteed binary-exact across operations).
private func approxEqual(_ a: Double, _ b: Double, tolerance: Double = 0.0005) -> Bool {
	abs(a - b) <= tolerance
}


// MARK: - measurement

@Suite struct MeasurementTests {
	@Test("single-line text reports its exact advance and one line height")
	func textSize() {
		let size = sizeOf(Text("a").font(.helvetica, size: 12))
		#expect(approxEqual(size.width, Font.helvetica.width(of: "a", size: 12)))
		#expect(approxEqual(size.height, 15))
	}

	@Test("embedded newlines stack lines at size times line height")
	func textHeight() {
		let size = sizeOf(Text("a\nb").font(.helvetica, size: 12))
		#expect(approxEqual(size.width, Font.helvetica.width(of: "a", size: 12)))
		#expect(approxEqual(size.height, 30))
	}

	@Test("line height modifier multiplies the reported height")
	func lineHeightAffectsSize() {
		let size = sizeOf(Text("a\nb").font(.helvetica, size: 12).lineHeight(2))
		#expect(approxEqual(size.height, 48))
	}

	@Test("paragraph wraps to its frame width and reports both dimensions")
	func frameWidthWraps() {
		let size = sizeOf(Paragraph("aa aa aa aa aa aa aa").font(.helvetica, size: 12).frame(maxWidth: 100))
		#expect(approxEqual(size.height, 30))  // five words fit line one
		#expect(approxEqual(size.width, 96.744))
	}

	@Test("paragraph wraps to a finite width proposal")
	func proposalWraps() {
		let size = sizeOf(Paragraph("aa aa aa aa aa aa aa").font(.helvetica, size: 12),
						  proposal: ProposedSize(width: 100))
		#expect(approxEqual(size.height, 30))
		#expect(approxEqual(size.width, 96.744))
	}

	@Test("unbounded proposal leaves paragraph unwrapped")
	func unboundProposalDoesNotWrap() {
		let size = sizeOf(Paragraph("aa aa aa aa aa aa aa").font(.helvetica, size: 12))
		#expect(approxEqual(size.height, 15))
	}

	@Test("fixed-geometry shapes ignore proposals")
	func shapesIgnoreProposals() {
		let rect = sizeOf(Rect(x: 0, y: 0, width: 200, height: 100), proposal: ProposedSize(width: 50, height: 50))
		#expect(rect == Size(width: 200, height: 100))
		let ellipse = sizeOf(Ellipse(x: 0, y: 0, width: 80, height: 40))
		#expect(ellipse == Size(width: 80, height: 40))
		let line = sizeOf(Line(from: Point(x: 0, y: 10), to: Point(x: 30, y: 25)))
		#expect(line == Size(width: 30, height: 15))
		let polygon = sizeOf(Polygon([Point(x: 0, y: 0), Point(x: 40, y: 0), Point(x: 40, y: 20)]))
		#expect(polygon == Size(width: 40, height: 20))
	}

	@Test("paint and placement do not affect measurement; stroke bleeds")
	func modifierPassthrough() {
		let plain = sizeOf(Text("a").font(.helvetica, size: 12))
		// placement is size-neutral
		#expect(sizeOf(Text("a").font(.helvetica, size: 12).at(x: 99, y: 99)) == plain)
		// paint is size-neutral, but only a PATH can be painted — so the paint
		// cases use a shape, never a text mark.
		let rect = sizeOf(Rect(x: 0, y: 0, width: 40, height: 20))
		#expect(sizeOf(Rect(x: 0, y: 0, width: 40, height: 20).fill(.red)) == rect)
		let stroked = sizeOf(Rect(x: 0, y: 0, width: 40, height: 20).stroke(.blue, width: 2))
		#expect(approxEqual(stroked.width, rect.width + 2))
		#expect(approxEqual(stroked.height, rect.height + 2))
		let retimed = sizeOf(Text("a").font(.times, size: 24))
		#expect(approxEqual(retimed.width, Font.times.width(of: "a", size: 24)))
		#expect(approxEqual(retimed.height, 30))
	}
}

// MARK: - stacks

@Suite struct StackLayoutTests {
	@Test("vstack sums main extents, spacing, and cross maximum")
	func vstackSize() {
		let size = sizeOf(VStack(spacing: 8) {
			Text("a").font(.helvetica, size: 12)
			Text("bb").font(.helvetica, size: 12)
		})
		#expect(approxEqual(size.width, 13.344))  // cross = widest child
		#expect(approxEqual(size.height, 15 + 8 + 15))
	}

	@Test("hstack sums along the x axis")
	func hstackSize() {
		let size = sizeOf(HStack(spacing: 4) {
			Text("a").font(.helvetica, size: 12)
			Text("bb").font(.helvetica, size: 12)
		})
		#expect(approxEqual(size.width, 6.672 + 4 + 13.344))
		#expect(approxEqual(size.height, 15))
	}

	@Test("empty containers measure zero and emit nothing")
	func emptyStack() {
		let emptyV = sizeOf(VStack { })
		let emptyH = sizeOf(HStack { })
		let emptyZ = sizeOf(ZStack { })
		#expect(emptyV == .zero)
		#expect(emptyH == .zero)
		#expect(emptyZ == .zero)
		let doc = PDFDocument {
			PDFPage(.a4) { VStack { } }
		}
		#expect(allContentStreams(doc).isEmpty)
	}

	@Test("single-child containers report the child size")
	func singleChild() {
		let size = sizeOf(VStack { Text("a").font(.helvetica, size: 12) })
		#expect(approxEqual(size.width, 6.672))
		#expect(approxEqual(size.height, 15))
	}

	@Test("vstack cross alignment offsets children within the column")
	func vstackAlignment() {
		let doc = PDFDocument {
			PDFPage(.a4) {
				VStack(alignment: .center) {
					Text("a").font(.helvetica, size: 12)
					Text("bb").font(.helvetica, size: 12)
				}
				.at(x: 100, y: 100)
			}
		}
		let s = allContentStreams(doc)
		// "a" is centered across the 13.344 column; both offsets ride the
		// transform, so child text stays anchored at its local origin.
		#expect(s.contains("1 0 0 1 103.34 -100 cm"))
		#expect(s.contains("1 0 0 1 0 832.29 Tm"))
		#expect(s.contains("1 0 0 1 100 -115 cm"))
	}

	@Test("vstack spacing offsets the second line")
	func vstackSpacing() {
		let doc = PDFDocument {
			PDFPage(.a4) {
				VStack(spacing: 8) {
					Text("a").font(.helvetica, size: 12)
					Text("b").font(.helvetica, size: 12)
				}
				.at(x: 100, y: 100)
			}
		}
		let s = allContentStreams(doc)
		#expect(s.contains("1 0 0 1 100 -100 cm"))
		#expect(s.contains("1 0 0 1 0 832.29 Tm"))
		// second line top at 100 + 15 + 8 = 123, carried by the transform.
		#expect(s.contains("1 0 0 1 100 -123 cm"))
	}

	@Test("zstack takes the extent of the largest child and writes in order")
	func zstack() {
		let size = sizeOf(ZStack {
			Spacer(minimumLength: 50)
			Text("a").font(.helvetica, size: 12)
		})
		#expect(size == Size(width: 50, height: 15))
		let doc = PDFDocument {
			PDFPage(.a4) {
				ZStack {
					Rect(x: 0, y: 0, width: 40, height: 40).fill(.red)
					Text("top").font(.helvetica, size: 12).at(x: 5, y: 5)
				}
			}
		}
		let s = allContentStreams(doc)
		let rectIndex = s.firstRange(of: " re")!.lowerBound
		let textIndex = s.firstRange(of: "(top)")!.lowerBound
		#expect(rectIndex < textIndex)
	}

	@Test("a width-dependent child measures inside a zstack as it draws")
	func zstackMeasuresUnderProposal() {
		// a BARE paragraph (no frame): its wrap follows the ambient width, so
		// measuring it unconstrained reports a height it does not draw.
		let paragraph = Paragraph("aa aa aa aa aa aa aa aa aa aa aa aa aa aa aa aa")
			.font(.helvetica, size: 12)
		let column = ProposedSize(width: 100, height: nil)
		// it really does wrap at this width …
		#expect(sizeOf(paragraph, proposal: column).height > sizeOf(paragraph).height)
		// … so the stack must report the wrapped height, not the unwrapped one.
		#expect(sizeOf(ZStack { paragraph }, proposal: column).height
			== sizeOf(paragraph, proposal: column).height)
	}
}

// MARK: - flex distribution

@Suite struct FlexDistributionTests {
	private func hstackCentered() -> PDFDocument {
		PDFDocument {
			PDFPage(.a4) {
				HStack(alignment: .center) {
					Spacer()
					Text("a").font(.helvetica, size: 12)
					Spacer()
				}
				.frame(maxWidth: 300)
				.at(x: 72, y: 72)
			}
		}
	}

	@Test("two spacers split leftover equally under a finite proposal")
	func equalSplit() {
		let doc = hstackCentered()
		let s = allContentStreams(doc)
		// fixed content 6.672; leftover 293.328 split two ways -> text at 146.664,
		// emitted at 2 decimals (146.66) plus the page origin (72) = 218.66.
		#expect(s.contains("1 0 0 1 218.66 -72 cm"))
		#expect(s.contains("1 0 0 1 0 832.29 Tm"))
	}

	@Test("no finite proposal: spacers collapse to their minimum and stack hugs")
	func hugWithoutProposal() {
		let size = sizeOf(HStack {
			Spacer(minimumLength: 10)
			Text("a").font(.helvetica, size: 12)
		})
		#expect(approxEqual(size.width, 16.672))
	}

	@Test("tight proposal overflows rather than compressing")
	func tightProposalOverflows() {
		let size = sizeOf(HStack {
			Spacer(minimumLength: 10)
			Text("a").font(.helvetica, size: 12)
		}, proposal: ProposedSize(width: 10))
		#expect(approxEqual(size.width, 16.672))
	}

	@Test("flexible minimums are respected before distribution")
	func minimumsRespected() {
		let size = sizeOf(HStack {
			Spacer(minimumLength: 20)
			Text("a").font(.helvetica, size: 12)
			Spacer()
		}, proposal: ProposedSize(width: 100))
		// fixed = 20 + 6.672; leftover 73.328 split -> first spacer 56.664, second 36.664.
		#expect(approxEqual(size.width, 100))
		let doc = PDFDocument {
			PDFPage(.a4) {
				HStack {
					Spacer(minimumLength: 20)
					Text("a").font(.helvetica, size: 12)
					Spacer()
				}
				.frame(maxWidth: 100)
			}
		}
		let s = allContentStreams(doc)
		// first spacer 20 + 36.664 = 56.664 -> text at 56.66.
		#expect(s.contains("1 0 0 1 56.66 0 cm"))
		#expect(s.contains("1 0 0 1 0 832.29 Tm"))
	}

	@Test("custom flexible marks participate in distribution")
	func customFlexible() {
		let size = sizeOf(HStack {
			MinPad(minimumLength: 5)
			Text("a").font(.helvetica, size: 12)
			MinPad(minimumLength: 5)
		}.frame(maxWidth: 30))
		#expect(approxEqual(size.width, 30))
		let doc = PDFDocument {
			PDFPage(.a4) {
				HStack {
					MinPad(minimumLength: 5)
					Text("a").font(.helvetica, size: 12)
					MinPad(minimumLength: 5)
				}
				.frame(maxWidth: 30)
			}
		}
		let s = allContentStreams(doc)
		// fixed 5 + 6.672 + 5 = 16.672; leftover 13.328 split -> each pad
		// holds 6.664, so the text starts at 11.664 behind the first pad.
		#expect(s.contains("1 0 0 1 11.66 0 cm"))
	}
}

// MARK: - frame modifier

@Suite struct FrameModifierTests {
	@Test("frame proposes a finite width that re-wraps paragraphs")
	func frameWrapsParagraph() {
		let size = sizeOf(Paragraph("aa aa aa aa aa aa aa").font(.helvetica, size: 12).frame(maxWidth: 100))
		#expect(approxEqual(size.height, 30))
		#expect(approxEqual(size.width, 96.744))
	}

	@Test("frame caps a fixed shape's reported size at the max bound")
	func frameOverShape() {
		let size = sizeOf(Rect(x: 0, y: 0, width: 200, height: 100).frame(maxWidth: 50))
		#expect(size == Size(width: 50, height: 100))
	}

	@Test("nested frames take the inner bound")
	func nestedFrames() {
		let size = sizeOf(Paragraph("aa aa aa aa aa aa aa").font(.helvetica, size: 12)
			.frame(maxWidth: 300).frame(maxWidth: 100))
		#expect(approxEqual(size.height, 30))
	}

	@Test("frame caps a fixed stack's reported size at the bound")
	func frameCapsStack() {
		let size = sizeOf(HStack { Text("a").font(.helvetica, size: 12) }.frame(maxWidth: 5))
		#expect(approxEqual(size.width, 5))
	}

	@Test("min width forces the box larger than the content")
	func frameMinWidthForcesBox() {
		let size = sizeOf(Text("a").font(.helvetica, size: 12).frame(minWidth: 40))
		#expect(approxEqual(size.width, 40))
		#expect(approxEqual(size.height, 15))
	}

	@Test("alignment centers content inside a widened box")
	func frameAlignmentCenters() {
		let doc = PDFDocument {
			PDFPage(.a4) {
				Text("a").font(.helvetica, size: 12)
					.frame(minWidth: 40, alignment: .center)
					.at(x: 50, y: 100)
			}
		}
		let s = allContentStreams(doc)
		// box 40 wide, content 6.672 -> shift (40 - 6.672) / 2 = 16.664,
		// carried by the frame's transform on top of the page origin.
		#expect(s.contains("1 0 0 1 16.66 0 cm"))
	}

	@Test("a min/max band locks the box and re-wraps inside it")
	func fixedWidthColumn() {
		let size = sizeOf(VStack {
			Paragraph("aa aa aa aa aa aa aa").font(.helvetica, size: 12)
		}.frame(minWidth: 100, maxWidth: 100))
		#expect(approxEqual(size.width, 100))
		#expect(approxEqual(size.height, 30))
	}

	@Test("ideal width is proposed when the axis is unconstrained")
	func idealWidthProposed() {
		let size = sizeOf(Paragraph("aa aa aa aa aa aa aa").font(.helvetica, size: 12).frame(idealWidth: 100))
		#expect(approxEqual(size.height, 30))
	}

	@Test("stroke bleed is included in the measured extent")
	func strokeBleed() {
		let size = sizeOf(Rect(x: 0, y: 0, width: 100, height: 50).stroke(.red, width: 4))
		#expect(size == Size(width: 104, height: 54))
	}
}

// MARK: - nesting

@Suite struct NestingTests {
	@Test("nested stacks compose their extents")
	func nestedSizes() {
		let size = sizeOf(HStack(alignment: .center, spacing: 4) {
			VStack(spacing: 6) {
				Text("a").font(.helvetica, size: 12)
				Text("bb").font(.helvetica, size: 12)
			}
			Text("c").font(.helvetica, size: 12)
		})
		// inner column: 13.344 wide, 36 tall. row: 13.344 + 4 + 6.0 ('c' is 500 units).
		#expect(approxEqual(size.width, 23.344))
		#expect(approxEqual(size.height, 36))
	}

	@Test("at on the container positions the whole subtree")
	func atPositionsSubtree() {
		let doc = PDFDocument {
			PDFPage(.a4) {
				VStack(spacing: 8) {
					Text("a").font(.helvetica, size: 12)
					Text("b").font(.helvetica, size: 12)
				}
				.at(x: 50, y: 200)
			}
		}
		let s = allContentStreams(doc)
		#expect(s.contains("1 0 0 1 50 -200 cm"))
		#expect(s.contains("1 0 0 1 0 832.29 Tm"))
		#expect(s.contains("1 0 0 1 50 -223 cm"))
	}
}

// MARK: - determinism

@Suite struct DeterminismTests {
	@Test("stack layout renders byte-identically across runs")
	func deterministic() {
		func build() -> [UInt8] {
			PDFDocument {
				PDFPage(.a4) {
					VStack(spacing: 8) {
						Text("hello").font(.helveticaBold, size: 24)
						HStack(alignment: .center) {
							Spacer()
							Paragraph("aa aa aa aa aa aa aa").font(.times, size: 12).frame(maxWidth: 80)
							Spacer()
						}
						.frame(maxWidth: 300)
					}
					.at(x: 72, y: 72)
				}
			}
			.render()
		}
		let first = build()
		let second = build()
		#expect(first == second)
		#expect(!first.isEmpty)
	}
}
